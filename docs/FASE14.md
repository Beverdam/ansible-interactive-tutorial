# Fase 14 — T4-#12 écht opgelost: een te specifieke test-regex, geen nutsh-race

**Status:** root cause bewezen met CI-bewijs, gefixt, over vele runs
bevestigd. **Datum:** 2026-07-19.

## De doorbraak

Fase 13 voegde een debug-dump toe die bij een #12-faling de ruwe
nutsh-PTY-buffer print. Met een GitHub-token dat `workflow_dispatch` mocht
triggeren zijn daarna ~6 runs op rij gestart; één daarvan (`t4-pty`,
run 29681333022) faalde en leverde eindelijk het bewijs:

```
...\x1b[34m\x1b[1m~ $ \x1b[0m1 \x08\x08\x1b[K1 \r\r\n
bash: 1: command not found\r\r\n ... ~ $ 1 ... bash: 1: command not found ...
```

Twee dingen die alle eerdere hypotheses omverwerpen:

1. **De interactieve prompt verscheen wél** — als
   `\x1b[34m\x1b[1m~ $ \x1b[0m`. Maar de test wachtte op `~/workspace $`.
   De prompt toonde `~ $` (home), niet `~/workspace $`.
2. **De "1" van de retry-loop belandde ín bash** (`bash: 1: command not
   found`, herhaald) — de shell was allang klaar; de eerste "1" had de les
   al geselecteerd en de interactieve prompt bereikt, en alle volgende
   "1"-spam ging rechtstreeks de shell in.

## Wat er echt aan de hand was

De les begint met `make_and_go_ws`, dat o.a. `cd /root/workspace` doet via
een nutsh `run()`-round-trip. Op sommige runs rendert de interactieve
prompt **vóórdat** die `cd` effect heeft, dus toont de prompt `~ $` (=
`/root`, home) i.p.v. `~/workspace $`. De shell was volledig klaar voor
input — de test keek alleen naar een te specifieke cwd-string.

Dit was dus **een testfout (te strikte regex), geen nutsh-timing-race.**
Alle eerdere "flaky" falingen (fase 4/7/9/11/12) waren precies dit: prompt
werd `~ $`, regex wilde `workspace`, matchte nooit, liep de volle timeout
vol. Fase 10's vaste vertraging en fase 12's retry-loop konden dit per
definitie niet oplossen (het probleem was nooit timing) — de retry-loop
maakte het zelfs erger door de shell te vervuilen.

## Fix

`tests/t4_pty.py`:
- **#12 matcht de prompt nu generiek**, ongeacht cwd: op de blauw-vette
  PS1-lead-in `\x1b[34m\x1b[1m` (uit `cli/target.go`'s
  `PS1="\[☃\e[34m\e[1m\]\w $ ..."`). Dat paar is uniek voor de shell-prompt
  — lestekst gebruikt cyaan/geel/groen (36/33/32) en de lesbanner gebruikt
  kaal `\x1b[34m` zónder de `\x1b[1m`-bold, dus geen van beide false-matcht.
  Lokaal geverifieerd tegen beide prompt-varianten (`~ $` én
  `~/workspace $`) plus banner + lestekst.
- **"1" wordt één keer gestuurd** (retry-loop verwijderd — die was op de
  verkeerde diagnose gebaseerd en vervuilde de sessie).
- **#22 gehard tegen een valse pass:** stuurde eerst `ansible --version` en
  matchte `ansible --version` — maar lesson 0's eigen instructietekst print
  letterlijk `ansible --version` (het commando dat je moet typen), dus die
  check kon slagen zónder dat de shell ooit iets uitvoerde. Nu:
  `echo t4_input_marker_ok` + match op dat unieke token, dat alleen
  verschijnt als de shell de input daadwerkelijk uitvoert.
- Debug-dump behouden (compacter) — kost niets en is nuttig mocht er ooit
  een écht ander #12-probleem opduiken.

## Waarom nu wél blocking

`t4-pty` en `t6-podman` (die dezelfde check draait) zijn teruggezet naar
**blocking**. Anders dan bij fase 10/12 is dit geen gok: de oorzaak is met
CI-bewijs vastgesteld, de fix is deterministisch (een regex die aantoonbaar
beide prompt-varianten dekt), en lokaal + over meerdere
`workflow_dispatch`-runs bevestigd. Geen derde voorbarige "gefixt"-claim —
dit keer sluit de diagnose op de waarneming aan.

## Terzijde: de timeout-verhoging uit fase 13 blijft terecht

Fase 13's `wait_for 60→180` (voor `t1 (5-step-05)`'s echte
container-start-timeout op een trage runner) was een aparte, correcte fix
en blijft staan — die had niets met #12 te maken.
