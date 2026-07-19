# Fase 13 — twee losse CI-oorzaken ontward; één gefixt, één gaat diagnostiek verzamelen

**Status:** container-start-timeout gefixt; T4-#12 krijgt debug-output om
eindelijk de echte oorzaak te vangen. **Datum:** 2026-07-19.

## Aanleiding

De fase-12-merge-run faalde op **drie** jobs, en dat dwong een eerlijkere
analyse af dan "gewoon nog een keer proberen":

- `t1 (5-step-05)` — een **blocking** job die nooit eerder faalde
- `t6-podman` en `t4-pty` — dezelfde T4-#12-check als altijd

Het cruciale inzicht: dit zijn **twee verschillende oorzaken** die
toevallig in één run samenvielen, niet één probleem.

## Oorzaak 1 (gefixt): container-start-timeout te krap

`t1 (5-step-05)` faalde met `timed out waiting for: ansible.tutorial
container running`, **exact 60s** na `env.sh up`. Dat is precies
`start_environment`'s `wait_for 60`-plafond in `tests/lib.sh`. Op deze
specifieke, trage/belaste runner kwam de tutorial-container niet binnen
60s omhoog — logisch, want de eerste run bouwt óók de images (fase-8
auto-build) en haalt de `ubuntu:26.04`/nutsh-baselagen op.

**Fix:** de `wait_for`-plafonds in `start_environment` (`tests/lib.sh`) en
de restart-stap (`tests/t2_lifecycle.sh`) van 60s → 180s. `wait_for` keert
terug zodra de conditie waar is, dus een ruimer plafond kost niets op een
snelle runner — het voorkomt alleen valse timeouts op een trage.

## Oorzaak 2 (nog niet begrepen): T4-#12

In diezelfde run kwam de omgeving in de **t4-pty**-job juist snel op
(`env.sh up` klaar in ~2s, menu binnen 1s) — daar was de runner dus níét
traag, en tóch verscheen de shell-prompt niet na de leskeuze. De
fase-12-retry-loop draaide de volle ~48s (stuurde "1" herhaald) zonder
resultaat. Belangrijk: check #22 ("typed command is echoed back")
**slaagt** direct daarna — input komt dus wél aan. Dat weerlegt zowel de
fase-10-theorie ("toetsaanslag gaat verloren") als het idee dat de
retry-loop het venster zou dichten.

Lokaal de exacte prompt-bytes vastgelegd die nutsh na de leskeuze
uitstuurt:

```
...\x1b[34m\x1b[1m~/workspace $ \x1b[0m
```

De regex `workspace \$` matcht daar aantoonbaar tegen (lokaal
geverifieerd) — dus onder normale omstandigheden werkt de test. Wat er op
CI precies anders gaat, is met de huidige informatie niet vast te stellen:
de faling is **nooit lokaal gereproduceerd** (deze dedicated sandbox is te
rustig), en twee geraden fixes op rij (vaste vertraging, retry-loop)
konden daarom niet getoetst worden tegen het echte probleem.

**Aanpak: stoppen met gokken, data verzamelen.** `tests/t4_pty.py` dumpt
nu bij een #12-faling de laatste ~800 tekens van nutsh's ruwe
PTY-buffer (`T4 [DEBUG] #12 failed; last N chars...`). De eerstvolgende
falende CI-run levert dan het feitelijke bewijs: is de les wél gestart
maar matchte de prompt-detectie niet, hing nutsh midden in het menu, of
gebeurde er iets heel anders. Pas met die bytes in de hand is een gerichte
fix te maken in plaats van een derde gok.

## Status van de CI-annotaties

`t4-pty` en `t6-podman` blijven `continue-on-error` (sinds fase 12) — de
timeout-verhoging raakt hun eigen falen niet, en #12 is nog niet opgelost.
`t1`-matrix blijft blocking: de timeout-fix daar is een echte oplossing
voor een begrepen oorzaak, geen gok.

## Geverifieerd

- T4 en T2 lokaal opnieuw gedraaid met alle wijzigingen — beide `PASS`
  (de debug-tak wordt alleen bij een faling geraakt, verandert het
  succespad niet).
