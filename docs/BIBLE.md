# GENESIS ARK — Udviklingsbibel v1.0

> Markdown-transskription af `Genesis_Ark_Udviklingsbibel_v1.pdf` (51 sider, version 1.0, 16. oktober 2026).
> Teksten er gengivet ordret. Sidetal fra PDF'en er angivet som `<!-- side N -->`. Sidefod på alle sider: *SPEC_READY | 16.10.2026 | Spildesign og verificerbar produktionsplan*. Sidehoved: *GENESIS ARK — UDVIKLINGSBIBEL / V1.0*.

<!-- side 1 -->

SPILDESIGN / GODOT / SYNTY / AUTONOM UDVIKLING

# GENESIS ARK

**Du er det sidste menneske, der kan give menneskeheden en fremtid.**

| FERIE | PRODUKTION | KVALITET |
|---|---|---|
| 7 dage · én kodeagent | 4 faser · 36 opgaver | Gameplay · animation · test |

*50.000 embryoner. Seks mulige verdener. Ét valg, du skal leve med.*

Version 1.0 / 16. oktober 2026

Fundament -> kvalitetsudsnit -> komplet spil -> udgivelseskandidat

<!-- side 2 -->

## Indhold og arbejdsvej

Start med mandatet. Læs spillets systemer, de fire faser og opgavekortene. Hver bibel er selvstændig. Klik på et kapitel for at gå til siden.

| Kapitel | Side | Kapitel | Side |
|---|---|---|---|
| Mandat til den ansvarlige kodeagent | 3 | Værktøjskæde efter hjemkomst | 28 |
| Spilløftet og den første uforglemmelige scene | 4 | Startværdier og balancering | 29 |
| Kernesløjfe og den første halve time | 5 | Fase 1 · GA-01 til GA-02 | 30 |
| Kamera, styring og skibsoplevelse | 6 | Fase 1 · GA-03 til GA-04 | 31 |
| Planetmodellen: ingen skjult facitplanet | 7 | Fase 1 · GA-05 til GA-06 | 32 |
| Scouting, rejse og beslutningen om at lande | 8 | Fase 1 · GA-07 til GA-08 | 33 |
| Koloniens fysiske layout og forsyning | 9 | Fase 1 · GA-09 til GA-10 | 34 |
| Økonomi, bygninger og kontrol af vækst | 10 | Fase 1 · GA-11 til GA-12 | 35 |
| 50.000 embryoner og en troværdig tidsakse | 11 | Fase 2 · GA-13 til GA-14 | 36 |
| Kampagnen: fra den sidste til de første | 12 | Fase 2 · GA-15 til GA-16 | 37 |
| Skærme, lyd og visuel identitet | 13 | Fase 2 · GA-17 til GA-18 | 38 |
| Domænearkitektur og specifikke invariants | 14 | Fase 2 · GA-19 til GA-20 | 39 |
| Scenarier, balance og accept af spillet | 15 | Fase 3 · GA-21 til GA-22 | 40 |
| Scope, produktion og kommerciel hypotese | 16 | Fase 3 · GA-23 til GA-24 | 41 |
| Fire faser og bindende leveranceporte | 17 | Fase 3 · GA-25 til GA-26 | 42 |
| Syv feriedage: leverancer dag for dag | 18 | Fase 3 · GA-27 til GA-28 | 43 |
| Ferieprofil og overgang til fuld værktøjskæde | 19 | Fase 3 · GA-29 til GA-30 | 44 |
| Agentstyring, genoptagelse og delegation | 20 | Fase 4 · GA-31 til GA-32 | 45 |
| Repository og tekniske ejerskaber | 21 | Fase 4 · GA-33 til GA-34 | 46 |
| Save/load, determinisme og dataintegritet | 22 | Fase 4 · GA-35 til GA-36 | 47 |
| Synty-pipeline: fra pakke til spilidentitet | 23 | Maskinlæsbar arbejds- og beviskontrakt | 48 |
| Animation I: rig, retargeting og motion | 24 | Startordrer: ferie, genoptagelse og hjemkomst | 49 |
| Animation II: events, våben og kvalitetsport | 25 | Kilder, antagelser og teknisk grundlag | 50 |
| Teststrategi, ydeevne og tilgængelighed | 26 | Kilder og erfaringer, der skal genverificeres | 51 |
| Kommandoer, beviser og releaseprocedure | 27 | | |

<!-- side 3 -->

## Mandat til den ansvarlige kodeagent

Læs denne side først, hvis du får biblen uden resten af samtalen. Den er en arbejdsordre til dette ene spil.

### Opgaven

Byg GENESIS ARK fra et nyt, selvstændigt Godot-repository til en verificeret udgivelseskandidat. Brug produktkravene og opgavekortene i denne bibel som autoritativ baseline. START_HERE.md og tasks.json i startpakken er praktiske kopier; PDF’en indeholder selv de nødvendige beslutninger. Status ved overdragelse er SPEC_READY: dokumenterne er færdige, spillet er ikke implementeret eller testet endnu.

### Arbejd selvstændigt

Vælg den første READY-opgave med opfyldte afhængigheder. Gennemfør en lille, sammenhængende ændring, verificér dens acceptkrav, gem beviser og commit. Fortsæt straks til næste opgave. Brug egne beslutninger til reversible detaljer, navngivning, layout og fejlrettelser. Vent ikke på feedback efter hvert skridt. Hold dig til ét aktivt integrationsspor.

### Ferie og hjemkomst

Dag 1-7: én kodeagent udfører selv alt arbejde på dette spil. Ingen underagenter eller afhængighed af andre projekter. Dag 8+: aktiver de værktøjer, som faktisk findes, og fordel afgrænsede opgaver efter samarbejdskontrakten. Hjemkomst er en kapacitetsændring, ikke en anledning til at omskrive en fungerende kerne.

> Langvarig autonomi kræver en aktiv agentkørsel og tilgængelig maskine. En PDF holder ikke en chatsession kørende. Checkpoints gør arbejdet sikkert at fortsætte efter pauser, kontekstskift og genstart. Ingen garanti om uafbrudt kørsel eller indtjening.

<!-- side 4 -->

## Spilløftet og den første uforglemmelige scene

Du går gennem et mørkt skib. På en væg står 50.000. Tallet er ikke en score. Det er alle, der endnu kan blive til nogen.

### Fantasi

Du er arkens eneste vågne menneske. Jorden kan ikke længere hjælpe. Skibets AI og robotter kan støtte dig, men du beslutter, hvor menneskeheden får sit næste hjem. Spillet forener nærvær om bord, ekspeditioner og et overskueligt kolonispil omkring ét vedvarende ansvar.

### Det særlige

Du leder efter et godt nok hjem med ufuldstændig viden. Mere scouting giver sikkerhed, men slider på skibet og bruger ressourcer. Efter landingen ophører planetvalget ikke: dens tyngde, vand, klima og økologi former byggeri, liv og samfundets første konflikter. Din oprindelige beslutning skal kunne mærkes timer senere.

### Følelsesmæssig kurve

Ensomhed -> håb -> tvivl -> forpligtelse -> stolthed -> at give slip. Første barn er et resultat af forberedelse, ikke en ressourceknap. Slutningen handler om et samfund, der kan klare sig uden kaptajnen. Spillet må gerne være spændende uden at reducere fremtidige mennesker til tabstal.

> Designsøjler: meningsfulde planetvalg; fysisk nærvær på arken; tydelige forsyningskæder; generationer med konsekvenser. Hvis en feature ikke støtter mindst én søjle, udskydes den.

<!-- side 5 -->

## Kernesløjfe og den første halve time

Hvert lag skal give beslutninger til det næste. Undgå tre separate spil, som blot deler en menu.

| Tid | Spillerhandling | Synlig konsekvens |
|---|---|---|
| 0-5 min | Genstart nødstrøm og besøg embryobanken. | Få et konkret mål: find en stabil verden, før reserverne svinder. |
| 5-10 min | Sammenlign tre kandidatverdener og vælg en probe. | Kendte værdier og usikkerheder vises separat; scouting afslører ét vigtigt forhold. |
| 10-17 min | Flyv et kort indflyvningsstykke og gennemfør en ekspedition. | Find vand eller en fare; beslut om endnu en prøve er risikoen værd. |
| 17-25 min | Bekræft landing og etabler et robotnet. | Arken bliver lokal base; terræn og afstand gør første layout vigtigt. |
| 25-30 min | Stabilisér forsyning og planlæg første kohorte. | Se præcis hvilke krav, der mangler, før nyt liv kan støttes. |

### Gentagen sløjfe

Observer -> vælg hypotese -> scout -> investér -> se konsekvens -> justér. Om bord vedligeholder du udstyr og læser planetdata. På overfladen undersøger du konkrete steder. I kolonien bygger du en robust løsning og tager stilling til udvikling. Alle tre visninger skriver til den samme CampaignState.

### Dag 7-grænse

Første uges spilbare slutpunkt er en stabil robotkoloni. Incubation verificeres i en kontrolleret test, men den fulde generationsfortælling kommer senere. Skibet skal føles som et sted, og planeterne skal allerede kræve forskellige valg.

<!-- side 6 -->

## Kamera, styring og skibsoplevelse

Tæt nok på til at mærke ensomheden, langt nok væk til at kunne læse systemerne.

### Primær kontrol

Tredjeperson med WASD og musekamera på skib og ekspedition. E interagerer, Shift løber, Tab viser journal, Esc pauser. Kameraet begrænses af collision og må ikke gå gennem skibsvægge. Ingen krævende platformhop i version 1. Interaktion viser objekt, handling og konsekvens før aktivering.

### Kolonitilstand

B skifter til skråt overheadkamera med WASD-pan, hjulzoom og Q/E trinrotation. Valgt bygning har footprint, forbindelser og forsyningsstatus. Placering er et preview, som først ændrer simulationen ved bekræftelse. Esc fortryder. Skift tilbage til kaptajnen ved en sikker position; ingen teleport gennem låste rum.

### Rumflyvning

Stjernekortet håndterer lange rejser og omkostninger. En kort, afgrænset orbital indflyvning giver pilotfølelse med gas, drej og autopilot. Ingen sømløs galakse eller realistisk orbitalmekanik. Vigtige beslutninger ligger i rute, energiforbrug, skaderisiko og landing; flyvesegmentet må kunne assisteres.

### Skibets tre kernerum

Bro: stjernekort og beslutninger. Embryobank: lagerstatus, redundans og senere omsorgsplan. Værksted: robotter, komponenter og reparationer. Et fælles fysisk loop forbinder rummene, så spilleren aldrig leder efter en nødvendig terminal. Ekstra opholdsrum er senere stemning, ikke fase 1-afhængigheder.

<!-- side 7 -->

## Planetmodellen: ingen skjult facitplanet

Seks hånddesignede kandidater i tre miljøfamilier. Hver har en levedygtig løsning og et vedvarende problem.

| Familie / kandidat | Fordel | Pris og kolonikonsekvens |
|---|---|---|
| Grøn / Viridia | Mildt klima og rig biomasse. | Sporebelastning kræver filtre og adskilte væksthuse. |
| Grøn / Pelagos | Overfladevand og frugtbare kyster. | Stormbælter gør strømreserve og beskyttede placeringer afgørende. |
| Ørken / Ferrum | Malm og sollys. | Vand skal hentes dybt og transporteres sikkert. |
| Ørken / Sere | Stabilt terræn og nemt byggeri. | Støv reducerer solenergi; lagring og vedligeholdelse får vægt. |
| Is / Nivalis | Vandis og geotermiske lommer. | Varmeforbrug og korte arbejdsperioder begrænser ekspansion. |
| Is / Umbra | Lav biologisk risiko og godt mineralgrundlag. | Lang nat kræver geotermi og redundans. |

### PlanetDefinition

id, biome_id, gravity_multiplier, temperature_band, atmosphere_class, water_access, mineral_yield, renewable_profile, hazard_ids og site_templates. Hvert tal har known/estimated/unknown samt confidence og source. UI viser interval ved usikkerhed. Scouting indsnævrer et interval eller afslører en egenskab; den kaster ikke gamle sandheder tilfældigt om.

### Valg uden falsk frihed

Alle seks profiler kan vindes på standard. Balancetest skal dokumentere mindst én robust koloniplan for hver. Ingen planet må være universelt bedst. Før permanent landing vises kendte risici, energiplan og mulighed for at fortsætte rejsen.

<!-- side 8 -->

## Scouting, rejse og beslutningen om at lande

Spænding kommer fra en udløbende mulighed og fra usikkerhed, som spilleren selv kan mindske.

### Scouting i tre trin

Orbital scan giver klima, tyngde og grove signaler. Probe afslører et sites vand/undergrund og én risiko. Kaptajnens ekspedition tager prøver, placerer et relæ og vurderer landingsplads. En prøve er knyttet til et bestemt site; der er ingen gratis global viden fra et enkelt klik.

### Ekspeditionens form

Et 6-10 minutters område med et tydeligt mål, to ruter og en valgfri risikoprøve. Dragtenergi begrænser tid; en drone kan bringe reserve én gang hvis planlagt. Storm, tynd is og sporer telegrapheres visuelt og i instrumenterne. Spillet bruger overlevelse og problemløsning, ikke et skjult alienshooterlag.

### Rejseregnskab

Prototype: fuel 100, integrity 100 og components 40. En rute koster et synligt heltalsbeløb brændstof, og en planlagt probe koster komponenter. Minimumsreserve beregnes til nærmeste kendte levedygtige mulighed. En risikabel rute kræver tydelig bekræftelse. Slitage og hændelser er varslede, datadrevne og begrænsede; ingen tilfældig øjeblikkelig kampagnedød.

### Forpligtelsespunkt

Landing ændrer phase fra VOYAGE til SETTLED og opretter et transaktions-ID. Arken bliver habitat og strømstøtte. Før bekræftelse gemmes et pre-landing checkpoint. Landingen kan ikke gentages for at duplikere skibsressourcer. Standardtilstand tillader at genindlæse checkpoint; ironman er ikke version 1.

<!-- side 9 -->

## Koloniens fysiske layout og forsyning

Spilleren skal kunne forstå, hvorfor et samfund fungerer, ved at se på det.

**LEVELDESIGN / FUNKTION FØR DEKORATION** *(skitse)*

| Zone | Funktion |
|---|---|
| ARK + ROBOTHUB | Start / nødreserve |
| VAND + STRØM | Forsyningsdistrikt |
| HABITAT + OMSORG | Beskyttet zone |
| MINE + VÆRKSTED | Afstand koster kapacitet |

*3 landingssites pr. biome; denne skitse viser ét layout.*

### Tre distrikter

Den valgte verden bruger et af tre håndbyggede biomeområder: landingszone, ressourceområde og sikker boligzone. Kortet er afgrænset og har tre mulige landingssites med forskellige afstande. Scouting afslører sites; fuldt frit procedural planetbyggeri er fravalgt.

### Net og forbindelser

Byggeri kræver gangbar adgang fra robotdepot samt strømforbindelse. Vand og mad beregnes som et forståeligt kolonilager; transportafstand påvirker dronearbejde, ikke et separat avanceret rørsystem. UI viser den konkrete flaskehals: ingen strøm, ingen adgang, utilstrækkelig lagerreserve eller vedligeholdelse.

> Skitsen er en leveldesignreference, ikke et screenshot. Første test bruger primitive bygninger med samme footprint og netregler som de senere Synty-prefabs.

<!-- side 10 -->

## Økonomi, bygninger og kontrol af vækst

En lille, dyb økonomi er bedre end tyve uigennemskuelige ressourcer.

| System | Kontrakt |
|---|---|
| Energi | Produktion/forbrug i kW; batteri i kWh. Prioritet: livsstøtte, omsorg, vand, produktion. Strømsvigt vises før det rammer. |
| Vand / mad | Standardiserede persondøgn med tydeligt forbrug pr. kohorte. Robotter spiser ikke; kaptajnens startforsyning er inkluderet i arkmodulet. |
| Alloy / components | Byggemateriale og raffinerede reservedele; købes ikke gennem en uendelig butik. Både udvinding og vedligeholdelse kan begrænse vækst. |
| Embryoner | Heltalslager med separate tilstande: viable, incubating, born, lost. Summen er altid 50.000. Population tælles separat. |
| Arbejdskraft | Dronekapacitet i robotfasen; voksne kohorter supplerer senere. Jobfordeling er prioriteringer, ikke manuel styring af tusinder. |

### Tolv bygninger i version 1

Solarray, geotermisk generator, batteri, vandanlæg, væksthus, mine, værksted, dronehub, habitat, omsorgs-/incubationscenter, klinik og skole/rådshus. Arkens kerne er en særskilt eksisterende bygning. Varme og filtre er moduler på habitat/produktion; de udvider funktion uden et eksplosivt byggecatalog.

### Balance som data

Bygningsdefinition har footprint, cost, build_work, power, output_rate, workforce og biome_modifiers. Første prototype bruger eksplicitte, små tal og én forsyningskæde. Gør altid det forventede resultat synligt før byggeri. Genbrug/nedrivning returnerer en angivet del, aldrig flere ressourcer end investeret.

<!-- side 11 -->

## 50.000 embryoner og en troværdig tidsakse

Science fiction-teknologien gør rejsen mulig. Samfundet skal stadig vokse gennem omsorg, læring og ansvar.

### Begreber

Brugerens 50.000 æg fortolkes som levedygtige menneskelige embryoner i kryobevaring. Kunstig gestation og robotomsorg er etablerede dele af universet. Incubation er ikke øjeblikkelig voksenproduktion. Embryoner forlader viable én gang; fødsler skaber en børnekohorte med alder, helbred, omsorgsbehov og uddannelse.

### Tid i tre skalaer

Ekspeditioner bruger realtid. Kolonien bruger pause/1x/3x med én afgrænset kolonidag pr. strategisk tick. Store livsfaser flyttes ved eksplicitte spring: efter den første stabile omsorgsperiode til år 20, senere til år 40. Kaptajnen bruger stasis mellem overvågningsperioder; AI og samfundets institutioner bærer dagligdagen.

### Spring er en prognose, ikke en gratis spoleknap

Simulatoren beregner forsyning, aldring, arbejde og planlagte hændelser i deterministiske intervaller. Den stopper før en uafklaret krise eller et ressourceunderskud og viser tidspunkt/årsag. Spilleren godkender en konkret plan. Ingen børn bliver voksne ved at klikke på bygningen, og ingen uforudset tabsskærm vises efter 20 års blind simulation.

### Befolkning uden 50.000 NPC’er

Kohorter er autoritativ data; højst ca. 40 synlige borgere illustrerer livet lokalt. Deres visuals repræsenterer grupper, ikke en fuld agentbaseret demografisimulation. Første kampagnemål er 500 indbyggere og selvforsyning, ikke at klække alle embryoner. Resten er fremtidens mulighed.

<!-- side 12 -->

## Kampagnen: fra den sidste til de første

Tre akter, to generationsspring og et afslutningsmål, der belønner et livskraftigt samfund.

### Akt I · Søgningen

Genopret arken, vurder kandidaterne og vælg et hjem. Seks candidate definitions, tre surface biome maps og seks håndskrevne scoutingproblemer giver variation uden at kræve seks unikke open worlds. AI’en opstiller muligheder, men vælger ikke for dig. Slutpunkt: landed og en dokumenteret koloniplan.

### Akt II · De første

Robotter skaber stabil forsyning. Start en lille kohorte, håndtér én biomespecifik krise og etabler skole/klinik. Tre navngivne unge repræsenterer forskellige drømme og gør resultater personlige. Ingen omfattende NPC-dialoggenerator: brug korte håndskrevne scener, journaler og situationsdialog.

### Akt III · Arven

Ved år 20 udfordrer den første generation dine prioriteringer: mere ekspansion, mere sikkerhed eller mere selvbestemmelse. Ved år 40 vurderes et samfund med mindst 500 mennesker, robust forsyning og et fungerende råd. Valg påvirker tillid, robusthed og afhængighed af arken.

### Tre afslutningsprofiler

Selvstændig civilisation: kan overleve uden arkens nødstrøm. Skærmet civilisation: overlever, men har fortsat kritisk arkafhængighed. Skrøbelig civilisation: må prioritere stabilisering før formel overdragelse. Ingen moralsk score alene afgør udfald; vis konkrete systemiske konsekvenser og de mennesker, der lever med dem.

> Indholdslås: 6 kandidatverdener, 3 biomekort, 12 byggeklasser, 6 scoutingproblemer, 9 kriser/borgerbegivenheder, 3 afslutningsprofiler. Udvid først efter gennemspilning og målt interesse.

<!-- side 13 -->

## Skærme, lyd og visuel identitet

Varmt menneskeligt håb inde i kold teknologi. Det skal føles som at bygge en fremtid, ikke som et regneark med rumtapet.

### Visuelt

Synty sci-fi-interiør, industri, natur/ørken/sne og kolonister er behovsfamilier. Arken har kølig petrol, varm rav og tydelige servicefarver. Hver planet har en dominerende naturfarve og én farefarve. Terrænvariation og silhouette gør områder genkendelige. Ingen fotorealistiske specialassets blandes tilfældigt ind.

### HUD og informationshierarki

Rejse: brændstof, skibstilstand, destination og reserve. Ekspedition: dragt, prøveprogression og vej hjem. Koloni: forsyningsbalance, reserve i dage og kritiske hændelser. Embryotallet er synligt i centrale skærme, men blinker ikke konstant dramatisk. Planetsammenligning viser kendt viden og manglende viden i hver sin kolonne.

### Lyd

Arkens ventilatorer, fjern mekanik og afdæmpet AI skaber ensomhed. Første koloni får mere udendørslyd; menneskestemmer kommer gradvist. Kritiske alarmer har entydig betydning og kan ikke spamme. Undertekster fungerer uden tale. Første barsels-/omsorgsscene bæres af lyd og lys, ikke et dyrt ansigtsanimationssystem.

### Onboarding og fejl

Lær én handling ad gangen gennem skibets reparation. Alle blokerede bygninger forklarer årsag og næste løsning. Før et tidsspring vises forventet forbrug og uløste problemer. Ved ressourcekrise tilbydes prioritering, pause og tilbagevenden til sidste checkpoint; aldrig blot en rød talmur.

<!-- side 14 -->

## Domænearkitektur og specifikke invariants

Én kampagnetilstand binder rejsen, ekspeditionen og kolonien sammen.

| Model | Vigtigste felter / ejer |
|---|---|
| CampaignState | phase, elapsed_days, captain_stasis_years, selected_planet_id, event_ids; CampaignService. |
| ArkState | fuel, integrity, components, systems, embryo_ledger; ArkService. |
| PlanetKnowledge | planet_id, observations[], confidence, sites; SurveyService. |
| ExpeditionState | site_id, suit_energy, samples, extracted; ExpeditionService. |
| ColonyState | biome_id, buildings, network, inventory, jobs, cohorts, trust; ColonySimulation. |
| CohortState | id, size, age_days, health, care_need, education, role; PopulationService. |

### Kommandoer

RequestTravel, CompleteSurvey, CommitLanding, PlaceBuilding, StartIncubation og AdvanceEra valideres mod samme model. Kommandoer returnerer success/error samt konkrete årsager. UI og 3D-adaptere abonnerer på resultater. Planetdata ændres aldrig af en HUD-knap uden en domænekommando.

### Ufravigelige regler

Alle ressourcer er >=0. Viable+incubating+born+lost =50.000. Born er historiske fødsler, population er aktuelt levende; de må ikke forveksles. En cohort kan ikke arbejde som voksen før aldersgrænsen. Landing kan kun committes én gang. Byggeri kan ikke forbruge samme cost to gange. Tidsfremskrivning stopper ved første uafklarede kritiske hændelse.

<!-- side 15 -->

## Scenarier, balance og accept af spillet

Den mest risikable antagelse er, om planetvalget stadig betyder noget efter landingen.

| Prøve | Bestået når |
|---|---|
| GA-A · Tre valg | Samme start kan skabe tre forskellige levedygtige koloniplaner. Spilleren kan forklare én fordel og én varig ulempe ved sit valg. |
| GA-B · Viden | En probe fjerner en konkret usikkerhed. Ekstra scouting har en synlig pris og kan fravælges rationelt. |
| GA-C · Forsyning | Afbryd strøm til vandanlæg: korrekt varsel, ændret forsyning og mulighed for prioriteret genstart uden tavst befolkningstab. |
| GA-D · Generation | Start kohorte, gem, load, spring til voksenfase. Embryoregnskab, alder og roller er identiske med kontrolkørslen. |
| GA-E · Kriser | Spore-, støv- og kuldekrise har forskellige løsninger og kan ikke vindes med samme standardlayout. |
| GA-F · Slutning | Afslutningsprofil følger faktisk robusthed og rådets status; ingen softlock ved manglende valgfrit mål. |

### Spiltestmål

Fase 2: mindst fem eksterne testpersoner, hvis de kan rekrutteres med brugerens mandat. Første mål findes uden hjælp af mindst fire. Mindst tre kan beskrive et reelt planettradeoff efter testen. Hvis adgang til spillere mangler, registreres playtest som udestående; agentens egen vurdering er ikke brugerdata.

### Balancearbejde

Simulér seks planeter med mindst tre kolonistrategier og faste seeds. Registrér tid til stabil drift, mindstereserve, krisegenopretning og afhængighed af arken. Tuning skal bevare forskelle og fjerne blindgyder, ikke gøre alle verdener ens.

<!-- side 16 -->

## Scope, produktion og kommerciel hypotese

Ambitionen er en stærk premiumoplevelse med replay gennem valg og konsekvenser.

### Udgivelsesmål

Singleplayer desktop, Windows primært; andre platforme først efter en fungerende native port. Arbejdsmål: 6-10 timers første kampagne, derefter nye planetvalg. Det er en designhypotese, som måles i fase 3. Foreslået pristest: 20-30 EUR, ikke dokumenteret markedspris eller indtjeningsløfte.

### Fravalgt i version 1

Ingen multiplayer, uendelig galakse, fuld astrofysik, sømløs planetflyvning, genetisk optimering af mennesker eller 50.000 individuelle NPC-simulationer. Ingen kampagne, som kræver en ekstern AI-tjeneste for at virke. Disse fravalg beskytter netop den centrale drøm: at tage ansvar for et nyt hjem.

### Markedsførbar scene

En kort gameplaysekvens går fra den tavse embryobank til planetvalget og ender med lys i koloniens første beboede habitat. Vis den samme verden senere med børn, skole og råd. Traileren skal dokumentere konsekvens over tid, ikke bare flyve hen over flotte assets.

### Stop-/fortsætbeslutning

Fortsæt indholdsproduktion når planetvalg skaber forskellige planer, kolonien er forståelig, og første omsorgskohorte føles meningsfuld. Hvis spillerne kun oplever ventetid, reduceres tidsfriktion og tomme rejser. Hvis layoutet ikke betyder noget, styrkes energi/afstand/biome før flere bygninger.

<!-- side 17 -->

## Fire faser og bindende leveranceporte

Tidsangivelser efter ferien er planlægningsintervaller, ikke løfter. Portene afgør, hvornår næste fase begynder.

| Fase | Leverance og port | Plan |
|---|---|---|
| 1 · Fundament | En 20-minutters kæde: vågn på arken, vælg mellem tre planetprofiler, scout én zone, land, opfør strøm/vand/habitat og gem/genindlæs en stabil robotkoloni. | Dag 1-7. 12 opgaver. |
| 2 · Kvalitetsudsnit | Et poleret 45-minutters udsnit med Synty, godkendt kaptajnrig, seks reelle planetvalg og første omsorgskohorte. Hele sløjfen kan spilles uden debugværktøjer. | Efter hjemkomst; ca. 2-4 arbejdsuger. 8 opgaver. |
| 3 · Komplet spil | Komplet kampagne fra afrejse til selvstændigt samfund: alle seks kandidater, tre kolonibiomer, to generationsspring og alle systemer/afslutninger. | Ca. 6-12 arbejdsuger efter fase 2. 10 opgaver. |
| 4 · Udgivelse | Verificeret desktopkandidat med komplet kampagne, migrerbare saves, tilgængelighed, performanceprofil og ærlig gameplay-/storepakke. | Ca. 2-4 arbejdsuger efter fase 3. 6 opgaver. |

### Portregel

En port består kun, når alle obligatoriske opgaver i fasen er DONE med faktiske beviser. BLOCKED_ENVIRONMENT er ikke godkendt. Et midlertidigt proxyasset er tilladt i fase 1, hvis det er registreret; det tæller ikke som godkendt animation, Synty-integration eller udgivelsesgrafik.

### Opgavernes rækkefølge

Opgavekortene har entydige ID’er, afhængigheder, ændringsområde, trin og accepttest. Der er 36 kort. En senere fase må undersøges uden at åbne store implementeringsspor. Hver ny feature skal fjerne et kendt problem eller opfylde et konkret krav. Udvid ikke scope, fordi agenten har ledig kontekst.

> Hvis kerneoplevelsen ikke fungerer i gråblokke, forbedres den før flere baner, flere systemer og dyrere grafik. En poleret forkert kerne tæller ikke som fremskridt.

<!-- side 18 -->

## Syv feriedage: leverancer dag for dag

Dag 1 betyder den faktiske startdag. Planen dækker syv hele dage, også når de krydser en kalenderuge.

| Dag | Arbejde | Bevis ved dagens slutning |
|---|---|---|
| 1 | GA-01/02: audit, boot, kamera og kaptajn. | Ren opstart og input-/kameraoptagelse. |
| 2 | GA-03/04: tre skibsrum, ressourcer og planetskema. | Bro -> embryobank -> værksted; validerede planetfixtures. |
| 3 | GA-05/06: stjernekort, rejse og scouting. | To forskellige rejser giver korrekt forbrug og ny viden. |
| 4 | GA-07/08: planetlanding og robotbyggeri. | Én zone med strøm, vand og habitat; placeringsregler virker. |
| 5 | GA-09/10: første kohortelogik og save/load. | Kontrolleret incubationstest og præcis roundtrip. |
| 6 | GA-11: saml gameplay og udfør fejl-/UI-pas. | 20-minutters prøve; ingen blindgyde eller skjult kritisk pris. |
| 7 | GA-12: eksport, regression, beviser og hjemkomsthandoff. | Kørbar demo eller tydeligt navngivet miljøblokering. |

### Prioritet ved lavere kapacitet

Beskyt kontrol, kamera, kernesløjfe, save/load og en start-til-slut-demo. Skær ekstra indhold og visuel pynt først. Skriv præcist hvad der er udskudt og hvorfor. De syv dage er en fokuseret produktionsperiode; arbejdsdagens længde afhænger af maskinen, agentens kørsel og fejl, der faktisk findes.

### Hvis der er tid til overs

Tag næste READY-opgave efter fase 1-porten. Udfør én kvalitetsforbedring ad gangen: styring, animation, lyd, læsbarhed, ydeevne. Undgå at starte et andet spil. En optaget gameplaysekvens med god rytme er mere værd end ti ufærdige systemer.

<!-- side 19 -->

## Ferieprofil og overgang til fuld værktøjskæde

Det samme repository, de samme data og de samme spilregler bruges før og efter hjemkomsten.

### Første miljøaudit

Registrér operativsystem, Godot-binær og version, renderer, GPU, skærm, Git, diskplads, eksportskabeloner og hvilke Synty- og animationsfiler der faktisk er tilgængelige. Søg i brugerens oplyste projekt- og assetmapper; opfind ikke gamle stier. Læs eksisterende AGENTS.md og tag et sikkert baseline-commit før ændringer.

### Fungerende ferieprofil

Kør Godot 4.x med GDScript, lokale data og desktop-export. Hvis kun headless Godot er tilgængelig, skriv domænetests, scenesmoke og validerede data, men markér visuel kontrol som afventende. Mangler Godot helt, opbyg data, repository, specifikationer og importinventory; forsøg en tilladt lokal installation. Kald ikke dette et spilbart build.

### Manglende assets

Brug primitive figurer og egne simple farvematerialer med samme størrelse, collision og sceneinterface som det kommende Synty-asset. Skift senere VisualRig eller miljøprefab uden at ændre simulation. Mangler en animation, dokumentér clipbehovet og brug en tydeligt registreret proxy; hent ikke tilfældige nye pakker som skjult afhængighed.

### Hjemkomstkontrol

Kør den seneste build på den fulde maskine, importér de rigtige assets gennem en karantænemappe, genkør save/load og gameplaytesten, og opdatér capability-matrix. Ret miljøforskelle i små commits. Ingen opgradering af engine midt i en port uden en konkret grund, rollback og regressionskørsel.

<!-- side 20 -->

## Agentstyring, genoptagelse og delegation

Få afsluttede, dokumenterede leverancer frem for mange samtidige halvfærdige ændringer.

### Tilstandsmaskine for opgaver

TODO -> READY -> IN_PROGRESS -> VERIFYING -> DONE. READY kræver alle depends_on i DONE. Fejl giver REWORK; manglende reel adgang giver BLOCKED_ENVIRONMENT. DROPPED kræver en dokumenteret scopebeslutning og en ændret port. Hver opgave har acceptance, owner, branch, last_commit, evidence og næste handling.

### Checkpoint efter hver opgave

Skriv STATUS.md med sidste beståede port, aktiv opgave, SHA, udførte tests, kendte problemer og næste tre READY-opgaver. Opdatér DECISIONS.md ved arkitekturvalg og RISKS.md ved konkrete blokeringer. Gem en lille test-save og et reproduktionsseed. Commit kun projektfiler; ikke credentials, buildcache eller hele rå assetbiblioteker.

### Efter hjemkomst: koordinator + højst to specialister

Koordinatoren ejer main, scope, kontrakter og integration. En specialist kan eje miljø/animation i en worktree, en anden tests/indhold i en anden. Opgaven gives med ID, mål, tilladte mapper, inputversion, acceptkrav og afleveringsformat. Ingen to agenter skriver i samme scene eller datafil. Specialistens commit integreres først efter kontrakt- og gameplaykontrol.

### Når noget stopper

Prøv højst tre forskellige, dokumenterede løsningshypoteser på samme fejl. Gem logs, lav den mindste reproduktion, og tag en anden READY-opgave hvis der er en. Efter genstart læses mandat, STATUS, DECISIONS og tasks.json før kode ændres. Afsluttede opgaver genåbnes kun ved konkret regression.

> Eksterne køb, offentlige udgivelser og beskeder til andre følger brugerens faktiske mandat. Gør bygge- og udgivelsespakken færdig, før en eventuel manglende tilladelse bliver det sidste stop.

<!-- side 21 -->

## Repository og tekniske ejerskaber

Et enkelt Godot-projekt med små domænemoduler. Ingen webbackend, multiplayer eller fælles tre-spils-platform i version 1.

| Sti | Ansvar |
|---|---|
| project.godot / scenes/ | Entry scene, flow, aktører, UI, baner og testgallerier. |
| scripts/domain/ | Regler og serialiserbar tilstand. Ingen afhængighed af visuelle nodes. |
| scripts/runtime/ | Fysik, navigation, input, spawns og præsentationsadaptere. |
| data/definitions/ | Validerede Resource-definitioner med stabile ID’er. Balance ligger her. |
| assets/source_inventory/ | Metadata og checksums; kildemateriale bevares uændret uden for arbejdsfiler. |
| assets/imported/ + art/prefabs/ | Udvalgte imports og egne wrapper-scenes; ingen vendor-controller som runtime. |
| tests/ + fixtures/ | Domænetests, scenetests, save-fixtures og faste seeds. |
| docs/ + evidence/ | Bibel, beslutninger, status, opgavebeviser, profileringsresultater. |
| tools/ + builds/ | Validering/eksport; builds er genererede og holdes ude af normal kildehistorik. |

### Få globale services

AppFlow håndterer scener, SaveService håndterer filer, AudioService lydgrupper og SettingsService indstillinger. GameSession ejer det aktive domæne. Brug eksplicitte referencer og typede signals; ikke en global eventbus, som skjuler alle afhængigheder. UI sender kommandoer; det ændrer ikke tilstand direkte.

### Versioner og navne

Vælg en stabil Godot 4.x, som kan køre på feriemaskinen, og lås nøjagtigt nummer i VERSION_MATRIX.md. GDScript med typer, snake_case filer, PascalCase klasse-navne. Brug composition frem for dybe arvetræer. Afhængigheder indføres kun ved dokumenteret gevinst og licens-/versionsnotat.

<!-- side 22 -->

## Save/load, determinisme og dataintegritet

Et tabt save eller dobbelttalt resultat ødelægger tilliden til hele spillet. Gem domænet, ikke tilfældige nodes.

### Save-kontrakt

Envelope: schema_version, game_id, build_id, content_version, save_id, saved_at, seed, rng_state, payload, checksum. Payload har stabile entitets-ID’er og primitive værdier; aldrig NodePath til en importeret figur. JSON er tilstrækkeligt til første version. Valider typer, ID-referencer og værdigrænser før tilstanden aktiveres.

### Sikker skrivning og migrering

Serialisér til en midlertidig fil i user://, luk og genlæs den, validér checksum og invariants, behold sidste gyldige backup, og erstat derefter hovedfilen via samme filsystem. Test omdøbning på mål-OS. Ved afbrudt skrivning tilbydes backup. En migration fra n til n+1 arbejder på en kopi og må ikke ødelægge originalen.

### Gentagne hændelser

Mission, byggeri, incubation og belønninger bruger event_id eller transaction_id. Allerede anvendte events må ikke anvendes igen efter load. Gem på et konsistent simuleringspunkt; pause kommandoindtag under snapshot. Restore opretter model, derefter aktører og til sidst UI. Der må ikke affyres skud, uddeles XP eller aktiveres lyd som utilsigtet restore-sideeffekt.

### Reproducerbarhed

Kampagnevalg og contentudtræk bruger adskilte RNG-strømme med gemt seed/state. Fysik kan variere; lov ikke bitidentisk 3D-physics på tværs af hardware. Domæneberegninger og eventrækkefølge skal være reproducerbare for samme fixture. Gem nok input og state til at diagnosticere en spillerfejl.

> Obligatorisk: normal roundtrip, duplikeret completion-event, afbrudt save, korrupt save, ukendt content-ID og migrering af én gammel fixture. Ingen tavs nulstilling til en ny kampagne.

<!-- side 23 -->

## Synty-pipeline: fra pakke til spilidentitet

Synty er det visuelle fundament. Konsekvent kamera, lys, farver og animation skaber spillets egen identitet.

### Inventory før import

Lav ASSET_LEDGER.csv med asset_id, kildepakke, faktisk filsti, format, checksum, rig_id, skala, materialer, licensstatus og brugsscene. De nævnte assetfamilier i denne bibel er behov, ikke en påstand om ejede pakker. Vælg én menneskelig basisrig og et begrænset miljøsæt først. Hold ubrugte pakker ude af projektet.

### Importkontrakt [R1, R7]

Foretræk en verificeret GLB-leverance til spillet, eller brug Godots understøttede FBX-import når den er afprøvet i den låste version. Eksisterende .blend-filer kræver den relevante Blender-pipeline; det må ikke være en skjult ferieafhængighed. Mål en figur mod en 1 m reference, kontrollér facing, pivot, materialer, skeleton og statisk collision.

### Wrapper og collision

Vendorfiler er read-only. Byg egne wrapper-scenes, hvor controller, collision, navigation, hurtbox, sockets og VisualRig er adskilt. Miljøprops får simple collision proxies; små pynteting får ofte ingen. Statiske navmeshflader bages efter gameplaygeometri, ikke efter hver dekorativ sten. Del materialer og instansér gentagen vegetation bevidst.

### Visuel sammenhæng

Én palet og én lysgrammatik pr. spil. Justér albedo/materialer i egne ressourcer; samme hud-/metalrespons på tværs af pakker. Funktionelle døre, cover og interaktioner skal skille sig fra dekoration. UI-pakker leverer grafik, ikke tre konkurrerende HUD-stilarter. En smuk prop, som ligner cover men ikke beskytter, er en designfejl.

> Importbevis: source hash, screenshot ved gameplaykamera, mål/skala, collisiontest og materialekontrol. Udgiv ikke rå købte pakker i en offentlig startpakke eller et offentligt repository.

<!-- side 24 -->

## Animation I: rig, retargeting og motion

Tidligere arbejdsprincipper er genbrugt; konkrete gamle rigs og clips skal stadig kontrolleres i det nye projekt.

### Canonical rig [R2]

Lav RigLab.tscn med én autoritativ humanoid og målestok. Registrér bone names, hierarchy, bind/rest pose, proportioner og socketplacering. BoneMap og SkeletonProfileHumanoid kan hjælpe retargeting, men ens navne er ikke nok: bone rests og akser skal stemme. Dokumentér forskellen mellem importprofilens facing og controllerens fremadretning; korrigér i VisualPivot én gang.

### Kilder og stil

Synty-klip, når de findes og passer, er førstevalg. Mixamo udfylder konkrete huller efter kontrol af rig, stil og brugsvilkår. Brug ikke en realistisk tung gang på én figur og en let stiliseret gang på de andre uden en bevidst fælles retning. Ikke-humanoide droner, væsner og køretøjer får egne rigs; pres dem ikke gennem et humanoidprofil.

### In-place som standard

Controller/navigation ejer figurens position. Locomotion er in-place, og anim_speed følger den reelle vandrette hastighed. Root motion kræver et eksplicit behov og collisionstyret bevægelse; undgå dobbelt bevægelse fra både animation og kode. Justér stride/tempo ved gang, løb og stop. Tjek fødder i 0,25x og 1x uden kamerarystelse.

### AnimationTree [R3]

AnimationPlayer rummer normaliserede clips; AnimationTree styrer locomotion, aim-lag, handlinger og afbrydelser. Lower-body locomotion fortsætter under relevant upper-body sigte. Maskér kun de nødvendige knogler. Death/downed har højere prioritet end reload, som har højere prioritet end normal locomotion. Blendtider er data, ikke spredte magiske tal.

> Historisk grundlag: EDEN9-masterens afsnit 4.3 og 4.8-4.9. Det er tidligere dokumenterede kvalitetskrav, ikke bevis for, at dette nye spil allerede har korrekte animationer.

<!-- side 25 -->

## Animation II: events, våben og kvalitetsport

Den handling, spilleren ser, skal være den handling simulationen udfører.

### Én ejer af handlingen

ActionController udsteder action_id og en valideret tidslinje. Gameplayeventet er autoritativt; animationsmarkører er synkroniseret præsentation eller en kontrolleret callback med samme action_id. Skud må aldrig affyres både af input, en animationstrack og et signal. Reload ændrer ammunition ved ét commitpunkt; afbrudt handling følger den specificerede regel.

### Sockets og kontakt

WeaponSocket, MuzzleSocket og håndreference kontrolleres med det faktiske våben. Projektil/raycast starter i den validerede muzzleposition efter en ekstra blokeringstest tæt på figuren; det må ikke skyde gennem væggen, fordi våbnet stikker gennem den. Ved to hænder bruges godkendt clip eller enkel stabil håndtilpasning. Smarte IK-systemer må ikke skjule et dårligt grundrig.

### Manifest

For hver clip: clip_id, source_asset_id, rig_id, state, duration_s, loop, in_place, speed_range, event_times, interrupt_policy, blend_in/out og review_status. Kontakt, skade, release, magazine_commit og færdigpunkt er navngivne events. Udjævn overgange mellem forskellige kilder. Seedet faseforskydning giver holdet variation uden at ændre gameplay.

### Godkendelsesmatrix

Se idle->move->stop, move->aim->fire, fire->reload, hit under reload, downed/death, revive og pause/restore. Krav: ingen tydelig foot slide ved gameplaykamera, ingen posesnap, korrekt greb/muzzle, intet dobbeltevent, ingen animation efter despawn og ingen skade under normal pause. Brug RigLab og en virkelig mission. Gem video i 1x og langsom gennemgang af fejl.

> En headless test kan bevise eventantal og tilstande. Den kan ikke bevise, at skuldre, fødder og våbengreb ser rigtige ud. Visuel animation bliver først APPROVED efter billed-/videokontrol.

<!-- side 26 -->

## Teststrategi, ydeevne og tilgængelighed

Test de dyre fejl og de oplevelser, som definerer spillet. Undgå tests, der blot gentager implementationen.

### Fire testlag

1: rene domænetests for ressourcer, skade, objectives og idempotens. 2: Godot-scenetests for collision, input, navigation og restore. 3: optaget gameplay fra den aftalte prøve med kontrol af læsbarhed og animation. 4: ren eksport på mål-OS uden editor. Hver port kræver relevante lag; en grøn parser er ikke et godkendt spil.

### Performancebudget

Første desktopmål er 1080p/60 fps på en dokumenteret referencecomputer; vælg faktisk hardware i fase 1. Mål CPU/GPU frametime, hukommelse og loading i samme prøve tre gange efter opvarmning. Arbejdsmål: p95 frame <=16,7 ms og p99 <=33,3 ms i referencekamp, uden vedvarende stutter. Lavere grafikprofil må reducere skygger/VFX, ikke fjendetelegraph eller sigtelæsbarhed.

### Budgettér systemerne

Adskil fysiktick fra taktiske beslutninger og kostbar stifinding. Spred AI-opdateringer, begræns aktive aktører og pool kortlivede effekter efter måling. Navigationavoidance løser ikke dørlogik eller fysisk collision [R4]. Profilér først; indfør ikke en stor ECS eller multithreading uden en påvist flaskehals.

### Tilgængelighed

Alle handlinger kan ombindes. UI skaleres og testes i 1280x720 og 1920x1080; kritisk tekst klippes ikke. Reducér shake, flashes og motion. Undertekster har afsender og justerbar størrelse. Farve er aldrig eneste signal: brug form, ikon og tekst. Combatkritiske lyde har visuelle signaler. Pause og indstillinger skal være tilgængelige fra gameplay.

### Defektprioritet

P0: tabte saves, crash, låst progression. P1: forkerte kampregler, usynlig fare, fastlåst navigation, ødelagt animation i kerneflow. P2: ikke-blokerende polish. Ingen P0/P1 ved faseport eller udgivelse; P2 har ejerskab og bevidst prioritering.

<!-- side 27 -->

## Kommandoer, beviser og releaseprocedure

Kommandoerne er en startkontrakt. Agenten opretter de nævnte testfiler; de findes ikke allerede i en leveret spilimplementation.

### Minimumskommandoer [R5]

- `godot --version | godot --help`
- `godot --headless --path . --import`
- `godot --headless --path . --script res://tests/run_tests.gd`
- `godot --headless --path . --script res://tests/scene_smoke.gd`
- `godot --path .` (spilbar og visuel kontrol)
- `godot --headless --path . --export-release "Windows Desktop" builds/windows/game.exe`

### Portabilitet

Brug den reelle binærsti eller et dokumenteret GODOT_BIN. Eksportpreset skal oprettes, templates matche engine, og outputmappen eksistere. På andet ferie-OS bygges også en lokal native eksport. --check-only kontrollerer et angivet script og beviser ikke hele projektet. Ukendte flags kan ignoreres; kontrollér derfor output og exitkode.

### Bevisformat

evidence/<task-id>/result.json indeholder commit, engine_version, command, exit_code, expected, observed, timestamp, fixture og status. Tilføj relevant log og screenshot/video, ikke følsomme stier eller tokens. Et screenshot uden build-ID kan ikke alene bevise en regression. Markér eksplicit NOT_RUN, PASS eller FAIL; opfind aldrig kørsel.

### Udgivelseskandidat

Byg fra et rent checkout, kør savecompatibility og en fuld kampagne, kontrollér credits/licenser, audioindstillinger, controller hvis understøttet og første opstart uden editor. Lav checksum og versionsnoter. Pak kun nødvendige runtimefiler. Behold forrige kandidat og dokumentér rollback. Offentlig storeupload er en særskilt handling efter et verificeret releasebundle.

<!-- side 28 -->

## Værktøjskæde efter hjemkomst

Værktøjer vælges til afgrænsede resultater. Spillets kerne fungerer uden cloudtjenester under afvikling.

| Rolle | Brug og afleveringskrav |
|---|---|
| Codex / Claude Code | Én er koordinator. Arkitektur, kode, tests, integration og release. Den anden kan efter hjemkomst løse et isoleret specialistkort. |
| Blender / scripts / MCP | Rignormalisering, sockets, eksport, simple meshrettelser. Aflever originalreference, bearbejdet fil, GLB og importtest. |
| Synty + Mixamo | Miljøer, figurer og validerede animationshuller. Ledger og gameplaykamera-review kræves. |
| Kimi / Gemini / Grok / DeepSeek | Valgfri kritik, tekst, research eller isoleret kodehjælp hvis adgang findes. Output er forslag, indtil koordinatoren har kontrolleret det. |
| ElevenLabs | Valgfri voice/SFX efter en konkret lydliste og budget. Lokale placeholderlyde holder udviklingen i gang. |
| Meshy / billedværktøjer | Kun navngivne visuelle huller eller konceptreference. Nye assets skal passe Synty-stil og godkendes i spillet. |
| HeyGen / videoværktøjer | Valgfri præsentation/storyboard; aldrig bevis for faktisk gameplay eller erstatning for gameplayoptagelse. |

### Capability-matrix

Registrér available/unavailable, auth_mode, allowed_actions, input/output og budget for hver service. Et abonnement beviser ikke API-adgang. Ingen private nøgler i kode, screenshots eller opgaveprompts. Hvis et værktøj mangler, fortsæt med en lokal løsning og notér præcis hvilket kvalitetsarbejde der udestår.

### Reviewsløjfe

Specialist får et låst input og ét resultat. Koordinator tjekker format, import, rettigheder og accepttest. Én revision skal pege på en konkret mangel; undgå endeløs generering uden målkriterium. Grafik og lyd låses i indholdsversioner, så et nyt asset ikke ændrer alle gamle missioner utilsigtet.

<!-- side 29 -->

## Startværdier og balancering

Disse tal er første implementeringsbaseline, ikke påstået færdig balance. De skal ligge i data og ændres med bevis.

| Område | Første værdier |
|---|---|
| Start og rejse | 50.000 viable; 0 øvrige embryo-state. Fuel 100, integrity 100, components 40. Prototype-ruter: 12/18/24 fuel; probe: 3 components. |
| Ekspedition | Suit 100; drain 0,12/s uden fare. Reservevarsel ved 30. Prøvetagning 8 s. Returnering og genopfyldning er eksplicit. |
| Koloniproxy | Start alloy 120. Solarray: 30 alloy, +12 kW. Vandanlæg: 35 alloy, -4 kW. Habitat: 40 alloy, -3 kW. Ark: +8 kW nødstrøm. |
| Incubationfixture | 10 embryoner pr. testkohorte; omsorgscenter, vand/madreserve og +5 kW kræves. 270 strategiske dage til fødsel; 18 år til voksenarbejde; spring til koloniår 20 sker efter fødsel og opvækst. |
| Generation | Dag -> år bruger 365 dage som spilabstraktion. År 20 og 40 er eksplicitte kapitelmål. Tidsspring stopper før uafklaret krise. |
| Kontrol og måling | Player walk 3 m/s, run 5 m/s som første tuning. 60 Hz fysik; koloniøkonomi tickes separat, aldrig per renderframe. |

### Hvordan der tunes

Lav baselinefixture, ændr én sammenhængende variabelgruppe og kør samme prøve igen. Notér gammel/ny værdi, forventning og observeret virkning. Synlig forbedring i styring, fairness eller beslutningskvalitet har prioritet over teoretisk realisme. Nye værdier kræver opdateret dokumentation, ikke nødvendigvis omskrivning af kode.

### Ingen skjulte løfter

Alle mængder, tider og contentlofter i biblen er designbeslutninger og testmål. De bliver først verificerede egenskaber, når et build består de beskrevne prøver. Hvis en antagelse ikke holder, ændres den i DECISIONS.md med konsekvens for porten.

<!-- side 30 -->

## Fase 1 · GA-01 til GA-02

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-01 · Miljø, repository og startscene

**Afhængigheder:** Ingen; bootstrap.  
**Ændringsområde:** project.godot; docs/; tools/.

#### Udfør

Registrér Godot/OS/GPU og tilgængelige assets. Opret separat Git-repository, inputmap og en tom boot->menu->game->quit-sløjfe. Lås engineversion og renderer. Lav en repeatable smoke-kommando og et baseline-commit.

#### Acceptprøve

Ren opstart uden parserfejl; exit fungerer; version og faktisk kørsel er dokumenteret. Ingen eksisterende projekter overskrives.

#### Ved problemer

Hvis engine mangler: dokumentér installation/fejl og fortsæt kun med data og tooling; spilbarhed er BLOCKED_ENVIRONMENT.

### GA-02 · Kaptajn, collision og to kameraer

**Afhængigheder:** GA-01.  
**Ændringsområde:** scenes/actors/; scripts/runtime/player/; scenes/tests/.

#### Udfør

Byg CharacterBody3D med VisualPivot, collision og interaktion. Lav tredjeperson og kolonipan som separate camera modes. Test ramper, hjørner og kameracollision med simple blokke. Hold input adskilt fra domænet.

#### Acceptprøve

10 gennemløb af samme rute uden væggennemgang eller mistet figur. Kameraskift giver ingen dobbelt input eller teleport.

#### Ved problemer

Reducer kamerafunktioner til én stabil mode ad gangen; rig må være en kapsel indtil import er afklaret.

<!-- side 31 -->

## Fase 1 · GA-03 til GA-04

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-03 · Arkens tre rum og første opgave

**Afhængigheder:** GA-02.  
**Ændringsområde:** scenes/ship/; data/objectives/; scripts/domain/.

#### Udfør

Byg bro, embryobank og værksted med et kort loop. Gør nødstrømsreparation til første objective. Tilføj interaktionsprompts, låst/ulåst terminal og tydelig vej til næste mål. Brug samme interface på alle stationer.

#### Acceptprøve

Ny spiller kan starte strøm og åbne planetskærm uden debug. Objective kan ikke belønnes to gange ved gentaget interaktion.

#### Ved problemer

Skær pynt og ekstra korridorer; behold rumfunktioner og læsbare skiltning.

### GA-04 · ArkState og validerede planetdata

**Afhængigheder:** GA-01.  
**Ændringsområde:** scripts/domain/ark/; data/planets/; tests/.

#### Udfør

Implementér fuel, integrity, components og embryo-ledger. Opret tre prototypeplaneter med known/estimated/unknown-observationer. Valider ID’er, intervaller og værdigrænser ved load. UI læser snapshots frem for at eje værdier.

#### Acceptprøve

Ugyldig planet afvises med præcis årsag. Embryosum er 50.000 og negative ressourcer afvises. Samme fixture giver samme state.

#### Ved problemer

Brug statiske Resources og korte tabeller; procedurale planeter indføres ikke.

<!-- side 32 -->

## Fase 1 · GA-05 til GA-06

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-05 · Stjernekort og transaktionel rejse

**Afhængigheder:** GA-03, GA-04.  
**Ændringsområde:** scenes/ui/starmap/; scripts/domain/travel/.

#### Udfør

Vis tre destinationer, reelle omkostninger og minimumsreserve. Implementér RequestTravel med idempotens og et kort assisteret indflyvningssegment. Commit rejsen på ét punkt og opdatér location efter succes.

#### Acceptprøve

Dobbelklik og load ved ankomst kan ikke bruge fuel to gange. Utilstrækkelig reserve giver forklaring før valg. Spilleren kan assistere flyvesegmentet.

#### Ved problemer

Er manuel flyvning ustabil, behold en kontrolleret orbital tilgang og den fulde rejsebeslutning.

### GA-06 · Probe, prøve og planetviden

**Afhængigheder:** GA-04, GA-05.  
**Ændringsområde:** scripts/domain/survey/; scenes/surface/; data/surveys/.

#### Udfør

Opret tre surveyhandlinger med pris og observation. Byg én 6-minutters gråbloksekspedition med to ruter, suit-energy og hjemvej. Prøven opdaterer kun relevante sitefelter og gemmer kilde.

#### Acceptprøve

Scouting indsnævrer et interval og betaler én gang. Udtømt dragt udløser varslet tilbagevending/checkpoint, ikke en tavs kampagnelås.

#### Ved problemer

Fjern tilfældige hændelser; bevar én forståelig fare og én værdifuld observation.

<!-- side 33 -->

## Fase 1 · GA-07 til GA-08

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-07 · Landing og vedvarende kolonistart

**Afhængigheder:** GA-05, GA-06.  
**Ændringsområde:** scripts/domain/landing/; scenes/colony/; tests/.

#### Udfør

Lav landingspreview med kendte risici, startinventar og pre-landing save-hook. CommitLanding skifter phase én gang, placerer arkkerne og opretter ColonyState med valgt biome/site.

#### Acceptprøve

Gentagen landing giver ikke dobbelt ressourcer eller ekstra ark. Tilbage/annuller ændrer ingen state. Den valgte planet bestemmer biomeparametre.

#### Ved problemer

Brug en kort skærmovergang; dyr landingscinematic er ikke en afhængighed.

### GA-08 · Robotbyggeri og første forsyningsnet

**Afhængigheder:** GA-07.  
**Ændringsområde:** scripts/domain/colony/; scenes/buildings/; data/buildings/.

#### Udfør

Implementér ghostplacement, footprint, gangbar adgang, byggecost og robotarbejde. Lav solarray, vandanlæg og habitat plus arkens reserve. Beregn netstatus og forklar strøm-/adgangsfejl i UI.

#### Acceptprøve

Tre bygninger kan opføres, nedrives og gemmes uden resource exploit. Et afbrudt strømnet stopper korrekt output og viser årsagen.

#### Ved problemer

Start med et enkelt energinet og fælles lager; transportgrafen kan være en simpel valideret afstand.

<!-- side 34 -->

## Fase 1 · GA-09 til GA-10

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-09 · Incubation og kohortetest

**Afhængigheder:** GA-04, GA-08.  
**Ændringsområde:** scripts/domain/population/; fixtures/; tests/.

#### Udfør

Opret viable->incubating->born-overgange, omsorgskrav og alder. Blokér start uden forsyning og kapacitet. Lav en isoleret accelereret testfixture til fødsel og voksenalder; normal demo slutter ved robotkolonien.

#### Acceptprøve

Alle overgangsforløb bevarer 50.000-summen. En børnekohorte leverer ingen voksenarbejdskraft. Gentaget completion-event giver ingen ekstra fødsel.

#### Ved problemer

Hold tidsacceleration i testværktøj med tydelig debugmærkning; opfind ikke øjeblikkeligt voksne borgere.

### GA-10 · Save/load og genoprettelse

**Afhængigheder:** GA-05, GA-07, GA-08, GA-09.  
**Ændringsområde:** scripts/persistence/; tests/save/; fixtures/saves/.

#### Udfør

Implementér envelope, validering, backup og restore-rækkefølge. Gem ArkState, observationer, kolonibygninger, kohorter og RNG. Lav corrupt-save og interrupted-write fixtures.

#### Acceptprøve

Roundtrip bevarer alle nøgletal og IDs. Korrupt hovedfil tilbyder gyldig backup. Restore affyrer ingen incubation-, landing- eller rewardevents igen.

#### Ved problemer

Gem kun på konsistente checkpoints før frie mid-action saves; dokumentér begrænsningen.

<!-- side 35 -->

## Fase 1 · GA-11 til GA-12

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-11 · Saml 20-minutters demo og læsbarhed

**Afhængigheder:** GA-02, GA-03, GA-05, GA-06, GA-07, GA-08, GA-10.  
**Ændringsområde:** scenes/ui/; scenes/demo/; evidence/.

#### Udfør

Forbind ny kampagne til robotkoloni med tydelige objectives. Lav kompakt HUD, pause, fejlbeskeder og placeholderlyd. Fjern debuggenveje fra spillerflow. Optag én hel gennemspilning og ret de tre største friktioner.

#### Acceptprøve

Hele demoen kan afsluttes og load fortsætter korrekt. Alle kritiske beslutninger viser pris og konsekvens. Ingen P0/P1-fejl er åbne.

#### Ved problemer

Skær ekstra prøver og dekoration, ikke rejsevalg eller koloniens forsyningsfeedback.

### GA-12 · Fase 1-port og eksport

**Afhængigheder:** GA-01, GA-02, GA-03, GA-04, GA-05, GA-06, GA-07, GA-08, GA-09, GA-10, GA-11.  
**Ændringsområde:** builds/; evidence/GA-12/; docs/STATUS.md.

#### Udfør

Byg native desktopversion, kør demo fra rent startstate og genkør domæne-/savetests. Registrér proxyassets og visuelle blokeringer. Pak test-save, logs og næste opgaver. Lav fase 1-tag.

#### Acceptprøve

Gate 1 opfyldt med build-ID og faktiske beviser. Hvis eksport eller visuel test mangler, er porten ikke DONE, og årsagen er eksplicit.

#### Ved problemer

Fortsæt mulige datatests ved miljøstop; markér ikke en scriptsamling som spilbar demo.

<!-- side 36 -->

## Fase 2 · GA-13 til GA-14

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-13 · Hjemkomstaudit og Synty-basiskit

**Afhængigheder:** GA-12.  
**Ændringsområde:** assets/; art/prefabs/; docs/ASSET_LEDGER.csv.

#### Udfør

Kontrollér fuld værktøjskæde og actual assetpaths. Importér ét skibsmodul, én humanoid og én terrænprøve. Lav wrappers, skala/collision og materialepalette. Sammenlign med feriedemo før bred udskiftning.

#### Acceptprøve

Synty-scener kører på låst engine, navigation og save-ID’er er uændrede. Sourcehash og screenshot ved gameplaykamera er gemt.

#### Ved problemer

Ret import i isoleret RigLab; behold proxyversion som rollback.

### GA-14 · Kaptajnens færdige animationskerne

**Afhængigheder:** GA-13.  
**Ændringsområde:** scenes/tests/RigLab.tscn; art/animations/; scripts/runtime/.

#### Udfør

Normalisér rig, in-place locomotion, turn, interact, sample og suit-reaction. Opsæt AnimationTree med afbrydelser og manifest. Test kontaktpunkt ved terminal og prøvetagning.

#### Acceptprøve

Gang/løb/stop og interaktion har korrekt fodfæste, greb og eventtid i galleri samt ekspedition. Pause/restore giver ingen posesnap eller dobbeltsample.

#### Ved problemer

Skær kompleks hånd-IK; ret clip, rig og socket før mere avanceret runtimekorrektion.

<!-- side 37 -->

## Fase 2 · GA-15 til GA-16

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-15 · Seks planetprofiler og sammenligning

**Afhængigheder:** GA-04, GA-06, GA-12.  
**Ændringsområde:** data/planets/; scenes/ui/planet_compare/; tests/.

#### Udfør

Udvid til seks navngivne kandidater og tre sites pr. biomekort. Indfør tre niveauer af viden og valider alle rejseomkostninger. Lav automatiske tests af mindst én levedygtig strategi pr. planet.

#### Acceptprøve

Ingen universel bedste planet i alle felter. Alle kandidater har en mulig landings-/koloniplan; surveykilde og usikkerhed fremgår.

#### Ved problemer

Balancer ud fra data; lav ikke seks unikke open worlds for at skabe forskel.

### GA-16 · Komplet økonomi og tolv byggeklasser

**Afhængigheder:** GA-08, GA-12.  
**Ændringsområde:** data/buildings/; scripts/domain/economy/; tests/.

#### Udfør

Tilføj alle 12 byggeklasser, workforce, upkeep, batterilagring og biometilpasninger. Vis reserve i persondøgn og prioriteret strømafbrydelse. Test cancel, rebuild og resource reservation.

#### Acceptprøve

Ingen negativ lagerbeholdning eller uendelig genbrugsgevinst. Kritiske systemer prioriteres korrekt. Hver bygning har én tydelig nødvendig funktion.

#### Ved problemer

Fjern overflødige varianter; behold klare basiskæder og målbare biomeforskelle.

<!-- side 38 -->

## Fase 2 · GA-17 til GA-18

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-17 · Omsorgsloop og første menneskelige scene

**Afhængigheder:** GA-09, GA-14, GA-16.  
**Ændringsområde:** scripts/domain/population/; scenes/story/; data/events/.

#### Udfør

Tilføj første kohorte, pleje/uddannelse og varslede behov. Skab en kort håndskrevet scene med kaptajn, AI og et fremtidsperspektiv. Lad omsorg være afhængig af fungerende koloni, ikke af et videoklip.

#### Acceptprøve

Spilleren kan forklare kravene til første fødsel. Forsyningssvigt stopper farlige fremskridt med forklaring. Cohortstatus overlever save/load.

#### Ved problemer

Brug lys, lyd og tekst frem for ansigtsrig og lange cinematics.

### GA-18 · Tre biomeudsnit og farer

**Afhængigheder:** GA-13, GA-15, GA-16.  
**Ændringsområde:** scenes/biomes/; data/hazards/; art/.

#### Udfør

Byg grøn-, ørken- og isgreybox til samme interface. Tilføj én central fare og én specifik koloniløsning pr. biome. Dressing følger først efter kontrol af ruter, landingssites og forsyningsafstande.

#### Acceptprøve

Spore, støv og kulde giver forskellige beslutninger. Alle sites kan navigeres og landes på uden skjulte dead ends. Fare er synlig uden lyd.

#### Ved problemer

Genbrug modulære terrænelementer; fokuser på forskellige funktionelle layouts.

<!-- side 39 -->

## Fase 2 · GA-19 til GA-20

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-19 · UI, lyd og 45-minutters spiltest

**Afhængigheder:** GA-14, GA-15, GA-16, GA-17, GA-18.  
**Ændringsområde:** scenes/ui/; audio/; evidence/playtest/.

#### Udfør

Saml kvalitetsudsnit med undertekster, skalerbar UI og lydprioriteter. Test planettradeoff og incubationforståelse med eksterne testere hvis tilgængelige. Registrér observationer og ret konkrete misforståelser.

#### Acceptprøve

Fire af fem testere finder første mål; tre beskriver et varigt planettradeoff. Manglende testere registreres som udestående, ikke simuleret evidens.

#### Ved problemer

Agentens walkthrough kan fange bugs, men erstatter ikke spillerbevis for sjov og forståelse.

### GA-20 · Fase 2-port og contentlås

**Afhængigheder:** GA-13, GA-14, GA-15, GA-16, GA-17, GA-18, GA-19.  
**Ændringsområde:** docs/; builds/; evidence/GA-20/.

#### Udfør

Kør kvalitetsudsnittet, profiler referencehardware og fastfrys data/interfaces. Dokumentér præcis contentliste og åbne P2-forhold. Opret tag og fixtures til resten af kampagnen.

#### Acceptprøve

Gate 2 er opfyldt: Synty/animation godkendt, seks valg fungerer, første kohorte er meningsfuld og buildet har ingen P0/P1.

#### Ved problemer

Udskyd indholdsproduktion ved svag kerne; reparér planetvalg eller koloniforståelse først.

<!-- side 40 -->

## Fase 3 · GA-21 til GA-22

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-21 · Era-simulator og sikre tidsspring

**Afhængigheder:** GA-20.  
**Ændringsområde:** scripts/domain/era/; tests/era/; fixtures/.

#### Udfør

Implementér deterministiske intervalberegninger for forbrug, aldring, upkeep og arbejdskraft. Stop før næste kritiske hændelse/underskud. Vis prognose, plan og resultat før commit.

#### Acceptprøve

År 20/40 kan nås uden dag-for-dag scene-simulation. Samme fixture giver samme resultat. Simulatoren springer ikke over en uløst kritisk krise.

#### Ved problemer

Brug kohorter og analytiske intervaller; simuler ikke alle fremtidige mennesker individuelt.

### GA-22 · Akt I og seks scoutingproblemer

**Afhængigheder:** GA-20.  
**Ændringsområde:** data/missions/act_1/; scenes/survey/.

#### Udfør

Skriv og implementér seks surveyproblemer på tre biomekort. Hvert har hovedprøve, valgfri risiko og tydelig evakuering. Forbind dem til rejse- og videnmodellen uden at kræve alle seks i en kampagne.

#### Acceptprøve

Alle surveys afsluttes, afbrydes og genoptages lovligt. Valgfrie prøver ændrer faktisk viden, ikke kun journaltekst.

#### Ved problemer

Genbrug korttopologi med nye mål; undgå seks uafhængige store baner.

<!-- side 41 -->

## Fase 3 · GA-23 til GA-24

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-23 · Akt II og ni krise-/borgerbegivenheder

**Afhængigheder:** GA-17, GA-20.  
**Ændringsområde:** data/events/; scripts/domain/events/; scenes/ui/.

#### Udfør

Byg tre biomespecifikke kriser og seks omsorgs-/samfundsbegivenheder. Hver definerer trigger, varsel, valgmuligheder, cost, effect og fallback. Vis menneskelige konsekvenser i korte håndskrevne scener.

#### Acceptprøve

Ingen event kræver en tabt engangsressource uden alternativ. Hver løsning har et synligt resultat og anvendes højst én gang.

#### Ved problemer

Reducer tekstmængde, ikke konsekvens. Uafklarede events skal standse tidsspring.

### GA-24 · Akt III, råd og overdragelse

**Afhængigheder:** GA-21, GA-23.  
**Ændringsområde:** scripts/domain/society/; data/story/act_3/.

#### Udfør

Indfør de første voksnes tre perspektiver, trust og rådets forudsætninger. Knyt valg til arkafhængighed, robusthed og ekspansion. Byg finaleobjective om 500 indbyggere og institutionsstabilitet.

#### Acceptprøve

Råd kan ikke opstå før voksne kohorter. Samfundets behov og overdragelseskriterier er forklaret. Ingen usynlig moralsk score styrer slutningen alene.

#### Ved problemer

Hold dialogsystemet lineært med dataforgreninger; ingen generativ NPC-chat som runtimekrav.

<!-- side 42 -->

## Fase 3 · GA-25 til GA-26

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-25 · Tre afslutninger og epilog

**Afhængigheder:** GA-24.  
**Ændringsområde:** data/endings/; scenes/story/ending/; tests/.

#### Udfør

Definér kriterier for selvstændig, skærmet og skrøbelig civilisation. Lav epilog, der refererer til planet, kriser, kohorter og institutionsvalg. Gem final_state og tilbyd fortsættelse fra pre-ending save.

#### Acceptprøve

Tre målrettede fixtures udløser hver sin korrekte profil. Samme save giver samme epilog; ingen modstridende planet- eller befolkningstal.

#### Ved problemer

Brug stærk art/lyd/tekst og ingamekamera frem for store specialproducerede film.

### GA-26 · Alle biomekort og artpass

**Afhængigheder:** GA-18, GA-20, GA-22.  
**Ændringsområde:** scenes/biomes/; art/prefabs/; lighting/.

#### Udfør

Færdiggør tre koloniregioner med tre sites hver, landmærker, collision og artpalette. Kontrollér alle byggefootprints og kameraer. Tilføj kun props, der støtter orientering eller fortælling.

#### Acceptprøve

Alle ni sites understøtter startbygninger og levedygtig progression. Ingen pynt blokerer kritiske paths eller skjuler interaktion.

#### Ved problemer

Reducer propdensitet og genbrug materialer, før performance kræver store systemomskrivninger.

<!-- side 43 -->

## Fase 3 · GA-27 til GA-28

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-27 · Borgere, robotter og lydidentitet

**Afhængigheder:** GA-14, GA-17, GA-24.  
**Ændringsområde:** scenes/actors/; audio/; scripts/runtime/crowd/.

#### Udfør

Tilføj repræsentative borgere med kohortetilknytning, robotarbejdsloops og variation. Begræns synlige borgere og opdatering. Udbyg lyd fra ensom ark til beboet koloni.

#### Acceptprøve

Synlige aktører ændrer ikke autoritativ population. Crowd undgår kritiske indgange; animationer og lyd kan reduceres uden tab af information.

#### Ved problemer

Brug få gode loops og sceneprioritering; ingen fuld hverdags-AI til hvert menneske.

### GA-28 · Balance af seks verdener

**Afhængigheder:** GA-21, GA-23, GA-25, GA-26.  
**Ændringsområde:** tools/balance/; fixtures/strategies/; data/.

#### Udfør

Kør mindst tre strategier på hver kandidat. Mål reserver, krisetid, arkafhængighed og slutprofil. Justér data i små sammenlignelige ændringer og spil mindst én fuld kampagne på hvert biome.

#### Acceptprøve

Alle seks kan gennemføres på standard. Ingen kandidat dominerer alle strategier. Ingen skjult ressourcefælde før nødvendig teknologi.

#### Ved problemer

Skift én variabelgruppe ad gangen og behold baselinefixtures til sammenligning.

<!-- side 44 -->

## Fase 3 · GA-29 til GA-30

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-29 · Robusthed, accessibility og performance

**Afhængigheder:** GA-26, GA-27, GA-28.  
**Ændringsområde:** settings/; tests/; tools/profile/.

#### Udfør

Test UI-skalering, remap, lydløst spil og reduceret motion. Profilér rejse, ekspedition, koloni og era-hop. Test gammel savefixture efter contentændringer og stress af build/cancel.

#### Acceptprøve

Referencebudget er opfyldt eller ærligt revideret med dokumenteret lav profil. Ingen tab af data ved migration, og kritiske alarmer har visuelle alternativer.

#### Ved problemer

Optimer målt flaskehals; undgå ny engineversion eller threading midt i contentlås.

### GA-30 · Fase 3-port: fuld kampagne

**Afhængigheder:** GA-21, GA-22, GA-23, GA-24, GA-25, GA-26, GA-27, GA-28, GA-29.  
**Ændringsområde:** builds/; evidence/GA-30/; docs/.

#### Udfør

Gennemspil start->overdragelse uden debug, plus fixtures til de to øvrige slutprofiler. Kontrollér contentloft, credits og kendte fejl. Fastfrys featurelisten.

#### Acceptprøve

Gate 3 opfyldt med fuld kampagne, alle planeter/biomer og tre korrekt beregnede afslutninger. Ingen P0/P1.

#### Ved problemer

Fjern ufærdige valgfri features i et dokumenteret cut; behold kampagnens hovedløfte.

<!-- side 45 -->

## Fase 4 · GA-31 til GA-32

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-31 · Ekstern beta og prioriteter

**Afhængigheder:** GA-30.  
**Ændringsområde:** evidence/beta/; docs/feedback/.

#### Udfør

Pak en privat testbuild og instruktion uden spoilers. Indsaml sessionlængde, første blokering, planetvalg og forståelse af generationer, når testadgang er godkendt. Triagér efter observeret problem.

#### Acceptprøve

Alle P0/P1 er reproduceret eller tydeligt afkræftet med bevis. Feedback er adskilt fra agentens egne antagelser.

#### Ved problemer

Hvis testere mangler, hold releaseporten åben og færdiggør øvrig QA; opfind ikke resultater.

### GA-32 · Bugfix og finale-polish

**Afhængigheder:** GA-31.  
**Ændringsområde:** scripts/; scenes/; tests/regression/.

#### Udfør

Ret prioriterede fejl i små commits med regressionsfixture. Gennemgå overgangene ark->planet->koloni->era->epilog. Finpuds tone, alarmsystem og ventetid uden nye systemer.

#### Acceptprøve

Alle beta-P0/P1 lukket med retest. Ingen nye savebrud. Tidsspring og epilog har tydelig konsekvens uden unødig venten.

#### Ved problemer

Rollback et risikabelt fix hvis det bryder flere stabile flows; lav en mindre rettelse.

<!-- side 46 -->

## Fase 4 · GA-33 til GA-34

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-33 · Udgivelsesdata, indstillinger og rettigheder

**Afhængigheder:** GA-30.  
**Ændringsområde:** docs/release/; localization/; credits/.

#### Udfør

Kontrollér asset/animation/audio-ledger mod faktisk build. Gennemgå tekst, credits, remap og settings persistence. Definér supporterede platforme og kendte begrænsninger ud fra tests.

#### Acceptprøve

Ingen rå købte sourcepakker følger offentlig levering. Alle shipped assets har kilde og afklaret brug. Indstillinger overlever restart.

#### Ved problemer

Erstat et uafklaret asset med et allerede godkendt alternativ; stop ikke hele projektet unødigt.

### GA-34 · Demo, trailer og salgssidegrundlag

**Afhængigheder:** GA-32, GA-33.  
**Ændringsområde:** docs/store/; captures/; builds/demo/.

#### Udfør

Lav en afgrænset demo til robotkoloni og optag faktisk progression. Skriv pitch, features og systemkrav baseret på build. Vis forskelle mellem tre planeter og kolonien over tid.

#### Acceptprøve

Alle påstande kan demonstreres i den angivne build. Video er gameplay, ikke genereret dokumentation. Demo har klar slutning og savegrænse.

#### Ved problemer

Skær løfter om fremtidige funktioner; sælg den oplevelse, der faktisk er færdig.

<!-- side 47 -->

## Fase 4 · GA-35 til GA-36

Aflevering: commit + faktiske testresultater + relevant billede/video + opdateret STATUS. Porten til næste fase skal være bestået.

### GA-35 · Ren releasekandidat og rollback

**Afhængigheder:** GA-32, GA-33, GA-34.  
**Ændringsområde:** tools/release/; builds/rc/; evidence/.

#### Udfør

Eksportér fra rent checkout på låst engine. Kør fuld smoke, save migration og mindst én kampagne. Pak checksum, versionsnoter, install-/startvejledning og forrige kandidat til rollback.

#### Acceptprøve

Gate 4 teknisk bestået: ren opstart, gyldige saves, ingen P0/P1 og verificeret runtimepakke. Publicering er ikke implicit udført.

#### Ved problemer

Ved forskel mellem editor og eksport laves en minimal eksportreproduktion før øvrige ændringer.

### GA-36 · Overdragelse og vedligeholdelsesplan

**Afhængigheder:** GA-35.  
**Ændringsområde:** docs/RELEASE_HANDOFF.md; docs/STATUS.md.

#### Udfør

Aflevér build, beviser, bugstatus, assetledger og startordre til næste kørsel. Lav en 30-dages prioriteret plan for bugs, support og måling af demo-/salgsinteresse. Notér alle handlinger, der stadig kræver faktisk adgang.

#### Acceptprøve

En ny agent kan bygge, teste og lokalisere saveformat uden samtalehistorik. Slutstatus skelner klart mellem RC_READY og faktisk offentlig udgivelse.

#### Ved problemer

Stop ved manglende offentliggørelsesmandat efter at have gjort releasepakken fuldt reviewklar.

<!-- side 48 -->

## Maskinlæsbar arbejds- og beviskontrakt

Startpakken spejler biblen. Den indeholder plan og skabeloner, ikke en skjult færdig spilimplementation.

### tasks.json

Liste med id, phase, title, depends_on, status, owner, paths, steps, acceptance, fallback, evidence og last_commit. Første status er TODO. Den leverede validate_plan.py kontrollerer unikke ID’er, afhængigheder, cykler, 36 kort og fire faser. Værktøjet kan vise næste READY-kandidater; det starter ikke agenter og beviser ikke gameplay.

### STATUS.md

Felter: project, spec_version, engine_version, profile HOLIDAY/FULL, current_phase, last_passed_gate, active_task, last_commit, tests_run, blockers, next_three_tasks og next_command. Alle faktiske resultater opdateres ved checkpoint. Ingen håndoff må nøjes med formuleringen fortsæt hvor vi slap.

### Evidence og assetmanifest

result.json: task_id, commit, engine_version, command, exit_code, expected, observed, fixture, status og artifacts. Assetledger: asset_id, source_pack, source_path, checksum, format, rig_id, scale_m, target_scene, rights_status, review_status. Animationledger: clip_id, source_asset_id, rig_id, state, duration_s, loop, in_place, event_times og review_status.

### Praktisk filprioritet

Brugerens seneste instruktioner og repositoryets gældende sikkerhedsregler går først. Biblen definerer baseline. DECISIONS.md dokumenterer begrundede ændringer. tasks.json er aktuel opgavestatus, ikke en mulighed for at fjerne acceptkrav uden beslutning. En uoverensstemmelse rettes i begge kilder ved samme commit.

> Pakken indeholder START_HERE.md, AGENTS.md, CLAUDE.md, den fulde bibel i Markdown og PDF, tasks.json, skabeloner og planvalidator. Læsbare PDF-opgavekort gør også PDF’en tilstrækkelig som selvstændig overdragelse.

<!-- side 49 -->

## Startordrer: ferie, genoptagelse og hjemkomst

Kopiér den relevante ordre til Codex eller Claude Code. Navnet på agenten ændrer ikke arbejdsmetoden.

### Start nu · dag 1

Du er ansvarlig for GENESIS ARK. Læs hele denne bibel og eventuelle gældende repositoryinstruktioner. Byg i et selvstændigt Godot-projekt. Dag 1-7 arbejder du alene uden underagenter. Start med GA-01 og miljøaudit, opret opgavefilerne hvis du kun har PDF’en, og fortsæt gennem READY-opgaver. Brug Synty, når de faktiske filer findes; ellers registrerede proxies. Tag reversible beslutninger selv. Kør tests, gem ærlige beviser og commit ved hver afsluttet opgave. Fortsæt uden at bede mig om godkendelse ved hvert skridt. Stop kun ved en reel blokering uden lovligt alternativ, manglende nødvendigt mandat eller sessionens faktiske grænse.

### Genoptag efter afbrydelse

Fortsæt GENESIS ARK. Læs mandat, STATUS.md, DECISIONS.md og tasks.json. Kontrollér Git-status og seneste commit. Beskyt eksisterende ændringer. Reproducer sidste kendte fejl eller kør den mindste relevante smoke. Vælg næste READY-opgave med opfyldte afhængigheder og faseport. Gentag ikke afsluttet arbejde uden konkret regression. Gem nyt checkpoint før sessionen slutter.

### Hjemkomst · dag 8+

Fortsæt det samme GENESIS ARK-repository. Auditér tilgængelig værktøjskæde, importér rigtige assets gennem den beskrevne pipeline, og genverificér feriebuilden. Du er koordinator. Brug højst to afgrænsede specialister samtidig, hvis adgang og mandat tillader det; én integrationsansvarlig og ingen overlappende filskrivning. Færdiggør fase 1-porten, hvis noget står åbent, og fortsæt derefter mod kvalitetsudsnit, komplet kampagne og releasekandidat.

### Definition af færdig

Projektet er RC_READY, når fase 4’s tekniske krav, dokumentation og reviewpakke er bestået med reelle beviser. Publiceret betyder derudover faktisk gennemført offentlig udgivelse. Brug aldrig færdig om en mappe med scripts, som ikke er importeret, spillet og eksporteret.

<!-- side 50 -->

## Kilder, antagelser og teknisk grundlag

Officielle kilder er kontrolleret under udarbejdelsen 16. oktober 2026. Den valgte engineversion skal stadig låses ved projektstart.

### R1 · Godot: import af 3D-scener

https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html

glTF/GLB og FBX; importerafhængigheder kontrolleres på den låste version.

### R2 · Godot: retargeting

https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html

BoneMap, SkeletonProfileHumanoid, rest pose og motion scale.

### R3 · Godot: AnimationTree

https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html

AnimationPlayer rummer clips; AnimationTree blander og styrer tilstande.

### R4 · Godot: NavigationAgent

https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html

Stifinding, avoidance og fysik er forskellige systemer.

### Brugergrundlag

Godot, Synty, syv feriedage, selvstændig kodeagent i første uge og fuld værktøjskæde efter hjemkomst er brugerens krav. Genrevalg og indholdslofter er denne bibels konkrete anbefalinger. De viste sci-fi-referencebilleder bruges som retning for stiliseret geometri, industriel farve og læsbar HUD; de er ikke inkluderede licenserede spilassets.

<!-- side 51 -->

## Kilder og erfaringer, der skal genverificeres

En gammel plan er værdifuld erfaring, men ikke en testkvittering for et nyt spil.

### R5 · Godot: kommandolinje

https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html

Headless import, scripts og eksport; flags kontrolleres med --help.

### R6 · Godot: save games

https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html

Grundlag for egen versioneret, valideret save-kontrakt.

### R7 · Synty: FAQ

https://syntystore.com/en-gb/community/faq

Assetformater, pakkeindhold og tilgængelige leverancer kontrolleres per køb.

### R8 · Godot: webeksport

https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html

Web er en valgfri særskilt eksport; desktop er målplatformen.

### Tidligere dokumenterede animationsprincipper

EDEN9_QWEN_AUTONOMOUS_MASTER_v2.0.md, afsnit 4.3 og 4.8-4.9, læst som brugerens tidligere projektgrundlag: canonical rig, in-place som standard, eventtiming, sockets, stilkontrol, gallery og gameplayreview. Konkrete lokale rigs, clips, adgangsforhold og tidligere rettelser er ikke verificeret i disse nye projekter. Derfor indgår de som kontrolopgaver, ikke som påstand om allerede løste problemer.

### Status og kommerciel nøgternhed

Der følger ingen købte assets, hemmelige nøgler eller færdigimplementerede spil med dokumentpakken. Priser, varigheder, budgetter og efterspørgsel er hypoteser. Kvalitet, spillerinteresse og kommercielt potentiale undersøges gennem et rigtigt kvalitetsudsnit og spillerprøver. Biblen giver en vej til et stærkt produkt; den kan ikke garantere indtjening.
