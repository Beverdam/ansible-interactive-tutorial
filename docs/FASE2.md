# Fase 2 — `tutorial.sh` hardening + podman-support (#33)

**Status:** compleet. **Datum:** 2026-07-18.

Anders dan fase 0/1 (podman-shim) is dit geverifieerd tegen **echte Docker**
(v29.6.2) op de werkmachine — precies het toolchain-pad van GitHub Actions —
én tegen **podman 5.4.2** via de PATH-shim (`tests/podman-shim/`).

## `PLAN.md` aangemaakt

Het overal aangehaalde maar ontbrekende masterplan is nu aangemaakt in de
repo-root: fasedefinities (§2), testsuite (§3a), reviewworkflow (§4),
T7-scope (§5) en de issue-triage-tabel (§6). Alle bestaande verwijzingen
(`docs/*`, CI-comments, testscripts) kloppen nu.

## `tutorial.sh`

- **`set -euo pipefail`** toegevoegd. Gevolgen zorgvuldig afgevangen:
  - Boolean-helpers (`doesNetworkExist`, `doesContainerExist`,
    `isContainerRunning`) worden alleen in condities gebruikt → `set -e` grijpt
    daar niet in.
  - `killContainerIfExists`/`removeNetworkIfExists` herschreven naar een
    `if`-vorm die altijd 0 teruggeeft, zodat een niet-bestaande
    container/netwerk het script niet afbreekt.
  - `remove()` doet netwerkverwijdering **best-effort** (`|| true`): terwijl
    `ansible.tutorial` nog aan het netwerk hangt faalt `network rm` voorspelbaar
    (bekende beperking, PLAN.md §5/fase1) — dat mag de rest van de opruiming
    niet afbreken. De engine-fout blijft zichtbaar op stderr.
  - `runTutorialContainer` vangt de exitcode expliciet op (`|| status=$?`;
    `return "${status}"`) zodat de lesson-testexitcode netjes doorstroomt naar
    `init`'s `exit $?`.
  - `LESSON_NAME`/`TEST` krijgen defaults (`${LESSON_NAME:-}`) voor `set -u`.
- **Alle 9 quoting-bevindingen** uit `docs/BASELINE.md` gefixt. `entrypoint`/
  `args` zijn nu **arrays** (`"${entrypoint[@]}"`) i.p.v. ongequote strings —
  correcter dan losse quoting en shellcheck-clean.
- **Runtime-agnostisch:** nieuwe `CONTAINER_ENGINE` (default `docker`, te
  overschrijven). Bewust **niet** op binaire naam detecteren — de podman-shim
  heet ook `docker` en `podman-docker` op Fedora/RHEL net zo. Compat komt uit
  het gebruiken van aanroepen die op beide engines gelijk zijn.
- **shellcheck-clean** (lokaal geverifieerd). De CI `lint`-job maakt de
  shellcheck-stap daarom **blocking**; hadolint blijft soft tot de Dockerfiles
  in fase 3 gemoderniseerd zijn.

## #33 — podman-compat (kernfix, geverifieerd)

`setupFiles()` gebruikte `docker network inspect --format
"...{{$c.IPv4Address}}..."`. Dat `IPv4Address`-veld bestaat niet in podman's
network-container-struct → leeg `ansible_host=` in het gegenereerde
hosts-bestand. **Fix:** per-container `inspect
-f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'` — portabel over
docker én podman, en meteen zonder de `cut -d/`-nabewerking (dit veld bevat
geen CIDR-suffix).

**Geverifieerd:**
- Echte Docker: T2 groen; ssh naar `172.18.0.2/3/4` (ansible_host gevuld).
- Podman 5.4.2: gegenereerde inventory bevat echte IP's
  (`ansible_host=10.89.0.7/8/9`) — vóór de fix was dit leeg. De kern van #33
  is dus opgelost op podman.

**Resterende podman-nuances (geen #33-inventarisbug meer):**
- `fping` gebruikt ICMP, wat onder rootless podman niet gegarandeerd werkt.
  T2's fping-check is nu **informatief onder podman** (nieuwe `is_podman`-helper
  in `tests/lib.sh`); ssh blijft de gezaghebbende bereikbaarheidscheck. Onder
  echte Docker blijft fping een harde check.
- In deze specifieke (genneste) werkomgeving faalde bovendien podman's
  container-DNS (`Could not resolve hostname ... Try again`), waardoor
  ssh-op-hostnaam hier niet lukt. Dit is omgevingsspecifiek (aardvark-dns) en
  reproduceert naar verwachting niet op GitHub's runners. De tutorial zelf
  verbindt via `ansible_host=<ip>` en omzeilt DNS.

## CI

- `lint` → shellcheck-stap **blocking**; hadolint soft (fase 3).
- `t6-podman` blijft één run `continue-on-error`: #33's inventarisbug is
  gefixt en lokaal op podman bevestigd, maar de definitieve groen-vlag wordt
  pas omgezet zodra GitHub's runner (echte podman, ander DNS-pad dan hier) de
  job groen bevestigt.

## Wat nog klopt uit eerdere fasen

- Fase-0 shellcheck-bevindingen: nu **gefixt** (waren nog open).
- `docs/FASE1.md`-bevindingen (T3-apache-service, T7-idempotentie): ongewijzigd,
  fase 5.

## Klaar voor fase 3

- ✅ `tutorial.sh` shellcheck-clean, `set -euo pipefail`, runtime-agnostisch.
- ✅ #33-inventarisbug opgelost en op podman geverifieerd.
- ✅ `PLAN.md` bestaat; alle verwijzingen kloppen.
- Volgende: eigen herbouwbare images (Ubuntu 24.04 + Python 3, nutsh pinnen,
  eigen namespace, #26 ssh-keys) — dan kan CI van pull → `docker build`.
