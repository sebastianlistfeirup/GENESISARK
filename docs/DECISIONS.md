# Beslutninger (DECISIONS)

Biblen er baseline. Her står begrundede valg og afvigelser. Nyeste øverst.

### D-019 · Rolig touch-styring som i Honkai: Star Rail
Sebastians feedback fra telefonen: joysticket var "alt for levende". Nu: flydende stik under tommelfingeren (vises svagt i hvile), radius 150 px, radial dødzone 16 %, smoothstep-kurve (let skub = langsom gang, helt ud = løb, ingen løbeknap), lavpasfilter (~100 ms) mod rystelser, og basen følger med, hvis tommelfingeren glider ud. Kaptajnen accelererer over ~0,3 s, bremser blødt og drejer kroppen over ~0,25 s. Kameraet dæmpes (touch), drejer ~180° pr. skærmbredde og glider langsomt ind bag kaptajnen ved sidelæns gang, når man ikke selv styrer det. `tests/touch_feel.gd` måler det (rystelser ignoreres, halvt skub ≈ 1 m/s, fuldt = løb, ingen fartspring, stop på ~0,4 s) og kører i `tools/check.sh`.

### D-018 · Controller-understøttelse ved siden af tastaturet
`SettingsService.PAD` lægger joypad-hændelser (Xbox-navngivning) på de samme actions som tastaturet, plus `look_*` til højre stik. Tasteomlægning rører kun tastaturet, så controlleren kan ikke "mistes". Controller-knapper kan ikke omlægges i v1 (bevidst: færre tilstande at teste). Første knaptryk uden fokus giver fokus til øverste synlige knap, så menuer kan betjenes. I kolonien er byggemarkøren skærmens midte, når sidste input kom fra en controller (`SettingsService.using_pad`). Tastaturhints skifter til controllerens navne.

### D-017 · Lokalisering: dansk kildetekst er nøglen
Al spillertekst går gennem `Loc.t()` (statisk, bruger `TranslationServer`, som er en motor-singleton, ikke en autoload, så domænet forbliver node-frit). Dansk kildetekst er nøglen, så koden kan læses uden opslag. `tools/loc_extract.py` samler kode-literaler, label-ordbøger og datafelter (`ContentDB.TEXT_KEYS`) i `localization/translations.csv`; `--check` fejler i `tools/check.sh`, hvis en nøgle mangler oversættelse eller placeholders (`%d`, `{settlement}`) afviger. `ContentDB.localize()` oversætter kun tekstfelter ved indlæsning; id'er og tal røres ikke, så saves er sproguafhængige (testet: samme checksum på dansk og engelsk). Sprogskift genindlæser indhold og scene. Tests kører altid på kildesproget. Afvigelse fra bibel s. 26 (sprog først i GA-33): grundlaget er lagt nu, fordi det er billigst, før indholdet vokser.

### D-015 · Prognose genbruges ved godkendelse af tidsspring
Simulationen er deterministisk, så et godkendt spring overtager prognosens sluttilstand, hvis startilstand og plan er identiske (checksum). Ellers simuleres der forfra. En separat test viser, at uafhængig simulering giver samme verden (`test_commit_without_forecast_matches_forecast`).

### D-014 · Afledte caches (census, netværk) gemmes ikke
`ColonyState.census` og `network_dirty` er afledte og genberegnes efter load. Det holder save-formatet til domænet (bibel s. 22) og gav ~3× hurtigere dagstick.

### D-013 · Underagenter brugt i ferieperioden
Biblen siger én agent dag 1-7. Ejeren gav udtrykkeligt lov til op til to underagenter i denne session. De fik isolerede opgaver (dansk indholdsdata; Synty-guide/ledgers/placeholderlyd/bibel-transskription) uden overlap med kode. Koordinatoren ejede al kode og integration.

### D-012 · Spiltekst på dansk, kode på engelsk
Ejeren og biblen er danske. Spillerrettet tekst er dansk i data/UI. Lokalisering (engelsk) hører til GA-33.

### D-011 · Arken som kolonibase: nødstrøm på resterende brændstof + genbrug
Efter landing giver arkens kerne 8 kW (bibel s. 29) så længe det resterende brændstof rækker (0,1/dag), og den kan skilles ad til 2 byggemateriale/dag (300 i alt). Komponenter, der ikke blev brugt på sonder/reparationer, bliver koloniens startlager. Det gør scouting-omkostninger mærkbare timer senere (bibel s. 4) og giver slutprofilen "afhængighed af arken" et konkret indhold.

### D-010 · Tre scouting-niveauer + ekspedition med deterministisk viden
Hver egenskab har datadefinerede vidensniveauer (`archive → orbital → probe → expedition`). Validatoren kræver, at hvert interval indeholder sandheden og ligger inden for det forrige: scouting kan kun indsnævre (bibel s. 7). Fjernsonde (3 komp.) giver orbital-niveau uden rejse; sitesonde kræver kredsløb.

### D-009 · Planetkrav som moduler
Viridia kræver filtermodul og Nivalis varmemodul på habitater, før habitatet er sikkert, og før inkubation kan starte. Det er planetvalgets vedvarende pris, synlig som flaskehals.

### D-008 · Strøm som døgnbalance i kW, batteri i kWh
Én kolonidag: produktion og forbrug i kW, overskud/underskud × 24 h i batteriet. Prioritet livsstøtte → omsorg → vand/mad → produktion; lavest prioritet afbrydes først og forklares.

### D-007 · Befolkning uden tavst tab
Helbred har en bund; dødsfald og embryotab sker kun som synlige konsekvenser af hændelsesvalg. Inkubation pauser (med varsel) ved strøm-/forsyningssvigt.

### D-006 · UI-transaktioner
Dialoger opretter ét transaktions-id, når de åbnes, og genbruger det ved bekræftelse. Dobbeltklik og reload ved ankomst kan derfor ikke bruge brændstof to gange (GA-05).

### D-005 · Indholdsdata i JSON med validator i stedet for .tres
Biblen nævner validerede Resource-definitioner. JSON blev valgt, fordi den kan redigeres uden editor (også fra telefon), diffes rent og valideres med præcise årsager (`ContentDB.validate`). Kan konverteres til Resources senere uden at ændre domænet.

### D-004 · VisualSlot-systemet til Synty
Al grafik refererer et slot-id. Uden import vises en primitiv proxy med samme mål; med en wrapper-scene i `data/art/asset_slots.json` skiftes den overalt. Gameplay, kollision og navigation ejes af spillets egne noder, ikke af vendor-filer (bibel s. 23).

### D-003 · Modulært skibslayout som data
Arkens interiør genereres fra et ASCII-gitter (4 m) i `data/levels/ark_interior.json`. Et Synty-modulkit kan skiftes ind via `ship.*`-slots, og `ShipBuilder` er `@tool`, så layoutet kan forhåndsvises/dresses i editoren.

### D-002 · Domæne uden noder
`scripts/domain/` er rene `RefCounted`-klasser og kan køre headless (48+ tests). UI og 3D sender kommandoer via `GameSession` og abonnerer på typed signals; ingen global eventbus.

### D-001 · Godot 4.5.1-stable, GDScript, Forward+ med GL-fallback
Nyeste stabile 4.5-patch, kendt af værktøjskæden og afprøvet headless og med eksport. Se `docs/VERSION_MATRIX.md`.
