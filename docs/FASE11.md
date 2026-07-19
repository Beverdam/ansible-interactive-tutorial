# Fase 11 — README-review vond een echte bug: podman-pad was niet compleet

**Status:** compleet, geverifieerd. **Datum:** 2026-07-19.

## Aanleiding

Gevraagd om de README nogmaals te controleren op onjuistheden. De meeste
inhoud bleek nog accuraat (fase 8 had de Ubuntu-versie en build-instructies
al gecorrigeerd). Bij het narekenen van de regel "podman also works
instead of docker" kwam een echte, niet-cosmetische bug aan het licht.

## De bug

`images/Makefile` had `docker build`/`docker push` **hardgecodeerd**,
onafhankelijk van `tutorial.sh`'s eigen `CONTAINER_ENGINE`-variabele.
Sinds fase 8 roept `tutorial.sh` deze Makefile automatisch aan
(`ensureImagesBuilt()`) als de images nog ontbreken. Gevolg: een
gebruiker die `CONTAINER_ENGINE=podman ./tutorial.sh` draait op een
machine met **alleen** podman (geen `docker`-commando) zou bij de
automatische build-stap alsnog stuklopen op `docker: command not found`
— ondanks dat `tutorial.sh`'s eigen container-commando's `CONTAINER_ENGINE`
al correct respecteerden.

Dit bleef tot nu toe onopgemerkt omdat CI's `t6-podman`-job dit omzeilt
via een PATH-shim (`tests/podman-shim/docker` → `exec podman`) waardoor
`docker` daar toch podman aanroept — dat verbergt precies dit
Makefile-gat, want de hardgecodeerde string "docker" wordt daar sowieso
naar podman doorgesluisd via PATH, ongeacht `CONTAINER_ENGINE`.

## Fix

- `images/Makefile`: `CONTAINER_ENGINE ?= docker` toegevoegd; `build`/
  `push`-targets gebruiken nu `$(CONTAINER_ENGINE)` in plaats van het
  hardgecodeerde `docker`. `?=` (niet `=`) zodat een al gezette
  omgevingsvariabele gerespecteerd wordt, met een zinnig standaardpad voor
  een kale `make`-aanroep.
- `tutorial.sh`: `ensureImagesBuilt()` geeft `CONTAINER_ENGINE` nu expliciet
  door aan `make` (`make -C images build_all
  CONTAINER_ENGINE="${CONTAINER_ENGINE}"`), omdat de shell-variabele in
  `tutorial.sh` niet `export`ed is en dus niet vanzelf naar het
  kindproces `make` doorstroomt.
- README: de podman-vermelding aangepast van "zie tests/podman-shim/"
  (CI-specifieke infrastructuur) naar de daadwerkelijke, voor eindgebruikers
  bedoelde manier: `CONTAINER_ENGINE=podman ./tutorial.sh`.

## Geverifieerd

- `make -n build` (standaard) → `docker build ...`
- `CONTAINER_ENGINE=podman make -n build` → `podman build ...`
- `make -n build_all CONTAINER_ENGINE=podman` → beide images correct met
  `podman build ...` via de geneste `$(MAKE)`-aanroepen (GNU Make geeft
  command-line-variabelen automatisch door aan recursieve `make`-aanroepen)
- Normale (docker) pad opnieuw end-to-end getest na de wijziging: auto-build
  vanaf een lege staat + T1 lesson 0 — nog steeds `PASS`
- Live podman-build niet opnieuw lokaal getest (bekende, al gedocumenteerde
  `apt-get update`-hang in déze sandbox door geneste netwerken, zie
  `docs/FASE3.md`) — de bedrading is bevestigd via bovenstaande dry-runs,
  wat voldoende is om de logica als correct te beschouwen zonder het
  bekende, omgevingsspecifieke probleem opnieuw te riskeren.

## Rest van de README

Verder gecontroleerd, geen andere onjuistheden gevonden: lessenlijst,
containerbeschrijvingen (Alpine control node, Ubuntu 26.04 LTS-hosts),
poortmapping, workspace-mount en de Jenkins/systemd-beperking komen
allemaal nog overeen met de werkelijke staat van het project.
