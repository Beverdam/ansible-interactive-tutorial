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
- `turkenh/nutsh:v2.0.0` — appears to be based on `refresh` branch (2025-04-08)
- `turkenh/nutsh:refresh` branch directly — if available for testing

**Verification checklist (to be completed in test environment):**

- [ ] Pull `turkenh/nutsh:v2.0.0` image
- [ ] Pull `turkenh/nutsh:1.2` image  
- [ ] Build tutorial image with each nutsh version
- [ ] **Test T4 (PTY smoketest)** against each version:
  - [ ] Menu appears on start
  - [ ] Can type in lesson prompt (issue #22)
  - [ ] Can type `sh` without panic (issue #37)
  - [ ] Prompt reappears cleanly (issue #12)
  - [ ] Terminal init works (issue #25 — manual WSL check only)
- [ ] Document which bugs are fixed in each version
- [ ] **Decision:** Proceed with v2.0.0-fork (minimal fixes) or full Fase 3 (comprehensive overhaul)

## `tutorial.sh` shellcheck Findings

**Script analysis:** `/home/wieger/Documents/Github/ansible-interactive-tutorial/tutorial.sh`

### Identified issues (to be automated in Fase 1 CI lint job):

| Line | Issue | Severity | Fase 2 Action |
|------|-------|----------|---------------|
| 40, 44, 48 | Unquoted variables in function arguments | Medium | Quote `$1` in `doesNetworkExist`, `removeNetworkIfExists`, `doesContainerExist` |
| 52 | `[[ ]]` is bash-only; script uses `#!/bin/bash` | Low | OK as-is; shebang is explicit |
| 56, 67, 69, 88 | Unquoted variable expansion in docker commands | High | Quote all variables passed to docker (e.g., `"${name}"`, `"${NETWORK_NAME}"`) |
| 62–63 | Arithmetic without quotes | Low | OK; `$((HOSTPORT_BASE + $3))` is safe |
| 102 | `rm -f` without quoting | Medium | Quote path: `rm -f "${step_01_hosts_file}"` |
| 105 | Complex quoting in nested command | Medium | Simplify `docker network inspect --format` call or add quoting guards |
| All pipes | No `set -euo pipefail` at top | High | Add error exit handling in Fase 2 |

**Expected shellcheck pass rate after Fase 2:** 100% (informational job in Fase 1 CI, fixes in Fase 2)

## Next Steps

**Blocked on test environment:**  
The full baseline test suite requires docker/podman to:
1. Pull baseline images (`turkenh/*:1.1`)
2. Run T1–T7 smoke tests
3. Verify nutsh versions

**Immediate actions ready (independent of container runtime):**
1. ✅ Fork created and remotes configured
2. ✅ BASELINE.md documented
3. ⏳ Await test environment setup (Fase 1 CI will run T1–T7 against prebuilt images)
4. ⏳ After Fase 2 image builds are ready, re-run this verification against locally-built images

**Fase 1 entry criteria:**  
- Fork exists ✅
- Baseline documented ✅
- GitHub Actions workflow `.github/workflows/test.yml` ready to pull `turkenh/*:1.1` and run smoke tests
