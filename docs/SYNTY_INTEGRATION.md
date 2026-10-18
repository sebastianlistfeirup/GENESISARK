# Synty-integration — fra købt pakke til færdigt spil-asset

*GENESIS ARK · Godot 4.5.1 · gælder biblen s. 19, 21, 23-25 og 48*

Denne guide er skrevet til dig som ejer. Du behøver ikke kunne programmere. Læs den gerne på telefonen nu, og følg trinnene ved computeren senere.

> **Ærlighedsnote:** Pakkerne ligger ikke i repositoryet, og ingen har åbnet dem endnu. Det, der står om **filnavne, mapper, skala og indhold i pakkerne**, er typiske Synty-konventioner og ikke kontrolleret mod dine filer. Alt, der er mærket **(skal verificeres ved import)**, skal du (eller agenten) tjekke første gang, filen åbnes i Godot.

---

## 0. Det korte overblik

1. **Køb** pakken (gjort) → 2. **Download** (FBX/"Source"-versionen) → 3. Pak ud i **karantænemappen** `assets/quarantine/` (kommer aldrig i git) → 4. **Kopiér kun de filer, du bruger**, til `assets/imported/<pakke>/` → 5. **Importér** i Godot (FBX direkte, eller via Blender → GLB) → 6. **Materiale**: sæt pakkens atlas-tekstur på → 7. **Kontrollér** skala, retning (facing), pivot → 8. Lav en **wrapper-scene** `art/prefabs/<slot>.tscn` med collision → 9. **Map slot-id** i `data/art/asset_slots.json` → 10. Udfyld **`docs/ASSET_LEDGER.csv`**.

Spillet viser en grå "proxy"-figur for hvert visuelt slot, indtil du mapper slot-id'et til en rigtig scene. Du kan altså skifte ét asset ad gangen, og spillets regler ændres ikke.

---

## Hurtig vej: automatisk import (anbefalet)

Værktøjerne i `tools/synty/` gør trin 3-9 nedenfor for dig. Kræver Python 3 og Godot 4.5.1 (eller bed agenten køre dem).

```bash
# 1. Pak hver købt pakke ud i karantæne (Unity-pakke, zip eller mappe; kommer aldrig i git)
python3 tools/synty/unpack.py "D:/SyntyArkiv/POLYGON_SciFi_Space.unitypackage"
python3 tools/synty/unpack.py "D:/SyntyArkiv/POLYGON_SciFi_Worlds_SourceFiles.zip"
# 2. Foreslå en model pr. slot ud fra navnemønstre -> data/art/synty_choices.json
python3 tools/synty/match.py
# 3. Kig listen igennem: ret "source", sæt "status": "approved" (lås), "skip" (behold proxy).
#    "weak" bygges først, når du har godkendt den. "rotation_y": 180 vender en model.
# 4. Byg: kopierer kun de valgte filer ind, importerer, sætter pakkens atlas-materiale
#    i importindstillingerne, laver wrapper-scener og mapper slottene.
tools/synty/build.sh
# 5. Start spillet (F5). Rapport: evidence/synty_build.json. Figurer: scenes/tests/RigLab.tscn.
```

Hvad byggeren gør med størrelse og placering:

| Slot-type | Tilpasning |
|---|---|
| Skibsmoduler (`ship.floor/wall/door/pillar/pipe/window…`) | Skaleres ensartet, så de passer præcist i 4 m-gitteret |
| Kolonibygninger (`building.*`) | Skaleres ned/op til at stå inden for spillets fodaftryk, centreret, bund på jorden |
| Rum (`space.*`) | Skaleres til proxyens største mål |
| Figurer, rekvisitter, sten, køretøjer | Ægte størrelse; kun cm→m-fejl rettes (×0,01). Advarsel, hvis højden er under 50 % eller over 200 % af proxyen |

Alt kan overstyres pr. slot i `synty_choices.json`: `"fit"`, `"extra_scale"`, `"rotation_y"`. Slots, der optræder mange gange (sten, træer, planter, is, kasser, rør, borgere, asteroider), får op til seks varianter af samme familie (`"variants"`); spillet vælger én pr. placering, altid den samme på samme sted. Particle FX er Unity-partikelsystemer og bygges i Godot med pakkens teksturer (status `manual`). Kollision ejes altid af spillets egne noder, aldrig af wrapperen.

**I Godot-editoren:** fanen **Asset-slots** (ved siden af Inspector) viser alle 81 slots, om de stadig er proxy, Synty-forslaget og matcherens valg. Markér en model i FileSystem-panelet og tryk **Brug valgt fil**, eller tryk på et af alternativerne. "Drej model" retter facing; **Åbn wrapper** og **RigLab** åbner scenerne.

Afprøv selve værktøjskæden uden købte filer: `tools/synty/selftest.sh` (falsk pakke → hele kæden → kontrol → oprydning).

---

## 1. Download — hvilken version?

Synty sælger hver pakke med flere downloads (fx Unity-pakke, Unreal, "Source Files"/FBX). **(skal verificeres ved import — se Synty FAQ, biblen R7)**

| Download | Brug i Godot? |
|---|---|
| **Source / FBX-mappe** (FBX-filer + `Textures/`-mappe) | **Ja — førstevalg.** Godot 4.5 kan selv åbne FBX. |
| Unity `.unitypackage` | Kun indirekte: kræver Unity for at pakke ud. Bruges til **Sidekick** (se afsnit 9) og hvis en pakke kun findes som Unity. |
| Unreal | Nej. |

Gem den originale zip et sikkert sted uden for repositoryet (fx `D:\SyntyArkiv\`). Biblen s. 23: *"Udgiv ikke rå købte pakker i en offentlig startpakke eller et offentligt repository."*

---

## 2. Karantænemappen `assets/quarantine/`

- Pak hele pakken ud i `assets/quarantine/<PakkeNavn>/`.
- Mappen er sat i `.gitignore` (sammen med `assets/synty_raw/` og `*.unitypackage`), så den **aldrig** bliver committet.
- Godot vil importere alt i projektmappen. For at undgå tusindvis af importer: læg en tom fil ved navn **`.gdignore`** i `assets/quarantine/`. Så springer Godot mappen over.
- Når du har valgt et asset: **kopiér** FBX-filen og den tilhørende tekstur til `assets/imported/<pakke>/` (fx `assets/imported/scifi_space/SM_Prop_Console_01.fbx` og `assets/imported/scifi_space/Textures/…png`). Rør aldrig vendorfilen derefter — den er "read-only" (biblen s. 23).
- Beregn checksum (bruges i ledgeren):
  - Windows PowerShell: `Get-FileHash .\fil.fbx -Algorithm SHA256`
  - macOS/Linux: `shasum -a 256 fil.fbx`

> **Licens:** Vi går ud fra, at de importerede filer må ligge i et **privat** repository til udvikling. Hvis repositoryet nogensinde bliver offentligt, skal `assets/imported/` fjernes eller gøres privat først. **(skal verificeres i Syntys licens)**

---

## 3. Import i Godot

### 3a. Direkte FBX (anbefalet start)

Godot 4.3+ har indbygget FBX-import (biblioteket *ufbx*); du behøver **ikke** FBX2glTF eller Blender. I Godot 4.5.1:

1. Når FBX-filen ligger i `assets/imported/…`, importeres den automatisk.
2. Dobbeltklik på filen → **Advanced Import Settings**.
3. Tjek at figuren ser rigtig ud, har den rigtige størrelse og ikke ligger ned (se afsnit 5).

### 3b. Alternativ: Blender → GLB

Brug kun hvis FBX-importen giver problemer (forkert akse, manglende knogler, mærkelige normaler):

1. Blender: *File → Import → FBX*.
2. Ret evt. rotation/skala, *Apply → All Transforms*.
3. *File → Export → glTF 2.0 (.glb)*, vælg "+Y Up".
4. Læg `.glb` i `assets/imported/…`. Notér i ledgeren, at filen er bearbejdet (biblen s. 28: aflevér originalreference, bearbejdet fil, GLB og importtest).

---

## 4. Materialer og tekstur (atlasset)

Synty POLYGON bruger normalt **én fælles farve-tekstur (et "atlas") pr. pakke**, fx noget i stil med `PolygonSciFi_Texture_01.png` eller `PolygonSciFiSpace_Texture_01_A.png`. Hver model "peger" bare på små farvefelter i atlasset. **(navnet skal verificeres ved import)**

- **Godot finder ofte atlasset selv**, hvis mappen `Textures/` ligger ved siden af FBX-filen med samme relative sti som i pakken.
- Hvis modellen er **hvid/grå/lyserød**, er teksturen ikke fundet. Gør sådan:
  1. Opret ét fælles materiale pr. pakke: højreklik i `art/materials/` → *New Resource → StandardMaterial3D* → gem som `mat_scifi_space_atlas.tres`.
  2. Sæt **Albedo → Texture** = pakkens atlas-PNG.
  3. **Roughness** ca. 0,7-0,9 og **Metallic** 0 til at starte med (Synty er "flad" stil). Justér senere, så metal ser ens ud på tværs af pakker (biblen s. 23: *én palet og én lysgrammatik*).
  4. I *Advanced Import Settings* → fanen **Materials** → vælg materialet → **Use External** → peg på din `.tres`. Nu bruger alle modeller fra pakken samme materiale (godt for ydelse).
- **Triplanar er IKKE nødvendigt.** Synty-modeller har allerede UV'er, der passer til atlasset. Triplanar ville tværtimod ødelægge farvefelterne.
- Glas/vinduer og emissive (lysende) dele har ofte et særskilt materiale eller ekstra tekstur (fx `_Emissive`). Lav et separat materiale med *Transparency: Alpha* til glas og *Emission* til lys. **(skal verificeres ved import)**
- Teksturimport: sæt *Filter* til Linear og lad *Mipmaps* være slået til for 3D-atlasser. UI-PNG'er: mipmaps fra.

---

## 5. Kontrol: skala, retning, pivot

### Skala (1 m-reference)

Synty-modeller er lavet til Unity, hvor **1 enhed = 1 meter**. Godot bruger også 1 enhed = 1 meter. **(skal verificeres ved import: nogle FBX'er eksporteres i cm og bliver 100× for store/små)**

Sådan tjekker du:
1. Åbn testscenen (eller en tom 3D-scene) og tilføj en `MeshInstance3D` med en **BoxMesh på 1×1×1 m** og en **CapsuleMesh på 1,8 m** (= en voksen).
2. Træk modellen ind ved siden af.
3. En dør skal være ca. 2-2,5 m høj, en kaptajn ca. 1,8 m, en kasse 0,5-1 m.
4. Er den 100× forkert: *Advanced Import Settings → Scene root → Root Scale* (fx 0,01 eller 100). Notér værdien i ledgerens `scale_m`.

### Retning (facing: +Z eller -Z)

- I **Godot** peger "fremad" mod **-Z**. I **Unity** peger "fremad" mod **+Z**.
- Synty-figurer og -køretøjer vender typisk mod +Z (Unity-standard) og vil derfor **vende baglæns** i Godot. **(skal verificeres ved import)**
- Ret det **ét sted**: i wrapper-scenens `VisualPivot`-node (drej 180° om Y). Ret ikke i koden eller i vendorfilen (biblen s. 24).

### Pivot (omdrejningspunkt)

- Bygninger og props: pivot skal være **i bunden** (så de står på jorden). Modulære vægge/gulve har ofte pivot i et hjørne. Notér det.
- Figurer: pivot mellem fødderne.
- Forkert pivot rettes ved at flytte modellen i forhold til wrapperens rod — ikke ved at ændre vendorfilen.

---

## 6. Collision (kollision)

Biblen s. 23: *"Miljøprops får simple collision proxies; små pynteting får ofte ingen."*

| Type | Collision |
|---|---|
| Vægge, gulve, store bygninger | `StaticBody3D` + `BoxShape3D` (en eller flere bokse). |
| Uregelmæssige store sten/klipper | `ConvexPolygonShape3D` (Godot: *Mesh → Create Collision Shape → Simplified Convex*). |
| Små sten, planter, rør, lamper | **Ingen**. |
| Figurer | Kapsel i controlleren — **ikke** i den visuelle model. |
| Døre | Collision på dørbladet; slås fra når døren er åben. |

Brug aldrig "Trimesh" collision på hele detaljerede modeller — det er langsomt og giver fastlåsning.

---

## 7. Wrapper-scene `art/prefabs/<slot>.tscn`

En wrapper er din egen lille scene, som "pakker" vendor-modellen ind. Spillet bruger kun wrapperen.

Eksempel for `ship.terminal` → fil `art/prefabs/ship.terminal.tscn`:

```
ship_terminal (Node3D)               <- rod, står på (0,0,0) = gulvniveau
└── VisualPivot (Node3D)             <- drej 180° her hvis den vender forkert
    └── SM_Prop_Console_XX (instans af den importerede FBX)
```

Regler (gælder for dette projekts VisualSlot-system):
- **Kun visuelt indhold.** Spillet ejer allerede kollision, interaktion og navigation for alle slots: skibets vægge/gulve/døre (`ShipBuilder`), interaktive objekter (`Interactable`), bygninger (pick-kollider pr. footprint), kaptajnen (kapsel) og terrænet. Læg derfor **ingen** StaticBody/CollisionShape i wrappere for `ship.*`, `building.*`, `char.*`, `surface.lander`, `surface.sample_marker`, `surface.relay_beacon`. Rene pynte-props, du selv placerer i scenen (se `docs/SCENE_ASSEMBLY.md`), må få en simpel kollisionsproxy.
- Samme **footprint og størrelse som proxyen** (bibel s. 9 og 19), så gameplay ikke ændrer sig. Proxyens mål står i `data/art/asset_slots.json` (`proxy`-listen) og bygningernes footprint i `data/buildings/buildings.json`.
- Ingen scripts fra Unity/vendor. Ingen gameplaylogik i wrapperen.
- Filnavn = slot-id + `.tscn` (fx `art/prefabs/building.habitat.tscn`).

---

## 8. Map slot-id og udfyld ledger

### 8a. `data/art/asset_slots.json`

Find slot-id'et og udfyld `scene` (stien til din wrapper). `scale`, `offset` og `rotation_y` (grader) finjusterer den importerede model uden at røre proxyen:

```json
"ship.terminal": {
  "scene": "res://art/prefabs/ship.terminal.tscn",
  "scale": 1.0,
  "offset": [0, 0, 0],
  "rotation_y": 0,
  "proxy": [ ...lad stå... ]
}
```

Start spillet: proxyen er nu skiftet ud **overalt**, hvor slotet bruges (fx alle vægge i arken). Er stien forkert eller filen væk, viser spillet stadig proxyen (ingen crash). Kører du `python3 tools/gen_asset_slots.py` igen, bevares dine `scene`/`scale`/`offset`/`rotation_y`.

Hjælp til at finde assets: `data/art/synty_suggestions.json` foreslår pakke og navnemønstre for hvert slot.

### 8b. `docs/ASSET_LEDGER.csv`

Én række pr. slot er allerede oprettet. Når du har importeret:

| Kolonne | Udfyld med |
|---|---|
| `source_pack` | Den pakke, filen faktisk kom fra |
| `source_path` | Sti inde i pakken, fx `Source_Files/FBX/SM_Prop_Console_01.fbx` |
| `checksum` | SHA-256 af vendorfilen (afsnit 2) |
| `format` | FBX eller GLB |
| `rig_id` | Kun figurer: fx `humanoid_main` |
| `scale_m` | Målt højde i meter, fx `1.80` |
| `materials` | Hvilken `.tres` der bruges |
| `license_status` | `purchased_unverified` → `purchased_verified` når licensen er tjekket |
| `review_status` | `PROXY` → `IMPORTED` → `APPROVED` (efter screenshot ved gameplaykamera) |

Biblen s. 23 kræver importbevis: **source hash, screenshot ved gameplaykamera, mål/skala, collisiontest og materialekontrol.**

---

## 9. Figurer: Sidekick, rig og animation

### Sidekick-figurer (robotter, evt. mennesker)

*Sci-Fi Robots – Sidekick Modular Characters* er bygget til **Syntys Sidekick-værktøj, som kører i Unity**. Man sætter en figur sammen af dele (hoved, torso, arme …) i Unity. Godot kan ikke køre Sidekick-værktøjet. **(skal verificeres ved import: om pakken også har færdige FBX-figurer i "Source"-download)**

Praktisk vej til Godot:
1. Installér gratis **Unity** (version som Sidekick kræver) og importér pakken + Sidekick-værktøjet.
2. Saml de figurer, spillet skal bruge: `robot_worker` (og evt. AI-hologram).
3. Eksportér den samlede figur som **FBX** — enten via Sidekicks egen eksport (hvis den findes i din version) eller via Unitys gratis **FBX Exporter**-pakke (*GameObject → Export To FBX*, slå "Include Animation" fra for selve figuren).
4. Læg FBX i `assets/imported/sidekick/` og følg afsnit 3-8.
5. **Retarget** i Godot (biblen s. 24, R2): *Advanced Import Settings → Skeleton3D → Retarget → Bone Map* → vælg **SkeletonProfileHumanoid**. Godot gætter de fleste knogler; ret resten manuelt. Kontrollér at rest-posen (T/A-pose) og knoglernes akser stemmer — ens navne er ikke nok.
6. Alle figurer, der skal dele animationer (kaptajn, borgere), skal bruge **samme** humanoid-rig `humanoid_main`. Ikke-humanoide robotter/droner får egne rigs (biblen s. 24).

> **Mennesker:** Robotpakken indeholder sandsynligvis kun robotter. Kaptajn og borgere skal derfor nok komme fra karakterer i Sci-Fi Worlds / Sci-Fi City / Cyber City-pakkerne eller en Sidekick-menneskepakke. **Børnefigurer findes muligvis slet ikke** i de købte pakker. **(skal verificeres ved import)**

### Animation (biblen s. 24-25)

- **In-place:** alle gang/løb-animationer skal stå stille på stedet; koden flytter figuren. Ved import: *Animation → Root Motion* slås fra, eller vælg in-place-varianten.
- Synty-animationer er førstevalg, Mixamo udfylder huller (tjek stil og vilkår).
- Behovslisten står i **`docs/ANIMATION_LEDGER.csv`** (kaptajn, robot, borger) med status `NEEDED`.
- Kontrol: fødder må ikke glide, ingen "pose-snap". Se i 0,25× og 1× hastighed.
- En animation bliver først `APPROVED` efter billede/video ved gameplaykamera.

---

## 10. Hvilken pakke til hvad?

| Pakke | Bruges til i GENESIS ARK | Fase |
|---|---|---|
| **POLYGON – Sci-Fi Space Pack** | Arkens interiør (bro, embryobank, værksted), arken udefra, landingsfartøj, asteroider, evt. planeter | 1-2 |
| **POLYGON – Sci-Fi Worlds Pack** | Interiør-supplement, de tre biomer (grøn natur, ørkenklipper, is/krystaller), kolonimoduler, evt. karakterer | 2-3 |
| **POLYGON – Sci-Fi Outpost Map** | Kolonibygninger: solpaneler, generatorer, tanke, habitatmoduler, stillads, skilte, kasser | 2-3 |
| **POLYGON – Sci-Fi City Pack** | Klinik, skole/rådshus, civile figurer, større by-elementer | 3 |
| **POLYGON – Sci-Fi Cyber City** | Den "voksne by" ved **år 40** (senere stadie, fase 3) — ikke i starten | 3 |
| **Sci-Fi Robots – Sidekick** | Arbejdsrobotter, evt. AI-hologram-figur | 2 |
| **POLYGON – Particle FX Pack** | **Kun teksturer**: sporer, støv, sne, storm, damp, thruster, gnister, scan-puls. Effekterne er Unity-partikelsystemer og skal genopbygges som `GPUParticles3D` i Godot | 2 |
| **INTERFACE – Sci-Fi Menus** | Hovedmenu, paneler, knapper, planetsammenligning | 2 |
| **INTERFACE – Sci-Fi Soldier HUD** | HUD-ramme, ressourceikoner, sigtekorn til interaktion | 2 |

**UI-regel (biblen s. 23):** UI-pakker leverer grafik, ikke tre konkurrerende HUD-stilarter. Vælg én visuel stil og hold den. Unity-UI-prefabs virker ikke i Godot — brug PNG-grafikken i `NinePatchRect`/`StyleBoxTexture`.

**Søgemønstre** (typiske Synty-konventioner — **verificér** i dine filer):

| Mønster | Betyder typisk |
|---|---|
| `SM_Bld_*` | Bygninger og bygningsdele |
| `SM_Env_*` | Miljø: sten, træer, gulve, vægge, terræn |
| `SM_Prop_*` | Rekvisitter: konsoller, kasser, stole, lamper |
| `SM_Veh_*` | Køretøjer og skibe |
| `SK_Chr_*` / `SM_Chr_*` | Figurer (SK = skinned/med skelet) |
| `FX_*` | Effekter/effektteksturer |
| `*_Texture_01*` | Pakkens atlas-tekstur |

Se `data/art/synty_suggestions.json` for forslag pr. slot.

---

## 11. Samle-tjekliste pr. scene

Sæt kryds, når slotsene er mappet, og ledgeren er udfyldt. Udskift altid **ét område ad gangen**, og sammenlign med proxy-versionen (biblen GA-13).

### A. Arkens interiør

**Bro**
- [ ] `ship.floor`, `ship.wall`, `ship.wall_window`, `ship.pillar`, `ship.ceiling_light`
- [ ] `ship.terminal_bridge`, `ship.starmap_table`, `ship.captain_chair`, `ship.window_space`
- [ ] Kaptajn kan gå rundt uden at sidde fast; kamera går ikke gennem vægge
- [ ] Udsigtsvindue viser rum-baggrund

**Embryobank**
- [ ] `ship.embryo_tank` (mange — brug MultiMesh), `ship.embryo_bank_core`
- [ ] Tallet 50.000 er synligt og læsbart fra gameplaykameraet
- [ ] `ship.cryo_pod` (kaptajnens opvågning)

**Værksted**
- [ ] `ship.workbench`, `ship.robot_station`, `ship.power_coupling`, `ship.crate`, `ship.pipe`, `ship.terminal`
- [ ] `char.robot_worker` står ved station
- [ ] Nødstrøms-objektet skiller sig tydeligt ud fra pynt
- [ ] `ship.door` mellem rum åbner og lukker

### B. Rum: stjernekort og indflyvning
- [ ] `space.ark_exterior` vender rigtigt (fremad = flyveretning)
- [ ] `space.planet_green`, `space.planet_desert`, `space.planet_ice`
- [ ] `space.asteroid`, `space.approach_ring`
- [ ] `fx.thruster`, `fx.scan_pulse`
- [ ] Lyd: `amb_space`, `sfx_thruster`, `sfx_probe_launch`, `sfx_scan` (placeholder indtil videre)

### C. Tre biome-overflader (ekspedition)

**Grøn (Viridia / Pelagos)**
- [ ] `surface.tree_green`, `surface.plant_green`, `surface.rock_small`, `surface.rock_large`
- [ ] `fx.spores`, `fx.storm`

**Ørken (Ferrum / Sere)**
- [ ] `surface.desert_rock`, `surface.rock_small`, `surface.rock_large`
- [ ] `fx.dust`

**Is (Nivalis / Umbra)**
- [ ] `surface.crystal_ice`, `surface.ice_spire`
- [ ] `fx.snow`, `fx.steam_vent`

**Fælles for alle tre**
- [ ] `surface.lander`, `surface.sample_marker`, `surface.relay_beacon`, `surface.hazard_marker`, `fx.landing_dust`
- [ ] Faren er synlig uden lyd (biblen GA-18); farve er ikke eneste signal
- [ ] Ruter kan stadig gås; pynt blokerer ikke stier

### D. Kolonien
- [ ] `building.ark_core` (den landede ark)
- [ ] Fase 1-bygninger: `building.solar_array`, `building.water_plant`, `building.habitat`
- [ ] Øvrige: `building.geothermal_generator`, `building.battery`, `building.greenhouse`, `building.mine`, `building.workshop`, `building.drone_hub`, `building.care_center`, `building.clinic`, `building.school_hall`
- [ ] Moduler: `building.module_filter`, `building.module_heater`
- [ ] `building.construction_frame` + `fx.construction_sparks`, `fx.power_surge`
- [ ] `char.robot_drone`, `char.citizen_adult`, `char.citizen_child`
- [ ] Footprint i wrapper = footprint i data (placering og net virker uændret)
- [ ] År 40: overvej Cyber City-varianter af skole/habitat (senere)

### E. UI og HUD
- [ ] `ui.panel`, `ui.button`, `ui.hud_frame`, `ui.crosshair_interact`
- [ ] Ikoner: `ui.icon_power`, `ui.icon_water`, `ui.icon_food`, `ui.icon_alloy`, `ui.icon_components`, `ui.icon_embryo`, `ui.icon_population`, `ui.icon_fuel`, `ui.icon_integrity`
- [ ] Testet i 1280×720 og 1920×1080; tekst klippes ikke (biblen s. 26)

---

## 12. Hvis noget går galt

| Problem | Løsning |
|---|---|
| Modellen er hvid/lyserød | Teksturen er ikke fundet → afsnit 4 (Use External materiale). |
| Modellen er kæmpestor eller usynligt lille | Root Scale 0,01 eller 100 → afsnit 5. |
| Figuren vender baglæns | Drej `VisualPivot` 180° om Y. |
| Modellen ligger ned | FBX har Z-op-akse → prøv Blender → GLB (afsnit 3b). |
| Figur "glider" når den går | Animationen er ikke in-place, eller hastighed passer ikke → afsnit 9. |
| Spillet viser stadig grå proxy | Forkert sti i `asset_slots.json` eller wrapperen fejler at loade (se Godots output-log). |
| Godot importerer i flere minutter | Du har glemt `.gdignore` i `assets/quarantine/`. |

Behold altid proxy-versionen som rollback (biblen GA-13): fjern blot mappingen i `asset_slots.json`, så er proxyen tilbage.
