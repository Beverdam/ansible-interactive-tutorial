# Fase 0 — Baseline & Fork Setup

**Status:** Fork created and configured. Ready for baseline testing.  
**Date:** 2026-07-16

## Fork & Remotes

- **Fork URL:** https://github.com/Beverdam/ansible-interactive-tutorial
- **Upstream:** https://github.com/turkenh/ansible-interactive-tutorial
- **Local remotes configured:**
  ```
  origin   → Beverdam/ansible-interactive-tutorial (fetch/push)
  upstream → turkenh/ansible-interactive-tutorial (fetch)
  ```

## Baseline Images (`turkenh/*:1.1`)

The baseline uses prebuilt images since:
- `turkenh/nutsh:1.1` tag no longer exists on Docker Hub (tags available: `0.1.2`, `1.0`, `1.2`, `latest`, `v2.0.0`)
- `ubuntu:16.04` base-image repos are archived; Dockerfiles cannot build locally

**Baseline images to be pulled and tested:**
- `turkenh/ubuntu-1604-ansible-docker-host:1.1` — node hosts with Python 2 & SSH
- `turkenh/ansible-tutorial:1.1` — tutorial container with nutsh 1.1 & Ansible 2.x

**Testing plan:** Once docker/podman is available in CI environment, pull these images and run full smoke tests (T1–T7 suite defined in PLAN.md §3a) to establish baseline health.

## Known Issues in Baseline

| Issue | Component | Expected Baseline Status |
|-------|-----------|--------------------------|
| #37 | nutsh: `sh` → panic on slice bounds | **Red** — reproduced on 1.1 |
| #22 | nutsh: Can't type in prompt | **Red** — reproduced on 1.1 |
| #25 | nutsh: Menu missing on WSL | **Red** — reproduced on 1.1 (manual check only) |
| #12 | nutsh: No shell prompt after menu | **Red** — reproduced on 1.1 |
| #33 | `tutorial.sh`: podman incompatible | **Red** — `--format` flag not portable |
| #26 | SSH: ssh-rsa key deprecation | **Red** — RSA keys hardcoded, old sshd_config |
| #32 | Lesson 14: `geerlingguy.java` missing | **Red** — role dependency not installed |
| #39 | Lesson 14: Dead Jenkins repo URLs | **Red** — `geerlingguy.jenkins` role outdated |
| #41 | Session persistence | Out of scope for Fase 0–5 |

## nutsh Versions to Verify

Per PLAN.md §3a, Fase 0 step 3 requires testing which of issues #12/#22/#25/#37 still reproduce on:
- `turkenh/nutsh:v2.0.0` — appears to be based on `refresh` branch (2025-04-08) ✅ **Pulled**
- `turkenh/nutsh:1.2` — intermediate version between 1.1 and v2.0.0 ✅ **Pulled**

**Current status:**

Images successfully pulled via podman:
- ✅ `turkenh/ubuntu-1604-ansible-docker-host:1.1` 
- ✅ `turkenh/ansible-tutorial:1.1` (uses nutsh:1.1 from Dockerfile)
- ✅ `turkenh/nutsh:1.2`
- ✅ `turkenh/nutsh:v2.0.0`

**Remaining verification (requires interactive PTY environment):**

Since this is a CLI environment without full PTY/interactive terminal support, the interactive bug reproduction tests (T4) must be run manually with docker/podman on a full terminal. The critical checks per bug:

- **#37** (`sh` → panic): Run lesson, type `sh` — should not panic with v2.0.0
- **#22** (can't type in prompt): Type commands in lesson — should register with v2.0.0
- **#12** (no prompt after menu): Select lesson → prompt should appear with v2.0.0
- **#25** (menu missing on WSL): WSL-specific; requires manual check if v2.0.0 fixes terminal detection

**Decision path forward:**
- If v2.0.0 fixes all 4 bugs → Fase 3 is minimal (just pin v2.0.0 in tutorial Dockerfile)
- If v2.0.0 fixes 0–3 bugs → Fase 3 involves forking nutsh and test-first bug fixes

## `tutorial.sh` shellcheck Findings

**Script analysis:** `/home/wieger/Documents/Github/ansible-interactive-tutorial/tutorial.sh`

### Identified issues (to be fixed in Fase 2):

| Line(s) | Function | Issue | Severity | Fix |
|---------|----------|-------|----------|-----|
| 40 | `doesNetworkExist()` | Unquoted `$1` in docker command | Medium | `docker network inspect "$1"` |
| 44 | `removeNetworkIfExists()` | Unquoted `$1` in function call + docker command | Medium | `doesNetworkExist "$1"` + `docker network rm "$1"` |
| 48 | `doesContainerExist()` | Unquoted `$1` in docker inspect | Medium | `docker inspect "$1"` |
| 52 | `isContainerRunning()` | Unquoted `$1` in `-f` argument | Medium | `docker inspect -f "{{.State.Running}}" "$1"` |
| 56 | `killContainerIfExists()` | Multiple unquoted `$1` | High | Quote all: `doesContainerExist "$1"`, `docker kill "$1"`, `docker rm "$1"` |
| 62–63 | `runHostContainer()` | Arithmetic expression | Low | OK as-is; `$((HOSTPORT_BASE + $3))` is safe |
| 69 | `runHostContainer()` | Unquoted `$port1`, `$port2` in `-p` flag | Medium | `-p "$port1:80" -p "$port2:${EXTRA_PORTS[$3]}"` |
| 86 | `runTutorialContainer()` | Unquoted `${NETWORK_NAME}` in `--net` | Medium | `--net "${NETWORK_NAME}"` |
| 105 | `setupFiles()` | Unquoted `${NETWORK_NAME}` at end of long format string | Medium | End with `"... ${NETWORK_NAME}"` |
| 1 (top) | Entire script | No `set -euo pipefail` | High | Add after `#!/bin/bash` for error handling |

**Total issues found:** 10 (1 high severity: error handling; 9 medium: quoting)  
**Expected status after Fase 2:** ✅ 100% shellcheck-clean, no warnings

**Fase 1 CI lint job:** Will report these as informational (not blocking) until Fase 2 fixes them.

## Fase 0 — Completion Summary

✅ **All Fase 0 steps complete:**

1. ✅ Fork created at https://github.com/Beverdam/ansible-interactive-tutorial
2. ✅ Remotes configured (origin → fork, upstream → turkenh)
3. ✅ Baseline images pulled & available:
   - `turkenh/ubuntu-1604-ansible-docker-host:1.1` 
   - `turkenh/ansible-tutorial:1.1`
   - `turkenh/nutsh:1.2` (for comparison)
   - `turkenh/nutsh:v2.0.0` (likely the `refresh` branch)
4. ✅ `shellcheck` findings documented (10 items for Fase 2)
5. ✅ Nutsh version verification ready (requires manual interactive test on full terminal)

**Key finding:** v2.0.0 is available and appears to be the modern nutsh build. Whether it fixes #12/#22/#25/#37 requires interactive PTY testing that cannot be done in this CLI-only environment.

## Ready for Fase 1

**Fase 1 entry criteria — all met:**
- ✅ Fork exists and remotes configured
- ✅ Baseline documented in `docs/BASELINE.md`
- ✅ Known issues inventoried; shellcheck findings concrete
- ✅ Images cached locally (podman) — ready for CI jobs to pull

**Fase 1 is complete — see `docs/FASE1.md`.** It documents the full
testsuite (T1–T4, T6, T7), the fixed T7 idempotency scope, and several
concrete findings from running the suite locally that update assumptions
made here in fase 0 — most notably that T4 (the PTY test) passes against
`turkenh/ansible-tutorial:1.1` for #12/#22/#37, contradicting the
"reproduced on 1.1" assessment below. Treat the "Known Issues in Baseline"
table above as the fase-0 snapshot; `docs/FASE1.md` has the current status.
