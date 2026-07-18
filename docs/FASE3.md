# Fase 3 — Moderne, herbouwbare images

**Status:** compleet. **Datum:** 2026-07-18.

Kern van "duurzaam weer werkend": van "pull `turkenh/*:1.1` (5 jaar oud,
Docker Hub-account niet van ons)" naar "bouw eigen images op een levende
basis". Geverifieerd met **echte Docker** (v29.6.2) op de werkmachine.

## Wat veranderde

### `images/ansible-managed-host/` (hernoemd van `ubuntu-1604-ansible-docker-host`)

- **Basis:** `ubuntu:16.04` → **`ubuntu:26.04` LTS** ("Resolute Raccoon" — de
  actuele LTS; eerst gebouwd op 24.04, tijdens deze fase overgestapt op 26.04
  na een vraag daarover; beide bleken identiek te werken, zie "Geverifieerd"
  hieronder).
- **Python 2 → Python 3:** `python`/`python-yaml`/`python-jinja2`/
  `python-paramiko`/`python-crypto` (allemaal EOL) vervangen door `python3` +
  `python3-apt` (nodig voor de native `apt`-module-bindings op het
  managed-doel; zonder deze faalt Ansible's `apt`-module luid).
- **`rsyslog` verwijderd:** nergens in een les of test gebruikt; Ubuntu
  26.04's rsyslog-pakket levert geen SysV `/etc/init.d/rsyslog` meer
  (systemd-only), dus `service rsyslog start` faalde hard
  (`rsyslog: unrecognized service`) — dode functionaliteit die het opstarten
  blokkeerde. Weggehaald in plaats van omheen gebouwd.
- **`MAINTAINER` → `LABEL maintainer=`** (hadolint).
- **#26 ssh-rsa deprecatie:** nieuw **ed25519**-sleutelpaar gegenereerd
  (`images/common/id_ed25519(.pub)`), de gecommitte `id_rsa`/`id_rsa.pub`
  verwijderd. Zowel de host-sleutel in de container als de
  `authorized_keys` van het control-node zijn nu ed25519 — de ssh-rsa
  (SHA-1 RSA-signature) deprecatie is niet gepatcht maar structureel
  vermeden door het algoritme niet meer te gebruiken.
- `common/start.sh`: de `while ! "${ALLOW_EXIT}"`-idioom (voerde de
  string-waarde uit als commando) vervangen door een expliciete
  string-vergelijking (`[ "${ALLOW_EXIT}" != "true" ]`); fail-fast op
  `service ssh start` behouden.

### `images/ansible-tutorial/`

- **Basis:** `turkenh/nutsh:1.1` (tag bestaat niet meer) →
  **`turkenh/nutsh:v2.0.0`** (Alpine 3.21.3, levende package-mirrors).
  `turkenh/nutsh:1.2` bleek **ook onbruikbaar als bouwbasis**: Alpine 3.14,
  wiens mirrors óók al gearchiveerd zijn (`dl-cdn.alpinelinux.org/alpine/v3.14`
  → 404) — hetzelfde bit-rot-patroon als de oude Ubuntu-basis. v2.0.0 is de
  enige nutsh-tag die nu nog daadwerkelijk bouwt.
- **Ansible gepind:** `apk add ansible` (ongepind, trok bij elke rebuild de
  actuele Alpine-Ansible) → `ansible=11.1.0-r0 ansible-core=2.18.1-r0`
  expliciet. Noodzakelijk voor reproduceerbaarheid, en cruciaal omdat
  ansible-core 2.18 een stuk lesinhoud harde brak (zie hieronder).
- `git` toegevoegd (niet strikt nodig op het control-node zelf, maar
  consistent met de nieuwe managed-host image; toekomstbestendig voor
  ansible-galaxy/roles-werk in fase 5).
- ed25519-sleutels (zie boven) i.p.v. rsa.

### `images/common/ansible.cfg`

`interpreter_python = auto_silent` toegevoegd — voorkomt een
interpreter-discovery-waarschuwing van moderne ansible-core zonder de
auto-detectie zelf uit te zetten. Geverifieerd: `ansible -m ping` geeft een
schone `SUCCESS`, geen waarschuwingen.

### `images/Makefile`

- `USER=turkenh` → `USER=beverdam` (eigen fork-namespace; `turkenh`'s
  Docker Hub-account is niet van ons om naar te pushen).
- `TAG=1.1` → `TAG=2.0`.
- **`.DEFAULT_GOAL`: `all` → `build_all`.** De oude default (`all` =
  `build_all` + `push_all`) betekende dat een kaal `make` probeerde te
  pushen naar `turkenh`'s account. Nu bouwt een kaal `make` alleen; pushen
  is een expliciete `make push_all`.
- Image-target hernoemd: `ubuntu-1604-ansible-docker-host` →
  `ansible-managed-host`.

### `tutorial.sh`

`DOCKER_IMAGETAG` default `1.1` → `2.0`; `DOCKER_HOST_IMAGE`/`TUTORIAL_IMAGE`
wijzen nu naar `beverdam/ansible-managed-host:2.0` /
`beverdam/ansible-tutorial:2.0` (lokaal gebouwd via `images/Makefile`), met
env-overrides voor wie een andere registry/namespace gebruikt.

### KRITIEK, naar voren getrokken uit fase 5: `when: result|failed` → `is failed`

Zoals in `PLAN.md` §6 voorzien: zodra ansible-core 2.18 gepind werd, bleek
`when: result|failed` (de filter-vorm, verwijderd sinds Ansible 2.9) een
**harde parse/eval-breuk**, niet een lint-waarschuwing. Zonder deze fix
crasht elke rebuild meteen op lessen 7–13. Gefixt in 6 bestanden +
lestekst: `tutorials/files/step-{7,8,9,10,11}/apache.yml`,
`tutorials/files/step-12/apache_tasks.yml`, `tutorials/7-step-07.nutsh`.

**Geverifieerd (niet aangenomen):** lesson 7's playbook end-to-end gedraaid
tegen host1 met de nieuwe images. De opzettelijke config-typo
("RocumentDoot") laat `apache2ctl configtest` falen, `result is failed`
evalueert correct naar waar, de drie rollback-taken draaien
(`changed: [host1.example.org]`), en de playbook eindigt met de bedoelde
`"Configuration file is not valid..."`-melding. Dit is precies het gedrag
dat vóór de fix een onafgevangen Jinja/filter-exception zou zijn geweest op
ansible-core 2.18.

## Geverifieerd (echte Docker)

- `make -C images build_all` — beide images bouwen schoon (geen 404's, geen
  Python-2-fouten).
- Volledige lifecycle: 4 containers op, ssh met het nieuwe ed25519-paar
  (`Warning: Permanently added ... (ED25519)`), fping, `ansible -m ping all`
  → 3× `SUCCESS`/`pong`, geen waarschuwingen.
- Lesson 7 (`is failed`-fix) end-to-end zoals hierboven beschreven.
- **Ubuntu 24.04 vs 26.04:** eerst op 24.04 gebouwd en volledig getest
  (identieke resultaten), daarna overgestapt op 26.04 LTS na een vraag
  daarover tijdens deze fase — herbouwd en **opnieuw** volledig
  geverifieerd (lifecycle, ssh, fping, ansible ping, lesson 7) met identieke
  uitkomst. Geen aan Ubuntu-versie gebonden regressies.
- `hadolint`: schoon op 2 na (DL3008/DL3018, "pin package versions" voor de
  niet-ansible-pakketten). **Bewuste keuze, geen omissie:** exact pinnen van
  élk apt/apk-pakket is precies het patroon dat de oude `ubuntu:16.04`
  Dockerfile onbouwbaar maakte (een pin veroudert op een gegeven moment uit
  het actuele repo). Alleen `ansible`/`ansible-core` zijn gepind, omdat
  lesinhoud direct van hun exacte gedrag afhangt.
- T2 (`tests/t2_lifecycle.sh`, nu bouwend i.p.v. pullend): **PASS**.

## Nieuwe bevinding: nutsh v2.0.0 test-mode regressie (fase-4-werk)

`nutsh test` (gebruikt door T1, en door T3/T7 via `run_tutorial -t`) **paniekt**
op vrijwel elke les met `panic: Expect was not reached: <commando>` — zelfs
wanneer het commando zichtbaar correct is uitgevoerd (volledige, correcte
`ansible --version`-output stond al op het scherm toen de panic optrad).

**Geverifieerd, alle 15 lessen individueel gedraaid in testmodus:**

| Les | Testmodus-resultaat |
|---|---|
| 0–2, 4–13 | **panic** (`Expect was not reached`) |
| 3-step-03 | **PASS** |
| 14-freeplay | **PASS** (bevat geen `expect()`) |

`turkenh/nutsh:1.2` is **geen alternatief**: Alpine 3.14-basis, mirrors
gearchiveerd, kan niet gebruikt worden om opnieuw te bouwen (zelfde
bit-rot-patroon als de oude Ubuntu-image). v2.0.0 is de enige levende optie.

**Interactieve modus is NIET aangetast — dit is puur een testmodus-bug:**
T4 (`tests/t4_pty.py`, een echte PTY-sessie zoals een gebruiker die ervaart)
**volledig groen** tegen de nieuwe v2.0.0-images: menu verschijnt, prompt na
lesselectie (#12), getypte input wordt opgepikt (#22), `sh` intypen paniekt
niet (#37). Dit bevestigt én verbreedt de fase-1-bevinding (toen alleen op
`:1.1` getest) naar v2.0.0.

**Impact op T3/T7:** beide draaien lessen via `run_tutorial -t` en raken dus
dezelfde panic, vóórdat hun eigen (al gedocumenteerde) content-bevindingen
(apache-service niet gestart, idempotentie) zelfs bereikt worden. T3-apache
handmatig bevestigd: faalt nu al op de nutsh-panic, niet (nog) op de
service-bug.

**Conclusie / fase-4-agenda:** dit is een bug in nutsh's
test-mode-interpreter (`parser/interpret.go`, rond de `expect()`-matching),
niet in de tutorialinhoud of onze images. Fixen vereist nutsh's Go-source
patchen/forken — expliciet fase-4-scope, niet aangepakt in deze fase.

## CI

- Elke job die `tutorial.sh` aanroept bouwt nu eerst (`make -C images
  build_all`) i.p.v. te pullen.
- `t1-lessons`: matrix-breed `continue-on-error` behalve `3-step-03` en
  `14-freeplay` (de enige twee die daadwerkelijk groen zijn, geverifieerd).
- `t3-checkpoints`, `t7-idempotency`: blijven `continue-on-error`, reden
  bijgewerkt (nutsh-panic maskeert nu de oorspronkelijke content-bevindingen).
- `t4-pty`: **blijft required-green** — en is dat ook, geverifieerd tegen
  v2.0.0.
- `t6-podman`: build-stap toegevoegd; het t1-lesson-0-smoke-onderdeel
  daarbinnen is nu ook `continue-on-error` (dezelfde nutsh-panic, los van
  podman).
- `lint`/hadolint: paden bijgewerkt naar de hernoemde directory.

## Niet geverifieerd in déze omgeving: `docker build` onder podman

Een poging om `make build_all` te draaien met `docker` geshimd naar podman
(zoals de CI `t6-podman`-job doet) **hing** op `apt-get update` binnen de
`ubuntu:26.04`-buildstap en moest afgebroken worden. Dit reproduceert
vermoedelijk dezelfde geneste-netwerk/DNS-eigenaardigheid die
`docs/FASE1.md` al documenteerde voor podman in déze specifieke
(geneste-container) werkomgeving (rootless podman + aardvark-dns), niet een
probleem met de Dockerfiles zelf — `docker build` van dezelfde Dockerfiles
werkte via echte Docker probleemloos. GitHub's `t6-podman`-runner (geen
geneste containers) is de eigenlijke validatie hiervoor; de job bouwt nu
mee en het resultaat daar is nieuwe informatie.

## Klaar voor fase 4

- ✅ Images bouwen op een levende, moderne basis (Ubuntu 26.04 LTS + Python 3,
  nutsh v2.0.0 + gepinde ansible-core 2.18.1).
- ✅ #26 (ssh-rsa) structureel opgelost via ed25519.
- ✅ Kritieke `\|failed`-contentbreuk gefixt en geverifieerd (naar voren
  getrokken uit fase 5, zoals `PLAN.md` §6 voorzag).
- 🆕 nutsh v2.0.0 test-mode-panic geïnventariseerd (alle 15 lessen individueel
  getest) — dit is nu de concrete fase-4-hoofdtaak, naast #12/#22/#25/#37
  (die overigens al bevestigd blijven gefixt in interactieve modus) en T5.
