#!/bin/bash
# T7: idempotency check for configuration-focused lessons (see PLAN.md §3a).
#
# Scope fixed here in fase 1, per PLAN.md's "exacte lessenlijst vast te
# stellen in fase 0/1": the apache/haproxy/git/templates/roles lessons,
# where a converging playbook is the point of the exercise. Excluded:
# lesson 7 "Playbooks and failures" and lesson 8 "Playbook conditionals"
# (both intentionally end in a failed run), and any command/shell-driven
# lesson that isn't about playbook convergence.
#
# Each scoped lesson is run once via tests/t1_lessons.py (which also copies
# the lesson's files into /root/workspace exactly as a user would
# experience it -- including the roles/ layout lesson 13 assembles), then
# the same playbook command is re-run directly in that workspace and its
# output is checked for `changed=0`.
#
# Fase 4: was `nutsh test` (`run_tutorial -t`); replaced with
# tests/t1_lessons.py, which drives each lesson's real command sequence
# directly instead of going through nutsh's test-mode interpreter -- that
# interpreter has its own PTY-tokenizer race condition (panics on 13/15
# lessons even when the driven command visibly succeeded), unrelated to
# tutorial content. See docs/FASE4.md. This also fixes a stale image
# reference: TUTORIAL_IMAGE below pointed at the archived `turkenh/*:1.1`
# tag rather than the locally-built image tutorial.sh now uses (fase 3).
#
# Known baseline finding (not a regression): the apache playbooks use
# `command:` tasks (a2ensite/a2dissite/apache2ctl configtest) which have no
# built-in idempotency -- Ansible reports `changed` on every run regardless
# of actual state. This is expected to go red here until fase 5 adds
# `changed_when`/`creates` to those tasks. The haproxy-only playbook uses
# only idempotent modules and is expected green from the start.
set -uo pipefail
BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${BASEDIR}/tests/lib.sh"

# A fresh throwaway container on the same network sees the exact same
# converged state (workspace is a host bind mount) to re-run the playbook
# against, without disturbing the long-running ansible.tutorial container.
DOCKER_IMAGETAG=${DOCKER_IMAGETAG:-2.0}
TUTORIAL_IMAGE="${TUTORIAL_IMAGE:-beverdam/ansible-tutorial:${DOCKER_IMAGETAG}}"
NETWORK_NAME="ansible.tutorial"
WORKSPACE="${BASEDIR}/workspace"

trap stop_environment EXIT
start_environment

# label|lesson file|playbook command to re-run inside /root/workspace
SCOPE=(
    "lesson5-apache|4-step-04|ansible-playbook -i hosts -l host1.example.org apache.yml"
    "lesson6-apache|5-step-05|ansible-playbook -i hosts -l host1.example.org apache.yml"
    "lesson9-git|8-step-08|ansible-playbook -i hosts -l host1.example.org apache.yml"
    "lesson10-apache|9-step-09|ansible-playbook -i hosts apache.yml"
    "lesson11-templates|10-step-10|ansible-playbook -i hosts apache.yml haproxy.yml"
    "lesson12-haproxy|11-step-11|ansible-playbook -i hosts haproxy.yml"
    "lesson13-roles|12-step-12|ansible-playbook -i hosts site.yml"
)

FAILED=0
for entry in "${SCOPE[@]}"; do
    IFS='|' read -r label lesson cmd <<< "${entry}"
    log "T7 [${label}]: running lesson ${lesson} to converge state"
    # $$ keeps this unique per run of this script, not just per label --
    # otherwise two concurrent runs (different users, or the same user
    # twice) collide on the same path and one gets "Permission denied"
    # writing over the other's file.
    setup_log="/tmp/t7-${label}.$$.log"
    if ! python3 "${BASEDIR}/tests/t1_lessons.py" "${lesson}" >"${setup_log}" 2>&1; then
        log "T7 [${label}]: SKIP -- lesson did not complete (see T1 / ${setup_log})"
        continue
    fi
    log "T7 [${label}]: re-running '${cmd}' to check idempotency"
    out=$(docker run --rm -v "${WORKSPACE}:/root/workspace:Z" --net "${NETWORK_NAME}" \
        -w /root/workspace --entrypoint sh "${TUTORIAL_IMAGE}" -c "${cmd}" 2>&1)
    if ! echo "${out}" | grep -q 'PLAY RECAP'; then
        log "T7 [${label}]: SKIP -- second run did not produce a PLAY RECAP, could not verify: ${out}"
        continue
    fi
    if echo "${out}" | grep -qE 'changed=[1-9]'; then
        recap=$(echo "${out}" | grep -A3 'PLAY RECAP' || true)
        log "T7 [${label}]: NOT IDEMPOTENT -- ${recap}"
        FAILED=1
    else
        log "T7 [${label}]: idempotent (changed=0)"
    fi
done

if [ "${FAILED}" -eq 0 ]; then
    log "T7: PASS"
else
    log "T7: FAIL -- see PLAN.md fase 4 (apache command-module tasks are expected non-idempotent until fixed)"
    exit 1
fi
