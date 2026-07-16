#!/bin/bash
# T2: build/lifecycle test (see PLAN.md §3a).
#
# Fase 1 uses the pulled `turkenh/*:1.1` images (see docs/BASELINE.md) --
# not `docker build`, which does not work against those Dockerfiles until
# fase 2. Covers: all 4 containers start; the control node reaches the 3
# hosts via fping and ssh; stopping/restarting the tutorial container
# reuses the host containers (the #12 scenario); `--remove` cleans up;
# HOSTPORT_BASE override is honoured.
set -uo pipefail
BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${BASEDIR}/tests/lib.sh"

trap stop_environment EXIT

FAILED=0
check() {
    if ! "$@"; then
        log "CHECK FAILED: $*"
        FAILED=1
        return 1
    fi
    return 0
}

log "T2: pulling baseline images"
docker pull turkenh/ubuntu-1604-ansible-docker-host:1.1
docker pull turkenh/ansible-tutorial:1.1

log "T2: starting full environment (4 containers)"
start_environment

for c in host0.example.org host1.example.org host2.example.org ansible.tutorial; do
    check container_running "$c"
done

log "T2: control node -> hosts reachability (fping)"
check docker exec ansible.tutorial fping host0.example.org host1.example.org host2.example.org

log "T2: control node -> hosts reachability (ssh)"
for h in host0 host1 host2; do
    check docker exec ansible.tutorial ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${h}.example.org" whoami
done

log "T2: stop -> restart reuses host containers (#12 scenario)"
before_id=$(docker inspect -f '{{.Id}}' host0.example.org)
docker kill ansible.tutorial >/dev/null 2>&1
docker rm ansible.tutorial >/dev/null 2>&1
( run_tutorial </dev/null >/tmp/tutorial-restart.log 2>&1 & )
wait_for 60 "ansible.tutorial running again" container_running ansible.tutorial
after_id=$(docker inspect -f '{{.Id}}' host0.example.org)
if [ "${before_id}" != "${after_id}" ]; then
    log "CHECK FAILED: host0.example.org was recreated instead of reused (${before_id} -> ${after_id})"
    FAILED=1
fi

log "T2: --remove cleans up host containers and network"
"${BASEDIR}/tutorial.sh" --remove
container_absent() { ! docker inspect "$1" >/dev/null 2>&1; }
for c in host0.example.org host1.example.org host2.example.org; do
    check container_absent "$c"
done
if container_absent ansible.tutorial; then
    log "T2: NOTE: ansible.tutorial was also removed (not just host containers)"
    if docker network inspect ansible.tutorial >/dev/null 2>&1; then
        log "CHECK FAILED: network ansible.tutorial still exists after --remove"
        FAILED=1
    fi
else
    # Known limitation, not a regression (PLAN.md fase1 step 3): --remove
    # never kills ansible.tutorial (only killed at the start of a run), so
    # while it's still attached, network removal predictably fails too.
    log "T2: NOTE: ansible.tutorial still present after --remove -- known limitation, not a regression (PLAN.md fase1 step 3)"
    if docker network inspect ansible.tutorial >/dev/null 2>&1; then
        log "T2: NOTE: network ansible.tutorial also still exists -- expected consequence of ansible.tutorial still being attached"
    fi
fi

log "T2: HOSTPORT_BASE override"
export HOSTPORT_BASE=45000
start_environment
port_binding=$(docker port host0.example.org 80/tcp 2>/dev/null)
if [[ "${port_binding}" != *:45000 ]]; then
    log "CHECK FAILED: expected host0.example.org port 80 bound to host port 45000, got '${port_binding}'"
    FAILED=1
fi

if [ "${FAILED}" -eq 0 ]; then
    log "T2: PASS"
else
    log "T2: FAIL"
    exit 1
fi
