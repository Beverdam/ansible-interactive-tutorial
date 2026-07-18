# Fase 7 — Jenkins: definitieve grens vastgesteld (geen enkele rolversie werkt)

**Status:** onderzoek compleet, architectuurbeslissing nodig van de gebruiker.
**Datum:** 2026-07-18.

## Wat is onderzocht

Voortbouwend op fase 6's bevinding (`geerlingguy.jenkins`'s nieuwste versie
roept `systemd: daemon_reload: true` hardgecodeerd aan, vereist een echte
systemd-D-Bus-verbinding die onze init-loze containers niet hebben), is de
volledige commit- en tag-geschiedenis van de upstream role
(`github.com/geerlingguy/ansible-role-jenkins`) doorzocht om een
**overlappende, veilige versie** te vinden — een die zowel:

(a) nog de generieke, auto-detecterende `service:`-module gebruikt (niet
    hardgecodeerd `systemd:`), én
(b) een moderne, werkende manier heeft om de Jenkins-apt-repository-sleutel
    te installeren (niet via het `apt-key`-commando, dat sinds enkele jaren
    volledig uit Debian/Ubuntu zelf verwijderd is — niet alleen
    gedeprecieerd in Ansible, het commando bestaat simpelweg niet meer op
    Ubuntu 26.04).

**Uitkomst: zo'n versie bestaat niet.**

| Gebeurtenis | Commit | Datum |
|---|---|---|
| Laatste versie met generieke `service:`-module | tag `4.3.0` | — |
| Overschakeling naar hardgecodeerd `systemd:` | `6268840` "Initalise Jenkins with systemd instead of init" | 2022-06-04 |
| Eerste versie mét dat probleem | tag `5.0.0` | — |
| Moderne apt-key-fix (`get_url` i.p.v. `apt_key`) | `c19593f` "Fixes #362: Use .asc file extension for apt key" | 2022-08-30 |

`5.0.0` (eerste systemd-versie) verscheen **vóór** de apt-key-modernisering
(30 augustus 2022) — bevestigd met
`git merge-base --is-ancestor 6268840 c19593f` (waar). Er is dus geen
enkele geschiedenis-periode waarin de role tegelijk (a) en (b) had.

**Concreet geprobeerd en empirisch bevestigd, niet alleen afgeleid uit de
geschiedenis:**
- `geerlingguy.jenkins==4.3.0` gepind via een `requirements.yml`: faalt op
  `"Failed to find required executable 'apt-key' in paths: ..."` — het
  commando bestaat niet op deze Ubuntu 26.04-images
  (`dpkg -S apt-key` → geen enkel pakket levert het (meer)).
- Nieuwste versie (ongepind, zoals origineel): faalt op
  `"System has not been booted with systemd as init system (PID 1)"`
  (al vastgesteld in fase 6).

## De echte keuze

Er zijn maar twee manieren om dit alsnog werkend te krijgen, en beide zijn
fundamenteel andere ingrepen dan de content-fixes tot nu toe:

1. **Echte systemd laten draaien in de managed-host-containers.** Dit is
   een architectuurwijziging die verder gaat dan lesson 14 alleen: het
   `images/ansible-managed-host/Dockerfile`, `images/common/start.sh` en
   `tutorial.sh`'s `docker run`-aanroep (waarschijnlijk `--privileged` of
   specifieke capabilities + cgroup-mounts nodig) zouden allemaal moeten
   veranderen. Dit project heeft tot nu toe bewust gekozen voor lichte,
   init-loze containers (zie `images/common/start.sh`'s hele ontwerp) —
   systemd toevoegen raakt die keuze voor **alle vijftien lessen**, niet
   alleen Jenkins, met een reëel risico op nieuwe, andersoortige
   regressies elders.
2. **Jenkins definitief als geaccepteerde, gedocumenteerde beperking
   laten staan.** De les blijft bruikbaar als leesvoorbeeld (de tekst,
   commando's en uitleg over Ansible Galaxy/rollen blijven correct en
   leerzaam), maar de daadwerkelijke Jenkins-service start niet. Dit is in
   feite waar het project al die tijd al stond (#32/#39 stonden al vóór
   fase 0 als "expected-fail" genoteerd) — nu alleen met een sluitende,
   volledig onderbouwde verklaring waaróm, in plaats van een vermoeden.

Optie 1 is een bewuste, project-brede architectuurbeslissing met reële
neveneffecten; optie 2 kost niets extra maar laat de les net iets minder
compleet. Dit is een keuze die de projecteigenaar moet maken, geen
technische correctheidskwestie.

## #25 (nutsh-menu ontbreekt op WSL)

Nutsh's broncode (`cli/`, `dsl/`) bevat geen enkele WSL- of
terminal-type-specifieke logica (`grep` op `TERM`/`isatty`/`WSL`/
`windows` levert niets op) — het probleem, als het nog bestaat, zit dus
vermoedelijk in hoe WSL's terminal-emulatie omgaat met de ANSI-reeksen die
nutsh gebruikt, niet in een aanwijsbare code-tak. Zonder een echte
WSL-omgeving is dit niet verder te onderzoeken of te verifiëren — blijft
ongewijzigd een handmatige/omgevingscheck, zoals in eerdere fases al
vastgesteld.
