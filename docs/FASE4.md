# Fase 4 — nutsh test-mode vervangen + verborgen contentbugs blootgelegd

**Status:** kern compleet. **Datum:** 2026-07-18.

## Aanleiding

Fase 3 ontdekte dat `nutsh test` (v2.0.0, gebruikt door T1 en door T3/T7 via
`run_tutorial -t`) paniekt op 13 van de 15 lessen (`panic: Expect was not
reached: <commando>`), zelfs wanneer het commando zichtbaar correct
uitvoerde. Onderzoek in nutsh's eigen broncode (`github.com/turkenh/nutsh`,
`refresh`-branch = de basis van `v2.0.0`) wees de oorzaak aan:
`parser/interpret.go`'s `prompt`-afhandeling zet `s.current_expect` vóór
`dsl.SimulatePrompt(...)`, en clearet dat pas als de `if success &&
command == "..."`-guard slaagt; `success` roept zelf een *aparte*
`run("echo $?")`-rondgang aan via dezelfde PTY-sessie
(`cli.QueryInteractive`, waarvan `Query` een dunne wrapper is). Wanneer die
tweede rondgang niet synchroon loopt met de eerste, blijft
`s.current_expect` gezet en paniekt de interpreter op de eerstvolgende
check (`interpret.go:126-129`) — een race condition in nutsh's eigen
PTY-tokenizer, dezelfde `cli`-package waar ook de bekende #37-tokenizerbug
zat.

**Besluit (gebruiker):** nutsh niet forken/patchen (grote, blijvende
onderhoudslast voor een race condition in andermans PTY state machine).
In plaats daarvan: **T1/T3/T7 vervangen door een eigen driver die de
lesinhoud rechtstreeks uitvoert**, buiten nutsh's testmodus om. De
interactieve modus (`nutsh run`, wat een echte gebruiker ervaart) blijft
ongemoeid — die is al bevestigd volledig groen (T4, fase 3).

## `tests/t1_lessons.py` — de vervanger

Elk lesbestand is een lineaire reeks van:
- top-level `run(\`cmd\`)`-regels en de twee macro's `make_and_go_ws`/
  `clear_ws` (workspace-setup), en
- `prompt { if [!]success && command == "X" { expect ("X") ... } }`-blokken.

Het script parseert dit rechtstreeks uit de `.nutsh`-bron (dezelfde
`expect()`-commando's die nutsh's eigen testmodus zou typen), bouwt er één
shell-script van, en voert dat uit via **één persistente**
`docker exec -i ansible.tutorial bash`-sessie (zodat `cd`/state normaal
blijft doorlopen tussen commando's — zie "Bug in eigen driver" hieronder).
Commando's gemarkeerd met `!success` (2 stuks in de hele suite: lesson 7's
en lesson 8's bewust-falende `ansible-playbook`-run) worden op een
niet-nul exitcode gecontroleerd i.p.v. nul.

**Bug in eigen driver (gevonden en gefixt tijdens verificatie):** de eerste
versie wrapte elke stap in een eigen `bash -c "..."`. Een `cd` in een
geneste subshell werkt niet door naar het bovenliggende script, dus
`make_and_go_ws`'s `cd /root/workspace` had geen effect op de
daaropvolgende stappen — commando's "slaagden" nog steeds (ze draaiden
allemaal consistent vanuit `/root`), maar bestanden kwamen nooit terecht in
de bind-mounted `/root/workspace` waar T7 op vertrouwt om geconvergeerde
staat vanuit een tweede container te zien. Fix: commando's rechtstreeks als
regels in het gedeelde script i.p.v. genest in `bash -c`.

## Geverifieerd: alle 15 lessen, op een volledig verse omgeving

| Les | Resultaat |
|---|---|
| 0–12 (13 lessen) | **PASS** |
| 13-step-13 (Jenkins) | **FAIL** — al bekend, #32/#39 (zie hieronder voor een preciezere diagnose) |
| 14-freeplay | **PASS** (geen echte inhoud, alleen de exit-marker `done`, terecht overgeslagen) |

**14 van de 15 lessen groen** — de enige rode is de al vóór deze fase
getrackte Jenkins-les.

## Vier echte bugs gevonden en gefixt (niet nutsh, niet de driver)

Omdat de eigen driver commando's *echt* uitvoert i.p.v. crashen vóór het
punt waarop nutsh's testmodus altijd paniekte, kwamen vier bestaande,
tot nu toe onzichtbare bugs aan het licht:

1. **`iproute2` ontbrak** op de managed-host image (fase 3 installeerde
   alleen `net-tools`). Moderne ansible's netwerk-fact-gathering
   (`ansible_eth0`, `ansible_default_ipv4`, ...) vereist het `ip`-commando;
   zonder `iproute2` blijven die facts stil afwezig →
   `AnsibleUndefinedVariable: 'ansible_eth0' is undefined` in haproxy's
   Jinja-template (lessen 10/11). **Fix:** `iproute2` toegevoegd aan
   `images/ansible-managed-host/Dockerfile`.

2. **`ansible-galaxy --offline init roles/haproxy` (les 13/`12-step-12`)**
   is verouderde CLI-syntax. Moderne `ansible-galaxy` vereist het
   `TYPE`-subcommando vóór de actie: `ansible-galaxy role init --offline
   roles/haproxy`. **Fix:** `tutorials/12-step-12.nutsh` bijgewerkt (zowel
   het getoonde commando als de `if`/`expect`-match).

3. **PID 1 in de managed-host container heette letterlijk "script"**
   (`images/common/start.sh`'s idle-lus was `exec script -q -c "tail -f
   /dev/null" /dev/null`). Ansible's `service_mgr`-fact-detectie leest
   PID 1's process-naam om het init-systeem te raden; op containers zonder
   systemd zag het toevallig de string "script" en gebruikte die als
   (onbestaand) service-manager-type, waarna **élke** `service:`-taak
   faalde met `"module (script) is missing interpreter line"`. Dit trof
   alle lessen met een `service:`-handler (9, 10, 11, 12, 13 — apache- en
   haproxy-restarts incluis). **Fix:** de onnodige `script`-pty-wrapper om
   de idle `tail -f /dev/null` weggehaald (`exec tail -f /dev/null`
   volstaat, `tail -f` is niet interactief en had nooit een pty nodig).
   Na de fix detecteert Ansible correct `ansible_service_mgr: sysvinit`.

4. **`step-10/templates/haproxy.cfg.j2` miste een eind-newline**
   (`step-11`/`step-12`'s kopieën hadden 'm al). Haproxy 3.2 weigert een
   config zonder LF op de laatste regel te laden: `"Missing LF on last
   line, file might have been truncated"`. **Fix:** trailing newline
   toegevoegd.

Bevindingen 1, 3 en 4 zijn **image-/infra-fixes** (horen bij fase 3's
"images bouwen weer" maar waren toen onzichtbaar doordat nutsh's testmodus
er nooit doorheen kwam); bevinding 2 is een **content-fix** (fase-5-achtig,
maar zo klein en eenduidig dat 'm meteen meenemen zinniger was dan een
aparte fase ervoor optuigen).

## Resterend: lesson 13 (Jenkins) — preciezere diagnose dan #32/#39

Met de PID1/service_mgr-fix (bevinding 3 hierboven) opgelost, komt lesson
13 nu **veel verder** dan voorheen (22 taken ok, pas bij de laatste
"Ensure Jenkins is started"-taak faalt het) — de eerder aangenomen
"systemd ontbreekt"-blocker is dus niet meer het probleem. De resterende
fout is dezelfde vorm als bevinding 3 leek te zijn, maar is het niet:
`"Service is in unknown state", "status": {}` bij het starten van
`jenkins`. Handmatig gereproduceerd: `service jenkins status` geeft exit 3
("jenkins is not running", een geldige LSB-not-running-code) — Ansible's
klassieke SysV-`service`-module lijkt dit specifieke statustekstformaat
niet te herkennen als "geldig, gewoon niet gestart", en valt terug op
"unknown state" i.p.v. door te gaan met starten. (Ter vergelijking: dit
bleek **geen** probleem voor haproxy in de volledige lesflow — die les zet
zelf al `ENABLED=1` in `/etc/default/haproxy` vóórdat de restart-handler
draait, wat blijkbaar de conditie vermijdt waarin dit optreedt.) Dit is een
diepere eigenaardigheid van ansible-core's klassieke `service`-module met
niet-mainstream SysV-initscripts, niet iets in onze eigen code — blijft
**fase-5-werk** samen met de al getrackte #32 (java-dependency, inmiddels
overigens al aanwezig — geen fout meer gezien over ontbrekende
`geerlingguy.java`) en #39 (dode Jenkins-repo-URLs, nog niet apart
geverifieerd).

## T3/T7 bijgewerkt

- **`tests/t7_idempotency.sh`**: `run_tutorial -t` → `t1_lessons.py`.
  Terzijde ontdekt en gefixt: het script had zelf nog de **verouderde**
  `turkenh/ansible-tutorial:1.1`-image hardcoded voor zijn
  throwaway-heruitvoer-container (een fase-3-omissie — die variabele werd
  toen niet meegenomen). Nu consistent met `tutorial.sh`'s
  `beverdam/ansible-tutorial:2.0`-default, met dezelfde env-override.
  Environment-lifecycle (`start_environment`/`trap stop_environment EXIT`)
  verplaatst naar het script zelf i.p.v. impliciet via `run_tutorial`.
  Geverifieerd op een verse omgeving: lesson5-apache en lesson6-apache
  idempotent (`changed=0`, zoals voorzien — alleen apt/copy/file-taken);
  lesson9-git en lesson10-apache **niet** idempotent (zoals voorzien — de
  `command:`-taken zonder `changed_when`, fase-5-werk).
- **`tests/t3_checkpoints.sh`**: zelfde omzetting, `run_tutorial -t` →
  `t1_lessons.py`, plus `start_environment`/`trap stop_environment EXIT`
  toegevoegd (voorheen impliciet via `tutorial.sh`'s eigen init in
  `run_tutorial`). **Geverifieerd, blijft rood** — maar nu met eerlijk
  signaal i.p.v. de nutsh-panic: `curl` op host1 poort 80 geeft `HTTP 000`.
  Dit bevestigt de al bestaande fase-1-bevinding
  (`files/step-4/apache.yml` installeert apache2 maar start de service
  nooit expliciet; deze image's `/start.sh` draait geen init die dat als
  neveneffect zou doen) — geen nieuwe bug, gewoon nu correct gemeten i.p.v.
  gemaskeerd door de nutsh-panic. Fix blijft fase 5. Jenkins-checkpoint
  blijft expected-fail (#32/#39, zie hierboven voor de preciezere diagnose).

## CI

`t1-lessons`, `t3-checkpoints`, `t7-idempotency`, en `t6-podman`'s
t1-smoke-stap gebruiken vanaf nu `t1_lessons.py`/de bijgewerkte T7 i.p.v.
`nutsh test`. Zie `.github/workflows/test.yml` voor de bijgewerkte jobs.

## Nog open voor latere fasen

- T5 (nutsh-eigen unittests) — nog niet gestart; gegeven dat we nutsh niet
  meer patchen, is de relevantie hiervan heroverwogen (zie `PLAN.md`).
- #25 (WSL-menu) — blijft een handmatige/omgevingscheck, niet uitvoerbaar
  in deze headless CLI-omgeving.
- Lesson 13/Jenkins — #32 (java-dependency, lijkt inmiddels aanwezig te
  zijn — geen fout meer over ontbrekende `geerlingguy.java` gezien) en #39
  (dode Jenkins-repo-URLs, nog niet apart geverifieerd) plus de nieuwe
  `service`-module-diagnose hierboven, fase 5.
- T7: `changed_when`/`creates=` toevoegen aan de apache `command:`-taken
  (lesson9-git, lesson10-apache, en naar verwachting lesson11-templates en
  lesson13-roles — nog te bevestigen, zie eindresultaat hieronder), fase 5.
