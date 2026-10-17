# Samleguide: fra greybox til Synty-scener

Spillet er **fuldt spilbart i greybox**. Hver visuel ting er et *slot* med en primitiv proxy i præcis den størrelse, gameplay forventer. Din opgave ved hjemkomst er at erstatte proxies med Synty-modeller — ikke at bygge spillet om. Følg `docs/SYNTY_INTEGRATION.md` for selve importen (FBX → wrapper → slot). Denne guide siger **hvad** der skal samles **hvor**.

## Tre måder at sætte grafik ind

| Metode | Hvornår | Hvordan |
|---|---|---|
| **1. Map et slot** (anbefalet) | Alt, der gentages eller har gameplay: vægge, gulve, terminaler, bygninger, figurer, sample-markører | Lav `art/prefabs/<slot>.tscn` og skriv stien i `data/art/asset_slots.json` → `"scene"`. Skiftet sker overalt. |
| **2. Dressing-noder** | Unikke pynte-props i arken (kabler, skilte, rod, lys) | Åbn `scenes/ship/ship.tscn`, markér `ShipBuilder` og sæt flueben i **Build Now** for at se layoutet i editoren. Læg props under noden `Dressing`. Gem. |
| **3. Site-dressing** | Landskabsprops ved et bestemt landingssite (klipper, vegetation, vragrester, landmærker) | Åbn `scenes/biomes/dressing_<site>.tscn` (9 filer). Koordinater er site-lokale (landingszonens centrum ≈ 0,0). `y = 0` betyder "på terrænet" — props snappes automatisk ned på jorden. |

Kør scenen direkte med **F6**: `surface.tscn` og `colony.tscn` har feltet `preview_setup` (fx `colony:nivalis`, `grown:umbra`, `expedition:ferrum`), så du kan se et site uden at spille dertil.

Gameplayregler, du ikke må bryde (bibel s. 9, 23): footprint og størrelse skal svare til proxyen; pynt må ikke blokere stier, døre, landingspladser eller interaktionspunkter; dekorative sten får ikke navmesh-betydning; funktionelle ting skal kunne skelnes fra pynt.

---

## Scene 1 — Arken (det aldrende rumskib)

Fil: `scenes/ship/ship.tscn` · Layout: `data/levels/ark_interior.json` (4 m gitter) · Pakker: **Sci-Fi Space Pack** (modulært interiør), **Sci-Fi Worlds** (props), **Sidekick** (robot), **Particle FX** (gnister/damp).

| Rum | Funktion i spillet | Slots at mappe | Stemning (bibel s. 13) |
|---|---|---|---|
| Kryorummet (start) | Kaptajnen vågner | `ship.cryo_pod`, `ship.floor`, `ship.wall` | Mørkt, rødt nødlys, frost, ensomhed |
| Ringkorridoren | Fysisk loop mellem alle rum | `ship.floor`, `ship.wall`, `ship.ceiling_light`, `ship.pipe`, `ship.door` | Gule servicelys viser vejen før strøm |
| Værkstedet | Nødstrømskobling (første mål), reparationer | `ship.power_coupling`, `ship.workbench`, `ship.robot_station`, `char.robot_worker`, `ship.crate` | Varm rav, værktøj, robotter |
| Embryobanken | 50.000 — lagerstatus | `ship.embryo_bank_core`, `ship.embryo_tank` (24 stk.) | Kølig petrol, stille, hellig |
| Broen | Stjernekort, sammenligning, kredsløb | `ship.starmap_table`, `ship.terminal_bridge`, `ship.captain_chair`, `ship.wall_window`, `ship.window_space`, `char.ark_ai_hologram` | Udsigt til stjerner/planet |

Tips: Synty-modulvægge har ofte et andet gitter end 4 m. Sæt `cell_size` i `ark_interior.json` til kittets mål (fx 5) — hele skibet skalerer med, og markører følger cellerne. Brug `rotation_y`/`offset` i slottet, hvis væggens forside vender forkert.

## Scene 2 — Rummet: stjernekort og indflyvning

Filer: `scenes/flight/flight.tscn`, `scenes/menu/main_menu.tscn` · Pakker: **Sci-Fi Space Pack**, **Sci-Fi Worlds** (planeter), **Particle FX** (thruster).

Slots: `space.ark_exterior` (arken set udefra — vigtigste hero-asset!), `space.planet_green/desert/ice` (tones automatisk med planetens farve), `space.asteroid`, `space.approach_ring`, `fx.thruster`. Stjernekortet er 2D-UI (se Scene 6).

## Scene 3 — Tre planetoverflader (ekspeditioner)

Fil: `scenes/surface/surface.tscn` · Terræn: genereret pr. biome (`data/sites/*.json` → `map`) · Pakker: **Sci-Fi Worlds** (biome-props, landere), **Sci-Fi Outpost Map** (relæ, beacons), **Particle FX** (sporer, støv, sne, damp).

| Biome | Planeter | Slots | Fare-FX |
|---|---|---|---|
| Grøn | Viridia, Pelagos | `surface.tree_green`, `surface.plant_green`, `surface.rock_*` | `fx.spores` (sporer), `fx.storm` |
| Ørken | Ferrum, Sere | `surface.desert_rock`, `surface.rock_*` | `fx.dust` |
| Is | Nivalis, Umbra | `surface.ice_spire`, `surface.crystal_ice`, `surface.rock_*` | `fx.snow`, `fx.steam_vent` |

Fælles: `surface.lander`, `surface.sample_marker`, `surface.relay_beacon`, `surface.hazard_marker`. Ruter (sikker = petrol, kort = rav) og fareområder er data i `data/surveys/<planet>.json`.

## Scene 4 — Kolonien (opbygning af den nye civilisation)

Fil: `scenes/colony/colony.tscn` · Pakker: **Sci-Fi Outpost Map** (base, moduler), **Sci-Fi Worlds** (habitater, drivhuse), **Sci-Fi City** + **Cyber City** (senere vækst ved år 20-40), **Sidekick** (borgere, robotter), **Particle FX** (byggegnister, strømstød).

| Bygning | Slot | Footprint (m) | Pakke-forslag |
|---|---|---|---|
| Arkens kerne | `building.ark_core` | 14 × 10 | Space Pack (landet skib) |
| Solpanelfelt | `building.solar_array` | 6 × 6 | Outpost Map |
| Geotermisk generator | `building.geothermal_generator` | 6 × 6 | Outpost Map / Worlds |
| Batteribank | `building.battery` | 4 × 4 | Outpost Map |
| Vandanlæg | `building.water_plant` | 6 × 8 | Outpost Map |
| Væksthus | `building.greenhouse` | 8 × 6 | Worlds |
| Mine | `building.mine` | 8 × 8 | Outpost Map |
| Værksted | `building.workshop` | 8 × 6 | Outpost Map |
| Dronehub | `building.drone_hub` | 6 × 6 | Outpost Map |
| Habitat | `building.habitat` | 10 × 8 | Worlds / City |
| Omsorgs- og inkubationscenter | `building.care_center` | 10 × 10 | City (varm, lys) |
| Klinik | `building.clinic` | 8 × 6 | City |
| Skole og rådhus | `building.school_hall` | 10 × 8 | City |
| Moduler | `building.module_filter`, `building.module_heater` | ~1,6 × 1,6 | Outpost Map |
| Byggestillads | `building.construction_frame` | stolpe | Outpost Map |

Figurer: `char.citizen_adult`, `char.citizen_child` (højst ~40 synlige; de illustrerer kohorter), `char.robot_worker`, `char.robot_drone`.

## Scene 5 — Epilog

Fil: `scenes/story/ending.tscn`. 2D i dag. Senere: et kamera over den voksne koloni (bibel s. 16: "lys i koloniens første beboede habitat"), fx en fast kameraposition i `colony.tscn`.

## Scene 6 — UI og HUD

Temaet bygges i `scripts/ui/ui_kit.gd` (farver, knapper, paneler). **INTERFACE – Sci-Fi Menus** og **Sci-Fi Soldier HUD** leverer typisk PNG-sprites: erstat `StyleBoxFlat` i `UiKit.theme()` med `StyleBoxTexture` (9-slice) for paneler/knapper, og brug ikonerne til `ui.icon_*` i ressourcelinjen. Behold tekst + ikon + farve sammen (tilgængelighed, bibel s. 26).

## Rækkefølge ved hjemkomst (GA-13)

1. Importér **ét** skibsmodul (væg + gulv), **én** humanoid (kaptajn) og **én** terrænprøve (én sten).
2. Map dem, kør `tools/check.sh`, tag screenshots med gameplaykameraet og sammenlign med greybox.
3. Udfyld `docs/ASSET_LEDGER.csv` (kilde, checksum, skala, review_status).
4. Derefter bred udskiftning scene for scene i rækkefølgen ovenfor.

## Figurer og animation (GA-13/14)

Når `char.captain` peger på en wrapper med en `AnimationPlayer` (fx en Sidekick-figur med retargetede klip), afspiller `CharacterAnimator` automatisk `idle`, `walk`, `run` og `sample` (hold-E prøvetagning). Klipnavnene står i `data/art/animation_map.json` — omdøb dem dér, ikke i koden. Bevægelse er *in-place*: controlleren flytter figuren, og afspilningshastigheden skaleres til den faktiske fart (`speed_ref`), så fødderne ikke glider (bibel s. 24). Udfyld `docs/ANIMATION_LEDGER.csv` og godkend først efter billed-/videokontrol (bibel s. 25).
