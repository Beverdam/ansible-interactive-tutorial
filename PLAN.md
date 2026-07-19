# PLAN — modernisering van ansible-interactive-tutorial

Masterplan voor de fork `Beverdam/ansible-interactive-tutorial` (upstream:
`turkenh/ansible-interactive-tutorial`, ~5 jaar niet onderhouden). Dit
document is de bron van waarheid waarnaar `docs/BASELINE.md`, `docs/FASE1.md`,
`.github/workflows/test.yml` en de testscripts verwijzen (§3a, §4, §5,
issue-triage).

## §1 — Doel & scope

Het project **duurzaam** weer werkend maken: eigen, herbouwbare Docker-images
op een ondersteunde basis in plaats van blijven leunen op de verdwijnende
`turkenh/*:1.1`-images, én alle bekende issues oplossen. De interactieve
tutorial (nutsh) en de 15 lessen moeten werken op een moderne Ansible en een
moderne containerruntime (docker én podman).

Uit scope: #41 (sessiepersistentie) — buiten fase 0–5.

## §2 — Fasen

| Fase | Onderwerp | Status |
|---|---|---|
| 0 | Fork & baseline setup, issue-inventaris, shellcheck-triage | ✅ `docs/BASELINE.md` |
| 1 | Testsuite eerst (het vangnet): T1–T4/T6/T7 + CI | ✅ `docs/FASE1.md` |
| 2 | `tutorial.sh` hardening (`set -euo pipefail`, quoting) + podman-support (#33) + dit PLAN.md | ✅ `docs/FASE2.md` |
| 3 | Moderne, herbouwbare images (Ubuntu 26.04 LTS + Python 3, nutsh v2.0.0, eigen namespace, #26 ssh-keys) + `\|failed`-contentfix vervroegd | ✅ `docs/FASE3.md` |
| 4 | nutsh test-mode vervangen door eigen driver (T1/T3/T7); 4 verborgen bugs blootgelegd en gefixt; #12/#22/#37 herbevestigd groen (interactief) | ✅ `docs/FASE4.md` |
| 5 | T7-idempotentie + T3-apache-service: compleet & geverifieerd. Jenkins (#32/#39): dieper gediagnosticeerd (root cause: role forceert systemd-module), niet gefixt | ✅ `docs/FASE5.md` |
| 6 | `t6-podman` root cause gefixt (Makefile `$USER`-shadowing). Jenkins: 2 bugs gefixt (java-versie, apt-cache-timing), 1 harde blocker vastgesteld (role vereist echte systemd, `daemon_reload:` hardgecodeerd) | ✅ `docs/FASE6.md` |
| 7 | Jenkins: definitief onderzocht — geen enkele rolversie werkt zonder systemd (oude versies: `apt-key` verwijderd uit Ubuntu 26.04; nieuwe versies: hardgecodeerd `systemd:`). **Besluit (eigenaar): geaccepteerde, gedocumenteerde beperking — geen systemd-architectuurwijziging.** #25 blijft handmatige check. | ✅ `docs/FASE7.md` |
| 8 | UX: `tutorial.sh` bouwt images automatisch als ze ontbreken — geen aparte `make`-stap meer nodig voor onervaren gebruikers. README teruggezet naar alleen `./tutorial.sh` | ✅ `docs/FASE8.md` |
| 9 | Test-suite `/tmp`-padcollisies gefixt (PID-uniek) — gevonden tijdens niet-root-verificatie | ✅ PR #10 (geen apart docs/FASE9.md, commit-message is de documentatie) |
| 10 | T4-flakiness op CI (check #12) root-oorzaak gevonden in nutsh's eigen bron (print-vóór-input-setup-race); gefixt met settle-delay in eigen testcode, niet in nutsh | ✅ `docs/FASE10.md` |
| 11 | README-review vond echte bug: `images/Makefile` had `docker` hardgecodeerd, negeerde `CONTAINER_ENGINE` — `CONTAINER_ENGINE=podman ./tutorial.sh` zou stuklopen op de auto-build-stap zonder een `docker`-commando. Gefixt + doorgegeven vanuit `tutorial.sh` | ✅ `docs/FASE11.md` |

Elke fase: wijziging → review → smoke tests → `docs/FASEn.md` → commit (zie §4).
De `continue-on-error: true`-annotaties in CI worden **per issue verwijderd
zodra dat issue groen is** — dat is de objectieve "klaar"-meting.

## §3 — Testsuite

### §3a — T1–T7 definitie

| Test | Bestand / job | Wat |
|---|---|---|
| T1 | `LESSON_NAME=<les> ./tutorial.sh -t` (matrix in CI) | Alle 15 lessen draaien in nutsh-testmode |
| T2 | `tests/t2_lifecycle.sh` | 4 containers, fping+ssh-bereikbaarheid, stop/restart-hergebruik (#12), `--remove`, `HOSTPORT_BASE` |
| T3 | `tests/t3_checkpoints.sh <apache\|jenkins>` | Host-side curl-checkpoint na les 5 (apache/host1) en les 14 (jenkins/host0) |
| T4 | `tests/t4_pty.py` | Scripted PTY-sessie; test de interactieve laag rechtstreeks (#12/#22/#37) |
| T5 | (fase 4) | nutsh-unittests |
| T6 | CI-job `t6-podman` | T1(les 0)+T2+T4 opnieuw met `docker` geshimd naar podman |
| T7 | `tests/t7_idempotency.sh` | Idempotentie op de scoped lessenlijst (zie §5) |

`tests/lib.sh`/`tests/env.sh` bevatten de gedeelde container-lifecycle-helpers.
Alle `tutorial.sh`-aanroepen lopen via `run_tutorial()` (`script -qe -c … /dev/null`)
zodat echte Docker een pty krijgt (anders faalt `docker run -it` op non-TTY-stdin).

### §3b — Runtime-agnostisch

`tutorial.sh` en de tests draaien onder docker én podman. Podman-compat wordt
bereikt door alleen inspect/run-aanroepen te gebruiken die zich op beide gelijk
gedragen (per-container `inspect` i.p.v. `network inspect --format …IPv4Address`),
niet door op de binaire naam te detecteren (`podman-docker` heet ook `docker`).
Runtime is via `CONTAINER_ENGINE` te overschrijven.

## §4 — Werkwijze per wijziging

1. Wijziging maken op een fase-branch.
2. **Adversarial review** (`/code-review`) op de diff — bevindingen fixen of
   expliciet weerleggen.
3. **Smoke tests**: de relevante T1–T7 lokaal draaien (echte Docker beschikbaar).
4. `docs/FASEn.md` bijwerken met bevindingen.
5. Commit → push naar fase-branch → PR → merge.

## §5 — T7 idempotentie-scope

Geconfigureerd in `tests/t7_idempotency.sh`. Uitgesloten: les 7 en 8 (eindigen
bewust in een falende run) en les 14 (rolinstallatie, geen
configuratie-convergentie). De apache-lessen die `command:`-taken zonder
`changed_when` bevatten (les 9/10/11/13) zijn rood tot de fase-5-fix
(`changed_when: false`/`creates=`); haproxy-only en de simpelste apache-lessen
(les 5/6, alleen apt/copy/file/template) zijn al idempotent.

## §6 — Issue-triage

De 9 getrackte issues (uit de fase-0-inventaris) plus twee fase-1-bevindingen.
Statuskolom = doelfase waarin het issue groen wordt.

| Issue | Component | Aanpak | Doelfase |
|---|---|---|---|
| #33 | `tutorial.sh` podman-incompatibel (`--format`, fping) | Portabele inspect + runtime-agnostisch | ✅ **2** |
| #26 | SSH ssh-rsa key-deprecatie | ed25519-sleutels | ✅ **3** |
| **`\|failed`** | Content: `when: result\|failed` verwijderd in Ansible 2.9+ | → `when: result is failed` (6 bestanden + lestekst) | ✅ **3** (vervroegd uit 5) |
| 🆕 | nutsh v2.0.0: `nutsh test` paniekt op 13/15 lessen (`Expect was not reached`) | nutsh forken/patchen (test-mode-interpreter) | 4 |
| #37 | nutsh: `sh` → panic (tokenizer) | **Al bevestigd gefixt** op v2.0.0 interactief (T4 groen); geen actie nodig tenzij CI anders toont | 4 (verificatie) |
| #22 | nutsh: kan niet typen in prompt | idem — al groen op v2.0.0 interactief | 4 (verificatie) |
| #25 | nutsh: menu mist op WSL | handmatige check, nog niet geverifieerd | 7 |
| #12 | nutsh: geen prompt na menu | idem — al groen op v2.0.0 interactief | 4 (verificatie) |
| — | `t6-podman`: podman rootless build faalt op GitHub | Makefile `USER=` botste met shell's `$USER` (subuid/subgid-lookup) → hernoemd naar `IMAGE_NAMESPACE` | ✅ **6** |
| 🆕 | Les 14: `openjdk-25-jdk` bestaat niet als los pakket op Ubuntu 26.04 | `java_packages: [openjdk-21-jdk]` override in jenkins.yaml | ✅ **6** |
| 🆕 | Les 14: host0 nooit ge-`apt update`-t vóór deze les | `pre_tasks:` met `apt: update_cache=true` (let op: niet `tasks:`, roles draaien vóór tasks) | ✅ **6** |
| #32/#39 | Les 14: harde blocker — geen enkele rolversie werkt zonder systemd (oud: `apt-key` verwijderd; nieuw: hardgecodeerd `systemd:`, geverifieerd geen overlap) | **Geaccepteerde beperking (besluit eigenaar, fase 7)** — geen fix, gedocumenteerd | ✅ **7** (afgesloten, niet opgelost) |
| — | T7: apache `command:`-taken niet idempotent | `changed_when`/`creates=`/`removes=` | ✅ **5** |
| — | T3: apache-service start niet in les 5 | `service: state=started` in step-4 | ✅ **5** |
| #41 | Sessiepersistentie | — | buiten scope |

De fase-0-tabel in `docs/BASELINE.md` markeerde #12/#22/#37 als "rood op 1.1";
`docs/FASE1.md` weerlegt dat (T4 groen op 1.1); `docs/FASE3.md` bevestigt
dezelfde drie nu ook groen op v2.0.0 — interactief. nutsh's **test-mode**
(`nutsh test`, apart van interactief) heeft op v2.0.0 een eigen, nieuw
ontdekte regressie (zie 🆕 hierboven) die T1/T3/T7 in CI blokkeert; dat is nu
de hoofdtaak van fase 4, naast het bevestigen van #25 en het toevoegen van T5.
