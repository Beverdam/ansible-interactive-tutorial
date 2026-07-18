# Fase 8 — `tutorial.sh` bouwt images automatisch

**Status:** compleet, geverifieerd. **Datum:** 2026-07-18.

## Aanleiding

Sinds fase 3 moeten images lokaal gebouwd worden (`make -C images
build_all`) vóór `./tutorial.sh` voor het eerst draait — een verse
gebruiker die dat niet weet krijgt een verwarrende
`pull access denied for beverdam/ansible-managed-host`-foutmelding.
Feedback: een aparte bouwstap is onhandig voor relatief onervaren
gebruikers, die simpelweg `./tutorial.sh` willen draaien zoals de
oorspronkelijke tutorial altijd al beloofde.

## Fix

`tutorial.sh` checkt nu bij het starten (`init()`) of
`DOCKER_HOST_IMAGE`/`TUTORIAL_IMAGE` al lokaal bestaan
(`doesImageExist()`, `${CONTAINER_ENGINE} image inspect`). Ontbreken ze,
dan bouwt het script ze zelf via `make -C images build_all` — met een
duidelijke melding ("dit gebeurt maar één keer") zodat de eerste, langere
wachttijd niet als een hang aanvoelt. Bestaan de images al, dan is de
check een snelle no-op (geen merkbare vertraging bij normaal gebruik).

Geen apart `setup.sh`-script toegevoegd — dat zou weer een extra commando
zijn om te onthouden. `./tutorial.sh` blijft het enige aanspreekpunt.

## Geverifieerd

- Images verwijderd, `LESSON_NAME=0-step-00 ./tutorial.sh -t` gedraaid:
  bouwt beide images automatisch, start daarna gewoon door — les slaagt.
- Met images al aanwezig: geen "Images not found"-melding, geen merkbare
  vertraging (~6.5s totaal, gelijk aan de starttijd zonder de check).
- `tests/t2_lifecycle.sh` opnieuw gedraaid — nog steeds `T2: PASS`.

## README bijgewerkt

Quick-start terug naar alleen `./tutorial.sh` (was: eerst `make -C images
build_all`, daarna `./tutorial.sh`). `make` toegevoegd als vereiste naast
docker, met een korte uitleg dat de eerste run een paar minuten langer
duurt (het automatisch bouwen) en latere runs meteen starten.
