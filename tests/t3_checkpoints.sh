#!/bin/bash
# T3: host-side checkpoint test (see PLAN.md §3a).
#
# Runs a lesson end-to-end via tests/t1_lessons.py, then verifies from
# *outside* the containers (like a tutorial user would) that the port
# mapping the lesson promises actually serves the expected service.
#
# Fase 4: was `nutsh test` (`run_tutorial -t`); replaced with
# tests/t1_lessons.py for the same reason as T7 -- nutsh's test-mode
# interpreter has its own PTY-tokenizer race condition, unrelated to
# tutorial content. See docs/FASE4.md.
#
# Usage: t3_checkpoints.sh <apache|jenkins>
#   apache  -- lesson 5 "Playbooks" (file 4-step-04): apache on host1.example.org
#   jenkins -- lesson 14 "...Jenkins server" (file 13-step-13): jenkins on host0.example.org
#              expected-fail at baseline, see issues #32/#39 (docs/FASE4.md
#              has a more precise diagnosis: it now gets much further than
#              before -- 22 tasks ok -- and fails on the final "start
#              jenkins" step with a classic-service-module SysV
#              status-parsing quirk, not the java-dependency issue #32
#              originally described).
set -uo pipefail
BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${BASEDIR}/tests/lib.sh"

HOSTPORT_BASE="${HOSTPORT_BASE:-42726}"
export HOSTPORT_BASE

trap stop_environment EXIT
start_environment

curl_check() {
    local desc="$1" url="$2" status
    status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${url}")
    [ -z "${status}" ] && status="000"
    if [ "${status}" == "200" ]; then
        log "T3: ${desc} -> HTTP ${status} OK"
        return 0
    fi
    log "T3: CHECK FAILED: ${desc} -> HTTP ${status} (expected 200)"
    return 1
}

case "${1:-}" in
    apache)
        python3 "${BASEDIR}/tests/t1_lessons.py" 4-step-04 || fail "lesson 4-step-04 (apache) did not complete"
        curl_check "apache on host1.example.org (lesson 5)" "http://127.0.0.1:$((HOSTPORT_BASE + 1))/"
        ;;
    jenkins)
        python3 "${BASEDIR}/tests/t1_lessons.py" 13-step-13 \
            || log "T3: lesson 13-step-13 (jenkins) did not complete cleanly -- expected, see #32/#39 and docs/FASE4.md"
        curl_check "jenkins on host0.example.org (lesson 14)" "http://127.0.0.1:$((HOSTPORT_BASE + 3))/"
        ;;
    *)
        echo "usage: $0 <apache|jenkins>" >&2
        exit 2
        ;;
esac
