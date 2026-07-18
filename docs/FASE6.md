# Fase 6 — t6-podman gefixt; Jenkins nog dieper gediagnosticeerd

**Status:** t6-podman opgelost en geverifieerd (root cause). Jenkins:
twee echte bugs gevonden en gefixt, een derde (harde) blocker vastgesteld
die buiten ons bereik ligt zonder de containerarchitectuur te wijzigen.
**Datum:** 2026-07-18.

## Aanleiding

De eerste twee "echte" GitHub Actions-runs (op de fase-4- en fase-5-merges)
leverden CI-data op die lokaal niet te reproduceren was:
- `t6-podman` faalde op GitHub met een **andere** oorzaak dan de lokale
  `apt-get update`-hang uit fase 3/4 (die leek op een geneste-netwerk-
  eigenaardigheid van déze werkomgeving).
- `t7-idempotency`/`t3-checkpoints`/`t4-pty` bevestigden op echte
  GitHub-infrastructuur dat de fase-5-fixes werken (allemaal groen).

## t6-podman — root cause gevonden en gefixt

GitHub's runner-log:
```
cannot find UID/GID for user beverdam: no subuid ranges found for user
"beverdam" in /etc/subuid - check rootless mode in man pages.
```

`/home/runner/work/...` in dezelfde log bevestigt dat de OS-gebruiker
gewoon de standaard `runner` is — maar podman zocht naar subuid-ranges
voor een user genaamd **"beverdam"**, die niet bestaat. Root cause:
**`images/Makefile` had een variabele letterlijk `USER=beverdam`.** GNU
Make exporteert variabelen die al in de overgeërfde omgeving aanwezig
waren automatisch door naar child-processen, óók nadat de Makefile ze
herdefinieert — en `$USER` is precies zo'n vooraf-bestaande
omgevingsvariabele (de shell zet 'm op de echte inlognaam). Onze
Makefile's `USER=beverdam` overschreef dus `$USER` voor élk commando dat
`make` uitvoerde, inclusief `podman build` — en rootless podman leest
`$USER` om de subuid/subgid-range van de huidige gebruiker op te zoeken.

Dit bleef lokaal onopgemerkt omdat ik hier als **root** test: root heeft
geen rootless-UID-remapping nodig, dus de kapotte `$USER`-waarde deed er
nooit toe.

**Fix:** de Makefile-variabele hernoemd van `USER` naar `IMAGE_NAMESPACE`
— functioneel identiek (nog steeds `beverdam/ansible-managed-host:2.0` als
image-tag), maar botst niet meer met de shell-omgeving. Geverifieerd:
`make build_all` bouwt nog steeds correct getagde images.

## Jenkins (#32/#39) — twee bugs gefixt, één harde blocker overgebleven

Voortbouwend op fase 5's diagnose (role routeert via `systemd:` i.p.v.
`service:` voor de daemon-reload-stap), zijn twee **extra**, eerder
onzichtbare content-bugs gevonden door de les stap voor stap op een
volledig verse omgeving te draaien:

1. **`openjdk-25-jdk` bestaat niet als los pakket op Ubuntu 26.04** (alleen
   de `-headless`-variant). `geerlingguy.java`'s eigen
   `vars/Ubuntu-26.yml` documenteert dit zelf: "`openjdk-25-jdk` (default,
   non-LTS)" naast expliciet genoemde LTS-alternatieven waaronder
   `openjdk-21-jdk (LTS, in universe)`. **Fix:** `java_packages:
   [openjdk-21-jdk]` als officieel-ondersteunde override-variabele
   toegevoegd aan `tutorials/files/step-13/jenkins.yaml` (niet de role
   zelf aangepast — dat kan niet, wordt vers gedownload).
2. **`host0` heeft nooit een `apt update` gehad** vóór deze les (anders
   dan host1/host2, die elke apache-les updaten), en geen van beide roles
   (`geerlingguy.java`, `geerlingguy.jenkins`) doet dit zelf — op een
   écht verse host faalt daardoor élke package-install met "No package
   matching ... is available", ook al bestaat het pakket wel degelijk.
   **Fix:** een `pre_tasks:`-blok met `apt: update_cache=true`
   toegevoegd aan `jenkins.yaml`. **Belangrijk detail, fout bij eerste
   poging:** dit moet `pre_tasks:` zijn, niet `tasks:` — in Ansible draaien
   `roles:` vóór een play's eigen `tasks:`, dus een gewone `tasks:`-entry
   komt te laat om de rol se eigen package-installs te helpen. Empirisch
   ontdekt (de taak verscheen domweg niet in de uitvoer) en gecorrigeerd.

**Resultaat van deze twee fixes:** de les komt nu **veel verder** — Java
installeert, Jenkins-pakket installeert, init-bestanden worden
geconfigureerd (`ok=24, changed=10` vóór de fout, was eerder `ok=6,
failed=1` op de java-stap).

**Derde, niet-gefixte blocker:** `geerlingguy.jenkins/tasks/settings.yml`
roept **rechtstreeks en onvoorwaardelijk** de `systemd:`-module aan met
`daemon_reload: true` (een handler, getriggerd door wijzigingen in het
init-bestand) — dit is geen `service:`-dispatch-kwestie meer (die correct
naar `sysvinit` routeert, zoals fase 5 al vaststelde) maar een
**hardgecodeerde systemd-aanroep** die een echt draaiende systemd-daemon
via D-Bus vereist:

```
failure 1 during daemon-reload: System has not been booted with systemd
as init system (PID 1). Can't operate.
```

Geen van de role's documented variabelen biedt een manier om deze
specifieke handler over te slaan of te vervangen. Een echte fix zou
vereisen: (a) echte systemd laten draaien in de managed-host-containers —
een fundamentele architectuurwijziging die niet lichtzinnig genomen moet
worden gezien de bewuste "geen init, houd het licht"-opzet van dit hele
project, of (b) een oudere `geerlingguy.jenkins`-rolversie pinnen die deze
handler nog niet had (onzeker, vereist trial-and-error over
historische versies). Beide zijn niet-triviale, apart te plannen
vervolgstappen — Jenkins blijft daarom een geaccepteerd "expected-fail"
in T1/T3, nu met een veel preciezere en verder-gevorderde diagnose dan bij
elke eerdere fase.

## Wat nog open staat

- Jenkins volledige fix: systemd in de container, of een oudere role-pin
  — apart te plannen, mogelijk buiten de scope van "lichte containers
  zonder init" die dit project verder consequent aanhoudt.
- #25 (WSL-menu): blijft een handmatige/omgevingscheck.
- T5 (nutsh-eigen unittests): relevantie blijft heroverwogen, niet
  gestart.
