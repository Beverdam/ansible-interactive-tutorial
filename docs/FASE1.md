# Fase 1 — Testsuite eerst (het vangnet)

**Status:** compleet. **Datum:** 2026-07-16.

Alles hieronder is lokaal geverifieerd tegen de gepulde `turkenh/*:1.1`-images
(zie `docs/BASELINE.md`), met `docker` op deze machine een podman-shim
(`podman-docker`, "Emulate Docker CLI using podman"). Dat betekent dat elke
podman-specifieke bevinding hieronder al zichtbaar was tijdens het bouwen
van de suite zelf, vóór er een aparte T6-CI-job voor bestond.

## De suite

| Test | Bestand | Wat |
|---|---|---|
| T1 | `LESSON_NAME=<lesson> ./tutorial.sh -t` (bestaand) | 15-lessen-matrix in `.github/workflows/test.yml` |
| T2 | `tests/t2_lifecycle.sh` | build/lifecycle: 4 containers, fping+ssh, stop/restart-hergebruik, `--remove`, `HOSTPORT_BASE` |
| T3 | `tests/t3_checkpoints.sh <apache\|jenkins>` | host-side curl-checkpoint na lesson 5 (apache/host1) en lesson 14 (jenkins/host0) |
| T4 | `tests/t4_pty.py` | scripted PTY-sessie (Python `pty`), test #12/#22/#37 rechtstreeks tegen de interactieve laag |
| T7 | `tests/t7_idempotency.sh` | idempotentie op de scoped lessenlijst (zie hieronder) |
| T6 | CI-job `t6-podman` | T1(les 0)+T2+T4 nogmaals, met `docker` geshimd naar podman (`tests/podman-shim/`) |

`tests/lib.sh`/`tests/env.sh` bevatten de gedeelde container-lifecycle-helpers.
T5 (nutsh-unittests) is fase 3 werk zoals gepland.

### Waarom T2/T7 geen `docker exec` in de langdurige `ansible.tutorial`-container gebruiken

`nutsh test` (test mode) draait de tutorial-container **in de voorgrond**;
zodra de les klaar is (of paniekt) stopt de container. Voor T7's tweede
("idempotentie") playbook-run is er dus geen draaiende container meer om in
te `exec`en. `/root/workspace` is echter een host-bind-mount
(`${BASEDIR}/workspace`), dus een verse, kortstondige
`docker run --rm -v ...:/root/workspace ...`-aanroep op hetzelfde netwerk
ziet exact dezelfde geconvergeerde staat. Dat is wat `t7_idempotency.sh`
doet. (Een eerdere versie deed dit fout — `docker exec` tegen de inmiddels
gestopte container faalde stil en werd ten onrechte als "idempotent"
gelezen omdat de foutmelding toevallig geen `changed=`-patroon bevatte. Nu
wordt expliciet op een `PLAY RECAP` in de output gecontroleerd voor er iets
beoordeeld wordt.)

## T7 — scope (vastgesteld in deze fase, zoals gepland in §3a/§5)

Geconfigureerd in `tests/t7_idempotency.sh`. Uitgesloten: lesson 7
("Playbooks and failures") en lesson 8 ("Playbook conditionals") — beide
eindigen bewust in een falende run. Lesson 14 (Jenkins/roles-install) valt
buiten scope (al expected-fail door #32/#39, en rolinstallatie is geen
"configuratie-convergentie"-voorbeeld zoals apache/haproxy).

| Label | Lesson (bestand) | Commando | Resultaat (lokaal, baseline) |
|---|---|---|---|
| lesson5-apache | 4-step-04 | `apache.yml -l host1...` | **groen** — alleen apt/copy/file taken |
| lesson6-apache | 5-step-05 | `apache.yml -l host1...` | **groen** — alleen apt/copy/file taken |
| lesson9-git | 8-step-08 | `apache.yml -l host1...` | rood — bevat `command:` taken |
| lesson10-apache | 9-step-09 | `apache.yml` (alle web-hosts) | rood — bevat `command:` taken |
| lesson11-templates | 10-step-10 | `apache.yml haproxy.yml` | rood — apache-deel bevat `command:` taken |
| lesson12-haproxy | 11-step-11 | `haproxy.yml` | **groen** — alleen apt/template/lineinfile |
| lesson13-roles | 12-step-12 | `site.yml` (apache+haproxy rollen) | rood — apache-rol bevat dezelfde `command:` taken |

**Root cause (bevestigd door lokale run):** `files/step-8/apache.yml` (en
alle latere apache-varianten die ervan afgeleid zijn) gebruiken
`command: a2ensite ...`, `command: apache2ctl configtest` en
`command: a2dissite ...` zonder `changed_when`. Ansible's `command`-module
heeft geen ingebouwde state-detectie en rapporteert dus `changed` op elke
run, ook als er niets verandert. `files/step-4/apache.yml` en
`files/step-11/haproxy.yml` gebruiken alleen declaratieve modules
(`apt`/`copy`/`file`/`template`/`lineinfile`) en zijn echt idempotent.
**Fix (fase 4):** `changed_when: false` of `creates=...` toevoegen aan de
`a2ensite`/`a2dissite`/`apache2ctl configtest`-taken.

## T3 — nieuwe bevinding (niet een van de 9 issues)

Baseline-verwachting in `PLAN.md` was "les 5 groen". Lokale run met een
**verse** `host1.example.org`-container laat zien dat dit **rood** is:
`files/step-4/apache.yml` installeert alleen het `apache2`-pakket
(`apt: state=present`) maar start de service nooit expliciet, en dit image
se `/start.sh` draait geen echte init die dat als side-effect van
`apt install` zou doen (`service apache2 status` → "not running" direct na
de playbook-run; handmatig `service apache2 start` lost het op en de curl-
checkpoint slaagt daarna). Vanaf lesson 6 (`files/step-5/apache.yml`) is er
wel een `notify: restart apache`-handler die de service alsnog start zodra
de virtualhost-config verandert — dus dit is specifiek aan lesson 5/les-4
gebonden, niet aan apache in het algemeen.
**Fix (fase 4):** een expliciete `service: name=apache2 state=started` taak
aan `files/step-4/apache.yml` toevoegen (of de fase-4-cleanup van de
`command:`-taken meteen combineren met een startup-garantie).

## T4 — herziening van de #12/#22/#37-aanname

`docs/BASELINE.md` (fase 0) markeerde #12/#22/#37 als "rood, gereproduceerd
op 1.1" maar kon dat toen niet automatisch verifiëren ("requires interactive
PTY environment"). `tests/t4_pty.py` lost dat probleem juist op (een
Python `pty`-gestuurde sessie, geen echte terminal nodig) en is in deze
fase wél tegen `turkenh/ansible-tutorial:1.1` gedraaid:

- Menu verschijnt bij start — **groen**
- Shell-prompt verschijnt na lesson-selectie (#12) — **groen**
- Getypte command wordt teruggekaatst / input wordt opgepikt (#22) — **groen**
- `sh` intypen op de prompt van lesson 1 veroorzaakt geen panic, proces
  blijft leven (#37, letterlijke reproductiestappen uit issue #37) — **groen**

Dit weerspreekt de eerdere aanname. Twee mogelijke verklaringen, geen van
beide bevestigd: (a) deze specifieke `:1.1`-tag bevat al een fix die niet
naar het issue is teruggekoppeld, of (b) de bug is omgevingsspecifiek (issue
#37 werd gemeld op CentOS 8, #12 met Docker 18.09) op een manier die deze
Python-pty niet triggert (bv. `$TERM`, terminal-timing). **Actie:** T4 blijft
in CI **verplicht groen** (niet als expected-fail geannoteerd) omdat dat is
wat lokaal daadwerkelijk gemeten is; als de CI-run op GitHub's Ubuntu-runners
(echte Docker, ander toolchain-pad dan hier) alsnog rood wordt, is dat zelf
al nieuwe informatie voor fase 3. De geplande vergelijking met
`turkenh/nutsh:1.2`/`v2.0.0` (fase 0 stap 3) blijft relevant voor fase 3 —
die images hebben een andere entrypoint-structuur en zijn niet meegenomen
in deze fase.

## T2 — bevestigde nuance bij `--remove`

Zoals voorzien in `PLAN.md` fase 1 stap 3: `--remove` verwijdert de 3
host-containers en probeert het netwerk te verwijderen, maar killt
`ansible.tutorial` niet. Lokaal blijkt dat als gevolg **ook de
netwerk-removal faalt** zolang `ansible.tutorial` nog aan het netwerk hangt
(`Error: "ansible.tutorial" has associated containers with it`). Dit is in
`tests/t2_lifecycle.sh` als informatieve `NOTE`, niet als `CHECK FAILED`,
verwerkt — het is de voorspelde afwijking, geen regressie.

## T6/podman — bevestigde reproductie van #33

Twee onafhankelijke breekpunten, allebei al zichtbaar tijdens het lokaal
bouwen van deze suite (`docker` = podman-shim op deze machine):

1. `setupFiles()`'s `docker network inspect --format
   "...{{$container.IPv4Address}}..."` faalt hard onder podman
   (`can't evaluate field IPv4Address in type types.NetworkContainerInfo`
   — podman's Go-structuur voor genetwerkte containers heeft die
   top-level-veldnaam niet). Resultaat: `ansible_host=` blijft leeg in het
   gegenereerde hosts-bestand.
2. `fping host{0,1,2}.example.org` rapporteert alle hosts "unreachable"
   onder (rootless) podman, terwijl `ssh` naar dezelfde hostnamen wél werkt
   (DNS-resolutie via podman's netwerk werkt, ICMP kennelijk niet zonder
   meer).

Beide horen bij #33 en zijn **fase 2**-werk (podman-detectie +
`--format`-aanroepen herschrijven in `tutorial.sh`).

## Adversarial review (na eerste commit)

Een `/code-review` pass (8 finder-angles + 1-vote verify, per `PLAN.md` §4)
op de eerste fase-1-commit vond 5 bevestigde/plausibele issues, allemaal
gefixt in een vervolgcommit:

1. **Kritiek, bevestigd:** `docker run -it` (gebruikt door `tutorial.sh` en
   dus door élke aanroep in deze suite) faalt hard op échte Docker als
   stdin geen terminal is — precies de situatie in een GitHub Actions
   `run:`-stap of een backgrounded proces. Podman waarschuwt alleen en gaat
   door, dus dit bleef onzichtbaar bij lokaal testen tegen de podman-shim.
   **Fix:** alle `tutorial.sh`-aanroepen lopen nu via `script -qe -c "..."
   /dev/null` (nieuwe `run_tutorial()`-helper in `tests/lib.sh`), wat een
   echte pty aan het kind geeft ongeacht of de aanroeper er zelf een heeft.
   `-e` geeft de exitcode door (zonder die vlag geeft `script` altijd 0).
2. **Bevestigd:** de `t6-podman`-job installeerde kaal `podman` zonder
   registry-config; Ubuntu's podman-pakket heeft `docker.io` niet in
   `unqualified-search-registries`, dus `turkenh/...`-image-pulls faalden
   met een short-name-resolutiefout — een derde, ongedocumenteerde
   faalmodus naast de twee al beschreven #33-symptomen. **Fix:** een
   `registries.conf.d`-drop-in die `docker.io` toevoegt, vóór de eerste pull.
3. **Plausibel:** `tests/t4_pty.py` decodeerde elke PTY-chunk apart, wat een
   UTF-8-teken dat een chunkgrens overspant kan corrumperen. Momenteel
   onbereikbaar (de enige non-ASCII string in `tutorials/` is dode code),
   maar een echte bug. **Fix:** een stateful `codecs.getincrementaldecoder`
   in plaats van chunk-voor-chunk `decode()`.
4. **Bevestigd, lage impact:** `PtySession.close()` reapte het proces niet
   opnieuw na een `kill()`, en signaleerde alleen het directe kind-PID
   ondanks `setsid`. **Fix:** signaleert nu de hele procesgroep via
   `os.killpg` en `wait()`t altijd na een kill.
5. **Plausibel (ontwerpnotitie):** `tests/podman-shim/docker` heet letterlijk
   `docker`, wat fase 2's runtime-detectie in de weg zou kunnen zitten als
   die op bestandsnaam vertrouwt in plaats van op gedrag. **Fix:** geen
   herontwerp (dat zou vooruitlopen op een nog-niet-gemaakte fase-2-keuze),
   maar een expliciete waarschuwing in het shim-bestand voor de fase-2-auteur.

Drie andere kandidaten uit de review bleken **refuted** bij verificatie —
`tutorial.sh`'s bestaande zelfherstellende logica (kill-before-run,
container-hergebruik, netwerk-hergebruik) ondervangt al precies de
scenario's waar twee andere angles zich zorgen over maakten (ontbrekende
cleanup-trap in T3/T7, verouderde netwerkstaat in de T6-job).

Alle 5 fixes zijn lokaal opnieuw geverifieerd (T2/T3/T7/T4 herhaald met
dezelfde uitkomsten als vóór de fix) — de `script`-wrapping verandert het
gedrag onder podman niet (podman had het probleem toch al niet), dus dit
kon alleen inhoudelijk tegen de podman-shim getest worden, niet tegen
échte Docker. De GitHub Actions-run zelf is de uiteindelijke validatie.

## Wat nog klopt uit fase 0

- shellcheck-bevindingen in `docs/BASELINE.md` — ongewijzigd, nog niet
  gefixt (fase 2).
- Issue-triage-tabel in `PLAN.md` — ongewijzigd, met de kanttekening bij
  #12/#22/#37 hierboven.

## Klaar voor fase 2

- ✅ CI draait op elke push (`.github/workflows/test.yml`): lint, t1-lessons
  (matrix), t2-lifecycle, t3-checkpoints, t7-idempotency, t4-pty, t6-podman.
- ✅ Elke verwachte-rode test is een geannoteerde reproductie: een issue-
  nummer (#32/#39/#33) of een hierboven gedocumenteerde fase-1-bevinding
  (T3-apache-service, T7-apache-idempotentie).
- ✅ `.travis.yml` verwijderd; README-badge wijst naar de Actions-workflow.
- Vanaf hier: wijziging → adversarial review op de diff → smoke tests →
  merge, per `PLAN.md` §4.
