#!/bin/bash
set -euo pipefail

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

NOF_HOSTS=3
NETWORK_NAME="ansible.tutorial"
WORKSPACE="${BASEDIR}/workspace"
TUTORIALS_FOLDER="${BASEDIR}/tutorials"

HOSTPORT_BASE=${HOSTPORT_BASE:-42726}
# Extra ports per host to expose. Should contain $NOF_HOSTS variables
EXTRA_PORTS=( "8080" "30000" "443" )
# Port Mapping
# +-----------+----------------+-------------------+
# | Container | Container Port |     Host Port     |
# +-----------+----------------+-------------------+
# |   host0   |       80       | $HOSTPORT_BASE    |
# +-----------+----------------+-------------------+
# |   host1   |       80       | $HOSTPORT_BASE+1  |
# +-----------+----------------+-------------------+
# |   host2   |       80       | $HOSTPORT_BASE+2  |
# +-----------+----------------+-------------------+
# |   host0   | EXTRA_PORTS[0] | $HOSTPORT_BASE+3  |
# +-----------+----------------+-------------------+
# |   host1   | EXTRA_PORTS[1] | $HOSTPORT_BASE+4  |
# +-----------+----------------+-------------------+
# |   host2   | EXTRA_PORTS[2] | $HOSTPORT_BASE+5  |
# +-----------+----------------+-------------------+

# As of fase 3, images are built locally from images/ (see images/Makefile)
# rather than pulled from turkenh's Docker Hub namespace: those `:1.1` tags
# are on a 5-year-stale ubuntu:16.04 base whose apt mirrors are archived, so
# they can no longer be rebuilt. `make build_all` in images/ produces these
# tags locally; override DOCKER_IMAGETAG/*_IMAGE to point elsewhere (e.g. a
# pushed registry image) if you're not building locally.
DOCKER_IMAGETAG=${DOCKER_IMAGETAG:-2.0}
DOCKER_HOST_IMAGE="${DOCKER_HOST_IMAGE:-beverdam/ansible-managed-host:${DOCKER_IMAGETAG}}"
TUTORIAL_IMAGE="${TUTORIAL_IMAGE:-beverdam/ansible-tutorial:${DOCKER_IMAGETAG}}"

# Container runtime. Honor an explicit override, otherwise default to the
# `docker` command -- a podman-docker shim on PATH also answers to `docker`,
# so this works under both engines without hardcoding one. We deliberately do
# NOT branch on the binary *name* to pick an engine (Fedora/RHEL's
# podman-docker is literally named `docker`); podman compatibility is instead
# achieved by only using inspect/run invocations that behave the same on both
# (see setupFiles: per-container inspect rather than a podman-incompatible
# `network inspect --format ...IPv4Address` template). See tests/podman-shim.
CONTAINER_ENGINE="${CONTAINER_ENGINE:-docker}"

function help() {
    echo -ne "-h, --help              prints this help message
-r, --remove            remove created containers and network
-t, --test              run lesson tests
"
}

function doesImageExist() {
    "${CONTAINER_ENGINE}" image inspect "$1" >/dev/null 2>&1
}

function ensureImagesBuilt() {
    if doesImageExist "${DOCKER_HOST_IMAGE}" && doesImageExist "${TUTORIAL_IMAGE}"; then
        return
    fi
    echo "Images not found locally -- building them now (images/Makefile), this only happens once."
    if ! command -v make >/dev/null 2>&1; then
        echo "Could not find 'make'. Install it, or build the images yourself: (cd images && make build_all)" >&2
        exit 1
    fi
    # Pass our resolved CONTAINER_ENGINE through explicitly -- it's a plain
    # (non-exported) shell variable here, so `make` wouldn't otherwise see
    # it, and images/Makefile's own build/push targets need it to build
    # with the same engine tutorial.sh itself is about to use.
    make -C "${BASEDIR}/images" build_all CONTAINER_ENGINE="${CONTAINER_ENGINE}"
}

function doesNetworkExist() {
    "${CONTAINER_ENGINE}" network inspect "$1" >/dev/null 2>&1
}

function removeNetworkIfExists() {
    if doesNetworkExist "$1"; then
        echo "removing network $1"
        "${CONTAINER_ENGINE}" network rm "$1" >/dev/null
    fi
}

function doesContainerExist() {
    "${CONTAINER_ENGINE}" inspect "$1" >/dev/null 2>&1
}

function isContainerRunning() {
    [[ "$("${CONTAINER_ENGINE}" inspect -f "{{.State.Running}}" "$1" 2>/dev/null)" == "true" ]]
}

function killContainerIfExists() {
    if doesContainerExist "$1"; then
        echo "killing/removing container $1"
        "${CONTAINER_ENGINE}" kill "$1" >/dev/null 2>&1 || true
        "${CONTAINER_ENGINE}" rm "$1" >/dev/null 2>&1 || true
    fi
}

function runHostContainer() {
    local name=$1
    local image=$2
    local index=$3
    local port1=$((HOSTPORT_BASE + index))
    local port2=$((HOSTPORT_BASE + index + NOF_HOSTS))

    echo "starting container ${name}: mapping hostport ${port1} -> container port 80 && hostport ${port2} -> container port ${EXTRA_PORTS[${index}]}"
    if doesContainerExist "${name}"; then
        "${CONTAINER_ENGINE}" start "${name}" > /dev/null
    else
        "${CONTAINER_ENGINE}" run -d -p "${port1}:80" -p "${port2}:${EXTRA_PORTS[${index}]}" \
            --net "${NETWORK_NAME}" --name="${name}" "${image}" >/dev/null
    fi
}

function runTutorialContainer() {
    local entrypoint=()
    local args=()
    if [ -n "${TEST}" ]; then
        entrypoint=(--entrypoint nutsh)
        args=(test /tutorials "${LESSON_NAME}")
    fi
    killContainerIfExists ansible.tutorial > /dev/null
    echo "starting container ansible.tutorial"
    local status=0
    "${CONTAINER_ENGINE}" run -it \
      -v "${WORKSPACE}":/root/workspace:Z \
      -v "${TUTORIALS_FOLDER}":/tutorials:Z \
      --net "${NETWORK_NAME}" \
      --env HOSTPORT_BASE="${HOSTPORT_BASE}" \
      "${entrypoint[@]}" --name="ansible.tutorial" "${TUTORIAL_IMAGE}" "${args[@]}" || status=$?
    return "${status}"
}

function remove () {
    for ((i = 0; i < NOF_HOSTS; i++)); do
       killContainerIfExists "host$i.example.org"
    done
    # Best-effort: network removal predictably fails while ansible.tutorial is
    # still attached (it is only killed at the start of a run, not by
    # --remove). Don't let that abort cleanup of everything else. The engine's
    # own error still prints to stderr for visibility.
    removeNetworkIfExists "${NETWORK_NAME}" || true
}

function setupFiles() {
    # step-01/02
    local step_01_hosts_file="${BASEDIR}/tutorials/files/step-1-2/hosts"
    rm -f "${step_01_hosts_file}"
    for ((i = 0; i < NOF_HOSTS; i++)); do
        # Read the container's IP straight from its own inspect data. This is
        # portable across docker and podman -- unlike `network inspect
        # --format "...{{$c.IPv4Address}}"`, whose IPv4Address field does not
        # exist in podman's network container struct (issue #33, left
        # ansible_host= empty). Each host is attached to exactly one network
        # (NETWORK_NAME), so ranging over Networks yields a single IP.
        local ip
        ip=$("${CONTAINER_ENGINE}" inspect \
            -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
            "host$i.example.org")
        echo "host$i.example.org ansible_host=$ip ansible_user=root" >> "${step_01_hosts_file}"
    done
}

function init () {
    ensureImagesBuilt
    mkdir -p "${WORKSPACE}"
    doesNetworkExist "${NETWORK_NAME}" || { echo "creating network ${NETWORK_NAME}" && "${CONTAINER_ENGINE}" network create "${NETWORK_NAME}" >/dev/null; }
    for ((i = 0; i < NOF_HOSTS; i++)); do
       isContainerRunning "host$i.example.org" || runHostContainer "host$i.example.org" "${DOCKER_HOST_IMAGE}" "$i"
    done
    setupFiles
    runTutorialContainer
    exit $?
}

###
MODE="init"
TEST=""
LESSON_NAME="${LESSON_NAME:-}"
for i in "$@"; do
case $i in
    -r|--remove)
    MODE="remove"
    shift # past argument=value
    ;;
    -t|--test)
    TEST="yes"
    shift # past argument=value
    ;;
    -h|--help)
    help
    exit 0
    ;;
    *)
    echo "Unknown argument ${i#*=}"
    exit 1
esac
done

if [ "${MODE}" == "remove" ]; then
    remove
elif [ "${MODE}" == "init" ]; then
    init
fi
exit 0
