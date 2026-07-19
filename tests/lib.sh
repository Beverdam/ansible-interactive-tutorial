#!/bin/bash
# Shared helpers for the smoke-test suite (see PLAN.md §3a).
#
# Assumes `docker` is on PATH -- either real Docker (build-test/T-jobs) or a
# podman shim (the podman job, see tests/podman-shim/docker). As of fase 2,
# tutorial.sh is runtime-agnostic (honors CONTAINER_ENGINE, defaults to the
# `docker` command, and only uses inspect/run forms that behave the same on
# docker and podman). These test scripts follow the same assumption: they
# call `docker` directly, which the podman job satisfies via the PATH shim.

LIB_BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
    echo "[$(date +%H:%M:%S)] $*" >&2
}

fail() {
    log "FAIL: $*"
    exit 1
}

# wait_for <timeout_seconds> <description> <command...>
wait_for() {
    local timeout="$1" desc="$2"
    shift 2
    local waited=0
    until "$@" >/dev/null 2>&1; do
        waited=$((waited + 1))
        if [ "$waited" -ge "$timeout" ]; then
            fail "timed out waiting for: ${desc}"
        fi
        sleep 1
    done
}

container_running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == "true" ]
}

# True when `docker` is actually podman (real Docker or the podman-docker
# shim). Detects by *behavior* -- the version string -- not by binary name,
# matching tutorial.sh's runtime handling. Used to relax checks that are
# genuinely unreliable under podman (e.g. ICMP/fping under rootless podman).
is_podman() {
    docker --version 2>/dev/null | grep -qi podman
}

# tutorial.sh always runs `docker run -it` (fase 2 will make that
# runtime-aware; unrelated to the problem here). On real Docker, `-it`
# with stdin that isn't a real terminal (e.g. /dev/null, or a GitHub
# Actions `run:` step, which never allocates one) makes the Docker CLI
# hard-fail client-side with "the input device is not a TTY" before any
# container is even created -- podman only warns and proceeds, which is
# why this doesn't show up when testing locally against the podman shim.
# `script` allocates a real pty for its child regardless of whether its
# own invoker has one, which satisfies Docker's check. `-e` propagates
# the wrapped command's exit code (without it, `script` always exits 0).
run_tutorial() {
    ( cd "${LIB_BASEDIR}" && script -qe -c "./tutorial.sh $*" /dev/null )
}

# Starts all 4 containers without blocking on the interactive nutsh menu.
# nutsh reads from stdin (pointed at /dev/null here); it keeps printing the
# menu and waiting rather than exiting, so the container stays up and we can
# `docker exec` into it for scripted checks.
start_environment() {
    "${LIB_BASEDIR}/tutorial.sh" --remove >/dev/null 2>&1 || true
    # $$ (this shell's PID) keeps the path unique per run -- a fixed shared
    # path lets one user's leftover file block another user's run (or the
    # same user's later run) with a permission error on a multi-user
    # machine.
    ( run_tutorial </dev/null >"/tmp/tutorial-start.$$.log" 2>&1 & )
    wait_for 60 "ansible.tutorial container running" container_running ansible.tutorial
    wait_for 60 "host0.example.org running" container_running host0.example.org
    wait_for 60 "host1.example.org running" container_running host1.example.org
    wait_for 60 "host2.example.org running" container_running host2.example.org
}

stop_environment() {
    docker kill ansible.tutorial >/dev/null 2>&1 || true
    docker rm ansible.tutorial >/dev/null 2>&1 || true
    "${LIB_BASEDIR}/tutorial.sh" --remove >/dev/null 2>&1 || true
}
