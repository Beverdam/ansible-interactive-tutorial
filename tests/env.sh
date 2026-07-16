#!/bin/bash
# Thin CLI around lib.sh's environment helpers, so tests that don't need
# the full lifecycle logic themselves (e.g. the T4 PTY test) can just do
# `tests/env.sh up` / `tests/env.sh down` around their own checks.
set -uo pipefail
BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${BASEDIR}/tests/lib.sh"

case "${1:-}" in
    up)
        start_environment
        ;;
    down)
        stop_environment
        ;;
    *)
        echo "usage: $0 <up|down>" >&2
        exit 2
        ;;
esac
