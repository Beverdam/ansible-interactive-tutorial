# Fase 10 — echte oorzaak van de T4-flakiness gevonden en gefixt

**Status:** compleet, root cause vastgesteld; wachten op CI-bevestiging
over meerdere runs. **Datum:** 2026-07-19.

## Aanleiding

`tests/t4_pty.py`'s check #12 ("shell prompt appears after selecting a
lesson") faalde intermitterend op GitHub's runners — drie keer nu, op
volledig ongerelateerde merges (fase 4, fase 7, fase 9), telkens **exact
op de volle timeout** (nooit bijna gelukt). Fase 5's fix (timeout 20s →
45s) loste dit niet op, alleen uitgesteld — bewijs dat het geen kwestie
van "iets trager deze keer" was.

## Root cause

Nutsh's eigen broncode (`model/model.go`, functie `SelectLesson`):

```go
fmt.Print("\nPlease select a lesson: ")

input := cli.GetInput()   // pas HIER wordt de input-lezer opgezet
buf := make([]rune, 0)
for {
    r := <-input
    ...
```

De prompt-tekst wordt geprint **vóórdat** de input-lezer wordt
geïnitialiseerd. Er is dus een echt tijdvenster tussen "de tekst is
zichtbaar in de PTY-buffer" en "nutsh is daadwerkelijk klaar om een
toetsaanslag te ontvangen". Onze test stuurt `"1\n"` op het moment dat de
tekst wordt gedetecteerd — als dat vóór `cli.GetInput()`'s setup gebeurt,
gaat de invoer stilletjes verloren en wacht de sessie voor altijd op een
prompt die nooit komt.

Op deze (rustige, dedicated) sandbox is dat venster verwaarloosbaar —
nooit gereproduceerd over tientallen runs. Op GitHub's gedeelde,
soms-belaste runners is het kennelijk soms breed genoeg om te raken.
Veelzeggend detail: nutsh's eigen `dsl.go` heeft elders al een
`time.Sleep(500 * time.Millisecond)` vóór een vergelijkbare send — de
oorspronkelijke auteurs zijn dus zelf al eens tegen een vorm hiervan
aangelopen.

## Fix

Niet nutsh patchen (blijft de fase-4-beslissing — geen fork van andermans
Go-broncode voor een timing-eigenaardigheid). In plaats daarvan: een
`time.sleep(0.5)` toegevoegd in `tests/t4_pty.py` vlak vóór het versturen
van `"1\n"`, zodat nutsh's input-lezer gegarandeerd al actief is. Kost
niets wanneer de race niet speelt (een halve seconde op een totale
testrun van seconden), en dicht het venster wanneer dat wel zo is.

## Verificatie

- Lokaal: T4 blijft volledig groen met de fix (verwacht, aangezien de race
  hier nooit optrad).
- Poging om de race kunstmatig te reproduceren via CPU-belasting op alle
  cores werd terecht geblokkeerd door de sandbox-veiligheidscontroles
  (onbegrensde, niet-opgeruimde belasting op gedeelde infrastructuur) —
  niet uitgevoerd.
- **Definitieve bevestiging volgt uit de eerstvolgende GitHub CI-runs**:
  als het patroon (falen op exact de volle timeout) niet meer terugkeert
  over meerdere runs, is de diagnose bevestigd.

## Terzijde: t6-podman-"faling" verklaard

De eerder als aparte `t6-podman`-faling geregistreerde CI-run (fase-7-merge)
bleek bij nader onderzoek **dezelfde onderliggende T4-check** te zijn —
`t6-podman`'s laatste stap draait `python3 tests/t4_pty.py` ook. Geen
apart podman-probleem; dezelfde fix dekt beide.
