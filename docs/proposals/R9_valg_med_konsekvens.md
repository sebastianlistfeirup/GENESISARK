# Forslag R9 · Valg der ændrer udfaldet

*Status: forslag til Sebastian. Intet er implementeret. Biblen s. 11: "Valg påvirker tillid, robusthed og afhængighed af arken." "Ingen moralsk score alene afgør udfald; vis konkrete systemiske konsekvenser og de mennesker, der lever med dem."*

## Problemet i tal

Kampagnebotten spiller alle seks planeter med første, midterste og sidste valg i alle hændelser og ved år 20/40:

| Spillestil | Slutprofil | Befolkning år 40 |
|---|---|---|
| Første valg | selvstændig ×6 | 650 (Ferrum 560) |
| Midterste valg | selvstændig ×6 | 650 (Ferrum 560) |
| Sidste valg | selvstændig ×6 | 650 (Ferrum 560) |
| Sjusket (få bygninger, intet råd) | skrøbelig ×6 | 40-650 |

Valgene flytter `trust` og `autonomy`, men ingen regel læser dem. Befolkningen er låst af fødselsplanen (20 + 16/år). *Skærmet* nås aldrig ved normal spillestil. Kun epilogen afspejler nu valgene (D-031).

## Tre lag, hver for sig brugbart

### Lag 1 · Prioriteterne ved år 20 og 40 bliver varige (lille, anbefalet først)

Data i `data/balance/baseline.json` → `priorities`. Hver prioritet har en gevinst og en pris, så ingen er "den rigtige":

| Prioritet | Gevinst | Pris |
|---|---|---|
| Ekspansion | Distrikter vokser 20 % mere; fødselsplan +3/år | Slid +15 %; lagerloft −25 % (mindre buffer mod kriser) |
| Sikkerhed | Lagerloft +50 %; kriseeffekter −30 % | Byggeri 15 % langsommere; fødselsplan −2/år |
| Selvbestemmelse | Rådet kan dannes med 15 voksne (ikke 25); voksne arbejder 1/3 i stedet for 1/4 | Arkens nødstrøm aftrappes 2× hurtigere (mere selvstændig, hvis forberedt; ellers *skærmet*) |

Virkning: befolkning og arkafhængighed spreder sig mellem spillestile; *skærmet* bliver en realistisk slutning for selvbestemmelse uden egen strøm.

### Lag 2 · Tillid bliver en drejeknap (mellem)

| Tillid | Systemisk virkning | Vises som |
|---|---|---|
| < 35 | Voksnes arbejdsindsats −25 %; inkubation kræver 45 i stedet for 30 reservedage | HUD-ikon ▼ + linje i Fremtid-fanen ("Folk arbejder langsommere: de stoler ikke på planen") |
| 35-65 | Ingen | — |
| > 65 | Arbejdsindsats +10 %; kriser løses med −20 % omkostning | ikon ▲ |

Tilliden ændres i dag af hændelsesvalg (±1-5), mangel (−0,05/dag) og stabile perioder (+0,01/dag). Kort test: tre dårlige valg + en mangelperiode skal kunne bringe den under 35; en rolig kampagne med gode valg over 65.

### Lag 3 · Hændelser får efterspil (større)

Hver af de 9 hændelser får ét valg med forsinket virkning (`aftermath: {days, effects, text}`), fx "Billigt nu: lappe ventilationen" → efter 300 dage +slid og −tillid, med en kort scene. Det giver de tre navngivne unge noget at reagere på i akt II.

## Slutprofiler

`profile_for()` beholder sine systemiske krav (befolkning, råd, egen strøm, reserver), men *skærmet* defineres skarpere som "arkens nødstrøm dækker stadig > 15 % af behovet". Tillid indgår aldrig alene (biblen), kun via sine systemiske virkninger.

## Sådan måler vi, om det virker

Kør `godot --headless --path . --script res://tools/campaign/campaign_bot.gd`. Mål efter lag 1+2:

- De tre normale spillestile giver **mindst to forskellige slutprofiler** på tværs af planeterne.
- Befolkningen ved år 40 spreder sig **mindst 15 %** mellem spillestile på samme planet.
- Sjusket spil giver stadig *skrøbelig*; ingen spillestil går i stå (0 fejl i botten).
- `run_balance.gd`: Ferrum forbliver sværest; ingen planet dominerer alle felter.

## Omfang

| Lag | Filer | Skøn |
|---|---|---|
| 1 | `society_service.gd`, `colony_simulation.gd`, `population_service.gd`, `era_service.gd`, balance-data, 3 tests, UI-tekst ved valget | 3-5 timer |
| 2 | `population_service.gd`, `day_simulator.gd`, HUD-ikon, Fremtid-fanen, 2 tests | 3-4 timer |
| 3 | `data/events/*.json` (9 efterspil), `event_service.gd`, korte scener | 1-2 dage (mest skrivning) |

**Anbefaling:** lag 1 + 2 nu (én session), lag 3 efter første rigtige gennemspilning, når du ved, hvilke hændelser der føles flade.
