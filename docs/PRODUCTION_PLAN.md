# GENESIS ARK — Produktionsplan fra start til udgivelse

*Version 1 · 18.10.2026 · bygger på Udviklingsbibel v1 (`docs/BIBLE.md`). Biblen er stadig baseline; denne plan fordeler arbejdet på værktøjer, faser og uger. Tal for tid og pris er planlægningshypoteser, ikke løfter (bibel s. 17, 29).*

---

## 0. Spilleregler for hele produktionen

1. **Kernen virker uden cloud.** Intet i det færdige spil må kalde en ekstern AI-tjeneste under spillet (bibel s. 16, 28). AI-værktøjer leverer *filer* (lyd, billeder, tekstudkast), som importeres, gennemgås og låses i en indholdsversion.
2. **Ét værktøj pr. opgave, én godkender.** Koordinatoren (dig + kodeagenten) godkender hvert leveret asset mod en konkret acceptpøve. Én revision skal pege på én konkret mangel; ingen endeløs generering (bibel s. 28).
3. **Gameplay-beviser er altid ægte optagelser.** AI-genereret video bruges aldrig som bevis for gameplay og aldrig i en trailer, der foregiver at vise spillet (bibel s. 28, 46).
4. **Alt har en kilde og en licens.** Hvert asset står i en ledger: `docs/ASSET_LEDGER.csv` (grafik), `docs/ANIMATION_LEDGER.csv` (animation), `docs/AUDIO_LEDGER.csv` (lyd og musik), `docs/VO_SCRIPT.csv` (stemmer). Uden kilde og licensstatus kommer et asset ikke med i et build (GA-33).
5. **Placeholders først, udskiftning uden kode.** Grafik skiftes via `data/art/asset_slots.json`, lyd via `assets/audio/final/<cue_id>.ogg`, stemmer via `assets/audio/vo/<line_id>.ogg`. Spillet virker hele tiden.
6. **Kvalitet før mængde.** Hvis kerneoplevelsen ikke virker i greybox, forbedres den før flere baner, systemer og dyrere grafik (bibel s. 17).

---

## 1. Overblik: faser, porte og milepæle

| Milepæl | Indhold | Opgaver | Port / bevis | Estimat |
|---|---|---|---|---|
| **M0 · Feriebuild** ✅ | Spilbar greybox fra ark til epilog, tests, balance, dokumentation | GA-01…10 DONE | `evidence/`, `docs/STATUS.md` | Udført |
| **M1 · Fase 1-port** | Menneskelig 20-min gennemspilning, Windows-build kørt, `phase-1`-tag | GA-11, GA-12 | Optagelse + build-ID | 2-4 dage |
| **M2 · Synty-basiskit** | Ét skibsmodul, kaptajn, én terrænprøve → derefter arken | GA-13 | Screenshots ved gameplaykamera, ledger | 1 uge |
| **M3 · Kaptajnens animation** | Gang/løb/stop, interaktion, prøve | GA-14 | Video 1x + slowmotion, godkendelsesmatrix | 1 uge |
| **M4 · Lyd v1 + stemmer DA** | Alle HOOKED-cues, ARK + kaptajn indtalt, musik akt I-II | §4-5 | Lyd-review i spillet, ledger udfyldt | 1-2 uger (parallelt med M3) |
| **M5 · Kvalitetsudsnit (fase 2-port)** | 45 min poleret: seks planeter, tre biomer dresset, første kohorte, UI-skin | GA-15…20 | 5 eksterne testere, ingen P0/P1 | 2-4 uger i alt |
| **M6 · Komplet kampagne (fase 3-port)** | Alle biomer, kriser, råd, tre slutninger, balance, borgere, lydidentitet | GA-21…30 | Fuld gennemspilning + fixtures til tre slutninger | 6-12 uger |
| **M7 · Beta + markedsføring** | Privat beta, bugfix, demo, trailer, Steam-side | GA-31…34 | Beta-rapport, trailer af ægte gameplay | 2-3 uger |
| **M8 · Releasekandidat** | Rent build, rollback, overdragelse | GA-35, GA-36 | RC_READY; offentlig udgivelse er en separat beslutning | 1 uge |

Samlet planlægningsramme efter hjemkomst: **ca. 12-22 uger** til releasekandidat, afhængigt af hvor meget tid du kan lægge, og om testere kan skaffes.

---

## 2. Værktøjsmatrix — hvem laver hvad

| Værktøj | Bruges til | Bruges **ikke** til | Leverer | Review-krav |
|---|---|---|---|---|
| **Godot 4.5.1** | Spillet, eksport, screenshots, gameplayoptagelse | — | Builds | `tools/check.sh` grøn |
| **Claude Code / Codex** (koordinator) | Arkitektur, kode, tests, integration, release | Endelige kunstneriske valg alene | Commits + beviser | Tests + gameplaykontrol |
| **Synty-pakkerne (9)** | Al 3D-grafik, UI-grafik, partikel-teksturer | Gameplay-logik (vendor-scripts) | Wrapper-scener i `art/prefabs/` | Skala, facing, kollision, screenshot |
| **Blender** | Rig-normalisering, GLB-eksport, simple meshrettelser | Nye store modeller | `.glb` + kildefil | Importtest i Godot |
| **Mixamo** | Animationshuller (gang, løb, interaktion) efter rig-kontrol | Realistisk tung gang ved siden af stiliseret | FBX-klip | Fodfæste i 1x og 0,25x |
| **ElevenLabs** | Lydeffekter, ambience, stemmer (DA + EN), evt. musik-skitser | Runtime-generering i spillet | `.wav` → redigeret `.ogg` | Lyt i spillet på rigtig bus og afstand |
| **HeyGen** | Devlog-præsentationer, pitch, beta-instruktion med avatar/præsentator | **Lydeffekter** (det er ikke et SFX-værktøj), gameplay, trailer | Præsentationsvideo | Mærket som præsentation |
| **Gemini** (inkl. Veo video / billeder) | Konceptvideo og storyboards til trailer, moodboards, research, tekstkritik, oversættelsesudkast | Gameplaybevis, færdige spil-assets uden review | Skitser, tekstforslag | Koordinator godkender; altid mærket "koncept" |
| **Grok** (inkl. Imagine) | Alternative moodboards/korte konceptklip, idé-sparring, kritik | Gameplaybevis, kanonisk tekst | Skitser, idéer | Som Gemini |
| **Kimi / DeepSeek** | Second opinion på kode eller tekst, isolerede kodeforslag | Direkte commits | Forslag | Koordinator kontrollerer |
| **Meshy / billedværktøjer** | Kun *navngivne* visuelle huller, som Synty ikke dækker (fx ét skilt, en planet-tekstur) | Erstatning for Synty-stilen | Model/tekstur | Skal passe Synty-look, godkendes i spillet |
| **OBS + DaVinci Resolve** | Gameplayoptagelse, trailer, devlog-redigering | — | Video | Kun ægte footage i trailer |
| **Audacity / Reaper** | Trim, fades, loop-punkter, loudness-normalisering | — | Endelige lydfiler | Måler loudness |

Priser, licenser og funktioner hos ElevenLabs, HeyGen, Gemini, Grok, Meshy osv. ændrer sig ofte. **Kontrollér den aktuelle kommercielle licens og pris, før du genererer noget til det færdige spil**, og notér plan/abonnement i ledgeren (kolonnen `license`). Et abonnement beviser ikke API-adgang (bibel s. 28).

---

## 3. Grafik (Synty) — rækkefølge og kvalitetsporte

Detaljeret scene-for-scene samleguide: `docs/SCENE_ASSEMBLY.md`. Importtrin: `docs/SYNTY_INTEGRATION.md`.

**Rækkefølge**
1. *Basiskit (GA-13):* én væg + ét gulv (Space Pack), kaptajnen (Sidekick), én sten. Bevis: screenshot ved gameplaykamera, side om side med greybox.
2. *Arken (M2):* alle `ship.*`-slots, dressing i `scenes/ship/ship.tscn` → `Dressing`. Mål: kryorum (frost, rødt nødlys), værksted (varm rav), embryobank (kølig petrol), bro med udsigt.
3. *Rummet:* `space.ark_exterior` er spillets vigtigste hero-asset (menu, indflyvning, trailer). Planeter tones af planetpaletten.
4. *Tre biomer (GA-18, GA-26):* grøn, ørken, is — props + farezone-FX. Ni site-dressing-scener i `scenes/biomes/`.
5. *Kolonien:* tolv bygninger + moduler i Outpost/Worlds-stil; ved år 20-40 skiftes habitater gradvist til City/Cyber City-varianter (visuel fortælling om vækst — kræver kun nye slots `building.habitat_t2/t3`).
6. *UI (Sci-Fi Menus + Soldier HUD):* 9-slice paneler og knapper i `UiKit.theme()`, ikoner til ressourcelinjen. Tekst + ikon + farve beholdes sammen.

**Art direction (bibel s. 13):** kølig petrol + varm rav + klare servicefarver; hver planet én dominerende naturfarve og én farefarve (står i `data/planets/*.json → palette`). Ingen fotorealistiske assets blandes ind. Lys: én lysgrammatik pr. scene (arken: praktiske lyskilder; overflader: én sol + ambient fra himmelfarve).

**Kvalitetsport pr. asset:** skala mod 1 m-reference · facing · pivot · ingen kollision i wrapper for slots, spillet ejer · materiale matcher paletten · screenshot ved gameplaykamera · ledger udfyldt.

---

## 4. Lyd og musik

### 4.1 Lyddesign (bibel s. 13)
- **Akt I — ensomhed:** arkens ventilatorer, fjern mekanik, dæmpet AI. Meget luft omkring lydene, ingen musik de første minutter.
- **Akt II — håb:** første koloni får mere udendørslyd; robotter og maskiner; musikken kommer ind med første lys i habitatet.
- **Akt III — fællesskab:** menneskestemmer (uden ord), børn i det fjerne, ordløst kor i musikken.
- **Første fødsel:** bæres af lyd og lys, ikke af ansigtsanimation (`stinger_birth`).
- **Alarmer:** entydige, kun to niveauer (advarsel/kritisk), aldrig spam (cooldown 6 s er kodet), altid med visuelt modstykke.

### 4.2 Teknik
| Bus | Indhold | Loudness-mål |
|---|---|---|
| Ambience | Rum- og biomelag | ca. −28 LUFS |
| SFX | Handlinger, maskiner, farer | ca. −20 LUFS, peak −3 dBFS |
| UI | Klik, bekræft, fejl | ca. −22 LUFS |
| Voice | Replikker (ARK får robot-effekt via AudioEffect på bussen) | ca. −18 LUFS dialog |
| Music | Musik og stingers | ca. −23 LUFS |

Format: optag/generér i WAV 48 kHz, redigér, eksportér **OGG Vorbis** (q6) til `assets/audio/final/<cue_id>.ogg`. Loops får rene loop-punkter (krydsfade i redigeringen). Variationer (fx 6 fodtrin) navngives `<cue_id>_01…06` — en lille kodeudvidelse vælger tilfældigt (opgave i M4).

### 4.3 Komplet cue-liste
`docs/AUDIO_LEDGER.csv` — **53 cues** med trigger, bus, loop, længde, loudness-mål og en klar engelsk prompt til ElevenLabs. Kolonnen `code_hook`:
- **HOOKED** (31): koden kalder allerede navnet. Læg filen i `assets/audio/final/` — færdigt.
- **PLANNED** (22): lyden er designet; koden skal have en lille krog (dør, byggeplads-loop, landing, farezoner, epilog-musik osv.). Laves i M4/M6.

Regenerér listen med `python3 tools/gen_audio_ledger.py` (bevarer status/licens).

### 4.4 Pipeline (ElevenLabs Sound Effects)
1. Tag prompten fra ledgeren, generér 3-4 varianter.
2. Vælg én, notér valget og hvorfor i `notes`.
3. Audacity/Reaper: trim, fade 5-20 ms, loop-punkt, normalisér til målet.
4. Eksportér `.ogg` til `assets/audio/final/<cue_id>.ogg`.
5. Lyt i spillet i den rigtige scene, afstand og bus (headset **og** højttalere).
6. Sæt `status = APPROVED`, udfyld `license`. Lås i en indholdsversion.

### 4.5 Musik
- **Hovedtema** (`music_hope`) og de tre epilog-versioner skal være samme melodi i tre stemninger. Anbefaling: en menneskelig komponist (eller dig selv) til temaet; AI-musik (fx ElevenLabs Music) til skitser og baggrundsvarianter, hvis licensen tillader kommerciel brug.
- 7 musikcues + 2 stingers i ledgeren. Musik er dynamisk pr. akt (`music_colony_act2/3` er allerede koblet).

---

## 5. Stemmer (ElevenLabs) — manuskript, casting og proces

**Omfang:** `docs/VO_SCRIPT.csv` — 92 replikker, ca. 4.550 tegn på dansk (ARK 2.500, fortæller 1.200, kaptajn 360, de tre unge ca. 500). Med engelsk version ca. 9.000-10.000 tegn i alt. Det er et lille stemmejob.

| Rolle | voice_id | Retning |
|---|---|---|
| ARK | `ark_ai` | Rolig, præcis, varm under overfladen. Optag rent; robotfilter lægges på Voice-bussen i Godot, så det kan justeres. |
| Kaptajnen | `captain` | Træt, ensom, lavmælt. Rollen er kønsneutral i teksten — vælg stemme bevidst og hold den. |
| Fortæller | `narrator` | **Anbefaling: kun undertekst.** Biblen siger, at undertekster skal virke uden tale; indtal kun, hvis playtest viser behov. |
| Noor / Elias / Sana | `noor`/`elias`/`sana` | Unge voksne: fremadlænet / forsigtig / rolig og bestemt. |

**Proces**
1. Casting: lav 3 kandidatstemmer pr. hovedrolle (ARK, kaptajn), test dem på 5 nøglereplikker i spillet.
2. Lås stemme + indstillinger pr. rolle (notér i `VO_SCRIPT.csv → tool`).
3. Generér alle replikker, gem som `assets/audio/vo/<line_id>.ogg` — **spillet afspiller dem automatisk** med underteksten og forlænger visningstiden til replikken er færdig.
4. Lyt i kontekst; ret udtale (navne: Viridia, Pelagos, Nivalis…) med fonetisk stavning i prompten, ikke i underteksten.
5. Engelsk version efter lokalisering (§9) med samme stemmer, gemmes i `assets/audio/vo/en/` (kodekrog i GA-33).

Ingen læbesynk nødvendig: spillet har bevidst ingen ansigtsanimation (bibel s. 13, 38). Regenerér manuskriptet efter tekstændringer: `python3 tools/export_vo_script.py`.

---

## 6. Video

### 6.1 Tre slags video — og hvad de må
| Type | Værktøj | Må bruges til | Må **ikke** |
|---|---|---|---|
| **A · Gameplay** | Godot + OBS + DaVinci Resolve | Trailer, Steam-video, devlog, beviser (GA-11, GA-34) | — |
| **B · Koncept / storyboard** | Gemini (Veo), Grok (Imagine) | Internt: tone, kameraidéer, trailer-storyboard, mood til lyd og musik | Vises som gameplay; bruges i trailer uden tydelig mærkning |
| **C · Præsentation** | HeyGen | Devlogs med præsentator, beta-instruktion, pitch til forlag/investorer, sociale opdateringer | Gameplaybevis; erstatte gameplayoptagelse |

### 6.2 Trailer (≈ 90 s, kun ægte gameplay — bibel s. 16)
| Tid | Indhold | Scene / fixture |
|---|---|---|
| 0-12 s | Den tavse embryobank, tallet 50.000 | `ship` / `fresh` → `power` |
| 12-25 s | ARK: "Jeg har vækket dig…"; stjernekortet med seks verdener | `ship` + `--action=starmap` |
| 25-40 s | Indflyvning og ekspedition: dragtenergi, fare, prøve | `flight`, `surface` / `expedition:<planet>` |
| 40-50 s | Beslutningen: "Bekræft landing (endelig)" | `--action=landing` |
| 50-65 s | Lys i koloniens første beboede habitat; første fødsel (lyd/lys) | `colony` / `grown:<planet>` |
| 65-85 s | Samme verden senere: børn, skole, råd, by ved år 40 | `colony` / `era:<planet>:40` |
| 85-90 s | Titel + "50.000 embryoner. Seks verdener. Ét valg." | Menu |

Brug Gemini/Grok-konceptklip **kun** til at planlægge disse skud (type B). Optag i 1080p60 (4K hvis maskinen kan), med reduceret HUD-version til flotte skud.

### 6.3 Devlog-plan (valgfri, marketing)
Månedlig devlog: 60-120 s ægte gameplay (A) + evt. HeyGen-præsentator i intro/outro (C). Emner i rækkefølge: arken før/efter Synty · planetvalget · første fødsel · generationsspring · lyd- og musikdagbog.

---

## 7. Animation

Plan efter bibel s. 24-25 og `docs/ANIMATION_LEDGER.csv` (15 klip).
1. **RigLab** (`scenes/tests/RigLab.tscn`, GA-14): én autoritativ humanoid, BoneMap/SkeletonProfileHumanoid, dokumentér facing.
2. **Kilder:** Synty/Sidekick-klip først; Mixamo kun til konkrete huller efter rig-kontrol.
3. **In-place** locomotion; `CharacterAnimator` + `data/art/animation_map.json` er allerede koblet (afspilningshastighed følger faktisk fart).
4. **Godkendelsesmatrix:** idle→gang→stop, gang→løb, interaktion ved terminal, 8 s prøvetagning, pause/restore. Video i 1x og langsom. Først derefter `review_status = APPROVED`.
5. Robotter og borgere: få gode loops, højst ~40 synlige borgere (bibel s. 11).

---

## 8. Narrativ og tekst

- **Findes:** 18 scener / 92 replikker, 26 journallinjer, 6 scoutingproblemer, 9 hændelser, 3 epiloger, 20 mål — alt på dansk i `data/`.
- **Mangler (fase 3):** flere korte borgerscener til år 20-40, journallinjer pr. planet-ankomst for alle seks, epilog-varianter pr. biome, credits.
- **Proces:** skriv i data → kør `tools/export_vo_script.py` → læs højt i spillet → ret. Gemini/Grok/Kimi må give kritik og alternativer; den kanoniske tekst godkendes af dig.
- **Tone:** varmt menneskeligt håb i kold teknologi; korte, konkrete, håndskrevne linjer; ingen generativ NPC-chat (bibel s. 12, 41).

---

## 9. Lokalisering (GA-33)

1. Udtræk alle tekster til en Godot-CSV (`localization/strings.csv`: key, da, en) — kodeopgave.
2. Ordliste (glossary) først: ARK, embryobank, kohorte, persondøgn, forsyningsnet, råd…
3. Engelsk udkast via Gemini/Claude → gennemlæsning af et menneske med engelsk som modersmål (eller grundig selvreview).
4. Engelske stemmer efter tekstlås (§5).
5. Test UI med de længste strenge i 1280×720 og 1920×1080 (bibel s. 26).

---

## 10. UI, HUD og tilgængelighed

- **Skin:** INTERFACE Sci-Fi Menus (paneler, knapper, menuer) + Soldier HUD (dragtmåler, alarmer, ikoner). Ét samlet HUD-sprog, ikke tre stilarter (bibel s. 23).
- **Findes:** tasteomlægning, UI-skala, undertekster med størrelse, reduceret bevægelse, kamerarystelser fra/til, ikon+tekst+farve på alle statusser, pausemenu overalt.
- **Mangler:** controller-understøttelse (valgfri), farveblind-gennemgang af alle farver, test af alle skærme i 1280×720, lydløst-spil-test (alle alarmer har visuelt modstykke) — GA-29.

---

## 11. Gameplay, balance og test

| Lag | Værktøj | Hvornår |
|---|---|---|
| Domænetests (49) | `tests/run_tests.gd` | Ved hver ændring |
| Scenetests (27) | `scenes/tests/scene_smoke.tscn` | Ved hver ændring |
| Balance 6×3 | `tools/balance/run_balance.gd` | Ved hver dataændring i økonomi/befolkning |
| Optaget gameplay | OBS | Hver faseport |
| Eksterne testere | 5 i fase 2, 10-20 i beta | M5, M7 |

Spiltest-protokol (fase 2): spilleren får ingen hjælp; mål: finder første mål (4 af 5), kan forklare én fordel og én ulempe ved sit planetvalg (3 af 5), forstår kravene til første fødsel. Registrér tid til stabil drift og første forvirring. Fejlprioritet: P0 tabte saves/crash/låst progression · P1 forkerte regler/usynlig fare/ødelagt animation i kerneflow · P2 polish (bibel s. 26).

---

## 12. Ydelse og teknik

- Mål: 1080p/60 fps, p95 ≤ 16,7 ms på referencemaskinen (vælges ved hjemkomst og noteres i `docs/VERSION_MATRIX.md`).
- Kendt: generationsprognose ≈ 0,7-1 ms pr. kolonidag; kører i baggrundstråd. Næste skridt hvis nødvendigt: interval-beregning i stabile perioder.
- Synty-scener: bag lys, del materialer, MultiMesh til vegetation, LOD på bygninger; profilér før optimering.
- Save-format er versioneret (schema 2) med migreringstest; hver indholdsversion får en gammel fixture.

---

## 13. Udgivelse og marked (GA-33 → GA-36)

- **Platform:** Windows (Steam) først; Linux-build findes allerede. Pris-hypotese 20-30 EUR (bibel s. 16) — testes, ikke lovet.
- **Steam-side:** capsule-art (render fra spillet med Synty-assets, evt. let paintover), 5-8 screenshots fra ægte gameplay, trailer (§6.2), kort beskrivelse på DA/EN, systemkrav fra målt build.
- **Demo (GA-34):** arken → robotkoloni, klar slutning og save-grænse.
- **Presse-kit:** logo, nøglebilleder, faktaark, trailer, kontakt.
- **Rettigheder:** Synty-licens (brug i spil, ingen redistribution af rå filer), ElevenLabs/HeyGen/Gemini/Grok-vilkår for kommerciel brug pr. genereret fil, fontlicenser, credits-skærm (findes ikke endnu — GA-33).
- **Releasekandidat (GA-35):** byg fra rent checkout, checksum, versionsnoter, forrige kandidat til rollback. Offentlig upload er en separat beslutning.

---

## 14. Budget (udfyldes af dig)

| Post | Valg | Månedlig / engang | Bemærkning |
|---|---|---|---|
| Synty-pakker | 9 pakker | købt | Licens dækker brug i spillet |
| ElevenLabs | plan med kommerciel licens | __ | ~53 lydcues + ~10.000 tegn stemme (DA+EN) |
| HeyGen | valgfri | __ | Kun devlog/pitch |
| Gemini / Grok | eksisterende abonnementer | __ | Koncept, kritik, oversættelsesudkast |
| Komponist (tema) | valgfri | __ | Anbefales til hovedtema |
| Steam Direct-gebyr | engang | __ | Kontrollér aktuel pris |
| Testere / beta | valgfri | __ | Evt. nøgler i stedet for betaling |

---

## 15. Uge-for-uge efter hjemkomst (forslag)

| Uge | Kode/integration (agent) | Dig (kreativt) |
|---|---|---|
| 1 | GA-11/12: gennemspilning, Windows-build, fase 1-tag · import-pipeline klar | Installér Godot 4.5.1, spil, optag; download Synty (FBX) |
| 2 | GA-13 basiskit + arken | Vælg skibs-kit, dress arken i editoren |
| 3 | GA-14 RigLab + kaptajnens animation · lydkroge (PLANNED-cues) | ElevenLabs: casting ARK + kaptajn, generér HOOKED-cues |
| 4 | GA-15/16 polering · UI-skin | Indtal alle DA-replikker, musik akt I-II, UI-pakke |
| 5-6 | GA-17/18 første kohorte-scene, tre biomer | Dress 9 sites, farezone-FX |
| 7 | GA-19/20 spiltest + fase 2-port | Find 5 testere, observer |
| 8-15 | Fase 3: GA-21…30 (kriser, råd, slutninger, borgere, balance, ydelse) | Tekster, musik akt III + epiloger, City/Cyber City-vækst |
| 16-18 | Fase 4: beta, bugfix, demo, trailer, Steam-side | Trailer-klip, presse-kit, Steam-tekst |
| 19 | GA-35/36 releasekandidat og overdragelse | Beslutning om offentlig udgivelse |

---

## 16. Roller efter hjemkomst (bibel s. 20)

- **Koordinator** (én kodeagent): ejer `main`, kontrakter, integration, tests og release.
- **Højst to specialister** i hver sin worktree: (1) miljø/grafik/animation (Synty, RigLab, Blender), (2) indhold/lyd (data, ledgers, lydkroge). Ingen to agenter skriver i samme scene eller datafil.
- **Du:** kreative valg, godkendelser, værktøjer med login (ElevenLabs, HeyGen, Gemini, Grok), spiltest og udgivelsesbeslutninger.

## 17. Risici, der især rammer denne plan

| Risiko | Afbødning |
|---|---|
| AI-lyd/stemmer lyder generiske eller inkonsistente | Lås stemme/indstillinger pr. rolle; lyt altid i spillet; komponist til hovedtema |
| Licensvilkår for AI-genereret indhold ændres | Notér plan og dato pr. fil i ledgeren; behold kvitteringer |
| Konceptvideo forveksles med gameplay | Mærk type B/C tydeligt; trailer kun fra Godot-optagelser |
| Synty-import tager længere tid end planlagt | Proxy forbliver rollback; én scene ad gangen |
| Scope vokser | Indholdslås (bibel s. 12): 6 verdener, 3 biomekort, 12 bygninger, 6 scoutingproblemer, 9 hændelser, 3 slutninger |
