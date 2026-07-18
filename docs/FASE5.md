# Fase 5 — Idempotentie, apache-service, Jenkins-diagnose, CI-bevindingen

**Status:** T7/T3 compleet en geverifieerd; Jenkins gedeeltelijk (dieper
gediagnosticeerd, niet gefixt). **Datum:** 2026-07-18.

## T7 — idempotentie (compleet, geverifieerd)

De apache-`command:`-taken (`a2ensite`/`a2dissite`/`apache2ctl configtest`)
hadden geen `changed_when`/`creates=`/`removes=`, dus Ansible rapporteerde
`changed` op elke run, ongeacht echte staatsverandering. Empirisch
geverifieerd (niet aangenomen) welke bestandsnamen `a2ensite`/`a2dissite`
daadwerkelijk aanmaken/verwijderen:

```
a2ensite X  -> symlink /etc/apache2/sites-enabled/X.conf -> ../sites-available/X.conf
a2dissite X -> verwijdert diezelfde symlink
```

**Fix, toegepast op alle 6 bestanden met dit patroon**
(`tutorials/files/step-{8,9,10,11}/apache.yml`,
`tutorials/files/step-12/apache_tasks.yml`; `step-11` zat niet in T7's
scope maar kreeg dezelfde fix voor consistentie — identieke inhoud, anders
zou een toekomstige lezer zich afvragen waarom de ene kopie wel en de
andere niet gefixt is):

- `a2ensite X` → `+ creates=/etc/apache2/sites-enabled/X.conf`
- `a2dissite X` → `+ removes=/etc/apache2/sites-enabled/X.conf`
- `apache2ctl configtest` → `+ changed_when: false` (een check-commando,
  verandert nooit iets op schijf)

**Geverifieerd op een volledig verse omgeving — `tests/t7_idempotency.sh`
volledig groen:**

| Label | Vóór fase 5 | Na fase 5 |
|---|---|---|
| lesson5-apache, lesson6-apache | idempotent | idempotent (ongewijzigd) |
| lesson9-git | **niet idempotent** | **idempotent** |
| lesson10-apache | **niet idempotent** | **idempotent** |
| lesson11-templates | **niet idempotent** | **idempotent** |
| lesson12-haproxy | idempotent | idempotent (ongewijzigd) |
| lesson13-roles | **niet idempotent** | **idempotent** |

`T7: PASS` — geen enkele `NOT IDEMPOTENT` meer.

## T3 — apache-service (compleet, geverifieerd)

`tutorials/files/step-4/apache.yml` installeerde `apache2` maar startte de
service nooit expliciet (fase-1-bevinding). Fix: expliciete
`service: name=apache2 state=started`-taak toegevoegd.

**Lestekst bijgewerkt** (`tutorials/4-step-04.nutsh`): de oorspronkelijke
tekst zei "our (first and only) task" en toonde een voorbeeld-`PLAY RECAP`
met `ok=2 changed=1`. Met de nieuwe taak erbij is dat niet meer waar — de
tekst is aangepast naar twee taken en een bijgewerkte
`ok=3 changed=2`-recap, empirisch geverifieerd tegen de echte uitvoer (zie
hieronder).

**Geverifieerd, twee keer op een volledig verse omgeving:**
- Eerste run: `changed=2` (apt install + service start, beide echt nieuw)
- Tweede run (idempotentie-demonstratie, al onderdeel van de les): `changed=0`
- `curl` op host1 poort 80 → **HTTP 200 OK** (was: HTTP 000, connectie geweigerd)

`tests/t3_checkpoints.sh apache` is nu volledig groen.

## Lesson 13/Jenkins (#32/#39) — dieper gediagnosticeerd, niet gefixt

Voortbouwend op fase 4's diagnose ("Service is in unknown state" bij het
starten van jenkins), is de **exacte routing-oorzaak** nu gevonden door
Ansible's eigen broncode te lezen (`plugins/action/service.py`,
`modules/systemd.py`):

- De `service:`-module-dispatcher kiest normaliter de module die
  overeenkomt met de `ansible_service_mgr`-fact (bij ons: `sysvinit`, sinds
  de fase-4-PID1-fix) — de klassieke SysV-fallback (`modules/service.py`,
  `LinuxService`-klasse) verwerkt exit-code 3 ("niet actief", LSB-conform)
  al correct via een expliciete rc-code-check
  (`if self.running is None and rc in [1, 2, 3, 4, 69]: self.running = False`).
- **Maar** de foutmelding "Service is in unknown state" komt uit een
  *andere* module: `modules/systemd.py`. De `geerlingguy.jenkins`-role
  gebruikt kennelijk de `systemd:`-module direct (of forceert
  `use: systemd`) in plaats van de generieke, auto-detecterende `service:`,
  wat onze correcte `sysvinit`-detectie omzeilt.
- In onze containers is `/usr/bin/systemctl` wél aanwezig (onderdeel van
  Ubuntu's basis-systemd-pakketten) maar er draait geen echte systemd als
  PID 1 — `systemctl show <unit>` levert dus geen bruikbare `ActiveState`
  op, en `systemd.py` valt terug op de exacte code-tak die de fout
  veroorzaakt: `elif is_chroot(module) or SYSTEMD_OFFLINE == '1': warn(...)
  else: fail_json("Service is in unknown state")`.
- **`SYSTEMD_OFFLINE=1` is geen volledige fix:** die tak *onderdrukt* de
  crash (`module.warn` i.p.v. `fail_json`), maar voert daarna **geen**
  `systemctl start`-commando meer uit — de taak zou dan "slagen" zonder dat
  Jenkins daadwerkelijk gestart wordt, wat de les alsnog stuk zou laten
  gaan (curl-checkpoint blijft falen), nu alleen stiller.
- **Niet uitgevoerd:** de `geerlingguy.jenkins`-role zelf is niet door ons
  te wijzigen (wordt vers gedownload via `ansible-galaxy install` bij elke
  lesrun) — een echte fix vereist een andere/oudere rolversie pinnen via
  een `requirements.yml` (zoals `PLAN.md` §6 al voorzag) die mogelijk een
  eigen, robuustere service-startlogica gebruikt, of het uitschakelen van
  `systemctl` op de managed-host image zodat Ansible's dispatcher sowieso
  nooit de systemd-route kiest. Beide zijn niet-triviale, apart te
  verifiëren vervolgstappen — blijft open voor een latere fase.

## CI-bevinding: t6-podman op GitHub — nieuwe, andere oorzaak dan lokaal

Fase 3/4 documenteerden dat een lokale `podman build`-poging hing op
`apt-get update` (vermoedelijk een geneste-netwerk-eigenaardigheid van déze
werkomgeving). De eerste échte GitHub Actions-run van de fase-4-merge laat
een **andere, wél overdraagbare** oorzaak zien:

```
cannot find UID/GID for user beverdam: no subuid ranges found ...
potentially insufficient UIDs or GIDs available in user namespace
```

Rootless podman op GitHub's `ubuntu-latest`-runner heeft geen
`/etc/subuid`/`/etc/subgid`-ranges geconfigureerd voor de runner-gebruiker,
nodig om een multi-UID-image (Ubuntu 26.04) te bouwen. Dit is een bekend,
op te lossen podman-rootless-configuratieprobleem (bv. via
`sudo usermod --add-subuids`/`--add-subgids` of `podman system migrate` als
CI-stap), niet iets in onze Dockerfiles. `t6-podman` blijft terecht
`continue-on-error: true`; dit is nieuwe informatie voor een latere fase,
geen regressie.

## CI-bevinding: t4-pty eenmalige flaky failure op GitHub, geen regressie

De eerste GitHub-run na de fase-4-merge liet `t4-pty` falen op check #12
("shell prompt appears after selecting a lesson"), na exact de volledige
20s-timeout. **Onderzocht en weerlegd als regressie:** fase 4 raakte
`images/ansible-tutorial/` (waar nutsh zelf draait) en `tests/t4_pty.py`
geen van beide aan — beide bestanden zijn byte-identiek aan de
onmiddellijk voorgaande fase-3-run, die wél groen was op dezelfde
infrastructuur. Dit wijst op tijdelijke, gedeelde-runner-trage opstart
(container/PTY-cold-start), geen functionele regressie. Als voorzorg de
timeout van 20s naar 45s verruimd (`tests/t4_pty.py`) — geeft meer marge op
gedeelde CI-infrastructuur zonder de daadwerkelijke test te verzwakken (een
écht kapotte nutsh zou nog steeds falen, alleen na langer wachten).

## Wat nog open staat

- Lesson 13/Jenkins: volledige fix (role-versie pinnen of `systemctl`
  wegnemen uit de managed-host image) — apart te verifiëren, buiten deze
  fase.
- `t6-podman`: subuid/subgid-configuratie op de CI-runner toevoegen.
- #25 (WSL-menu): blijft een handmatige/omgevingscheck.
- T5 (nutsh-eigen unittests): nog niet gestart (relevantie heroverwogen nu
  we nutsh niet meer patchen, zie `PLAN.md`).
