#!/bin/bash
# Shared helpers for the smoke-test suite (see PLAN.md §3a).
#
# Assumes `docker` is on PATH -- either real Docker (build-test/T-jobs) or a
# podman shim (the podman job, see tests/podman-shim/docker). tutorial.sh
# itself hardcodes `docker`; fase 2 adds runtime detection there. Until
# then, these test scripts follow the same assumption.

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

# Starts all 4 containers without blocking on the interactive nutsh menu.
# nutsh reads from stdin (pointed at /dev/null here); it keeps printing the
# menu and waiting rather than exiting, so the container stays up and we can
# `docker exec` into it for scripted checks.
start_environment() {
    "${LIB_BASEDIR}/tutorial.sh" --remove >/dev/null 2>&1 || true
    ( cd "${LIB_BASEDIR}" && setsid ./tutorial.sh </dev/null >/tmp/tutorial-start.log 2>&1 & )
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
