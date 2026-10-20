# Text pass (GA-22..25): changed player-facing lines

English is the source language (D-025). Every changed English key was moved in `localization/translations.csv`
(`tools/loc_extract.py`) and its Danish column filled from the line it replaced, adjusted where the meaning changed.
`docs/VO_SCRIPT.csv` was regenerated with `tools/export_vo_script.py`. No ids, numbers, effects or logic changed;
all placeholders are preserved (`route_belt` additionally uses `{dest}`, which NavAdvisor already supplies).

## Lines changed per file

| File | Lines |
|---|---|
| `data/story/scenes.json` | 14 |
| `data/story/journal.json` | 2 |
| `data/story/nav.json` | 12 |
| `data/events/crises.json` | 12 |
| `data/events/civic.json` | 5 |
| `data/endings/endings.json` | 2 |
| `data/objectives/objectives.json` | 4 |
| `data/surveys/ferrum.json` | 4 |
| `data/surveys/nivalis.json` | 1 |
| `data/surveys/pelagos.json` | 1 |
| `data/surveys/umbra.json` | 1 |
| `data/surveys/viridia.json` | 3 |
| `data/planets/ferrum.json` | 1 |
| `scripts/domain/population/population_service.gd` | 1 |
| **Total** | **63** |

## Voice and terminology rules applied

- **ARK** (ship intelligence): calm, warm, personal; contractions are fine ("I've noted it"), never a status readout when speaking to the captain.
- **NAV** (navigation computer): `Label: value unit.` reports, every number has its unit, no feelings, no "I"; instructions are technical ("increase reaction time"). Route lines share one shape: `Approach to {dest}: <hazard>. Expected ...`.
- **Captain** in direct address is capitalized ("Welcome back, Captain"); "the captain" in narration stays lowercase.
- **Habitat** is the building where people live; "housing" no longer stands in for it in event text.
- **Care center** is the short form of *Care and incubation center*; never just "the center".
- **School and town hall** is the building name (no "school/town hall"); "school hall" remains as the colloquial name in story/epilogue prose.
- **Components** is the resource name in option descriptions whenever the option's cost is components (not "spare parts").
- **Heating module** / **Filter module** (never "heater module").
- **Lander** for the expedition craft (already consistent); **route** for paths on the surface and in space.
- Survey titles and hazard-zone labels use sentence case; named places ("The Fungal Rim") stay in title case.
- Toast/subtitle lines kept at or below ~145 characters where shown with a timer (evacuation toasts).
- American spelling (analyze, gray, toward, meters) — no British spellings were found.

## `data/story/scenes.json`

| Id / key | Before | After | Why |
|---|---|---|---|
| scene_starmap_first #5 (ARK) | We'll have to work that out. It costs something every time. | We'll have to find out. And every answer costs something. | Clearer answer to the captain's question; avoids vague 'work that out'. |
| scene_probe_result #2 (ARK) | That doesn't make the choice easier. Only more your own. | That doesn't make the choice easier. Only more yours. | Idiom: 'more your own' reads as a mistranslation. |
| scene_probe_result #4 (ARK) | I have numbers, captain. You have the responsibility. It's not the same. | I have numbers, Captain. You have the responsibility. It's not the same. | Rank used in direct address is capitalized (consistent with 'Captain. You're awake.'). |
| scene_arrival_orbit #4 (ARK) | I can't measure that. But I have noted it. | I can't measure that. But I've noted it. | ARK voice: warm and personal, not clipped. |
| scene_expedition_start #3 (ARK) | The sample site is marked. There are two ways there. The short one isn't the safe one. | The sample site is marked. There are two routes. The short one isn't the safe one. | Terminology: the UI calls them routes; 'two ways there' was clumsy. |
| scene_landing_commit #2 (ARK) | The Ark becomes the colony's base. The emergency power, the drones, you. | The Ark becomes the colony's base. Its emergency power, its drones. And you. | Fragment read like a list; 'its ... And you' lands the personal beat. |
| scene_incubation_start #2 (ARK) | Ten embryos can begin incubation. You are the one who starts it. | Ten embryos are ready for incubation. You should be the one to start it. | Stiff phrasing; sets up 'Why not you?' more naturally. |
| scene_captain_stasis #2 (ARK) | You've been awake a long time, captain. Stasis gives you more years with them later. | You've been awake a long time, Captain. Stasis gives you more years with them later. | Capitalize rank in direct address. |
| scene_captain_stasis #4 (ARK) | I do. And when they have something to show you. | I will. And when they have something to show you. | Grammar: reply to 'Wake me if...' must be future ('I will'). |
| scene_crisis_survived #1 (NARRATOR) | The alarm goes quiet. For the first time in days, the control room is silent. | The alarm stops. For the first time in days, the control room is silent. | Removes quiet/silent repetition. |
| scene_year_20 #2 (ARK) | Welcome back, captain. A lot has happened. | Welcome back, Captain. A lot has happened. | Capitalize rank in direct address. |
| scene_year_20 #6 (ARK) | They've been waiting for you. I think they're waiting for an answer. | They've been waiting for you. I think what they want is an answer. | Removes 'waiting ... waiting' repetition. |
| scene_year_40 #3 (elias) | We've run the numbers. We can manage without — almost. | We've run the numbers. We can manage without it. Almost. | 'manage without' needs an object; the pause sets up Noor's 'Almost is enough'. |
| scene_year_40 #5 (sana) | It's not your choice anymore, captain. But we'd like you to be here when we make it. | It's not your choice anymore, Captain. But we'd like you to be here when we make it. | Capitalize rank in direct address. |

## `data/story/journal.json`

| Id / key | Before | After | Why |
|---|---|---|---|
| journal_arrival_sere | Sere. Flat and friendly from orbit. The dust looks harmless from up here. | Sere. Flat and friendly. From up here, the dust looks harmless. | Removes 'from orbit ... from up here' repetition. |
| journal_expedition_complete | The samples are analyzed. We know more. We never know enough. | Back aboard. We know more than we did this morning. We'll never know enough. | Duplicated ARK's line in the same scene word for word; now the captain's own voice. |

## `data/story/nav.json`

| Id / key | Before | After | Why |
|---|---|---|---|
| route_field | The approach to {dest} has scattered asteroids. Expected: {hits_manual} impacts on manual control, {hits_auto} on autopilot. The autopilot uses {fuel_auto} extra units of fuel. | Approach to {dest}: scattered asteroids. Expected impacts: {hits_manual} manual, {hits_auto} on autopilot. Autopilot cost: {fuel_auto} additional fuel units. | NAV report format (label: value), shorter (176 -> 150 chars), parallel with debris/belt. |
| route_debris | The approach to {dest} passes a debris field. Expected hull loss: {integ_manual} percent manual, {integ_auto} percent on autopilot. | Approach to {dest}: debris field. Expected hull loss: {integ_manual} percent manual, {integ_auto} percent on autopilot. | Same report format as the other route lines. |
| route_belt | The route crosses an asteroid belt. Density: {density} percent. Expected hull loss: {integ_manual} percent manual, {integ_auto} percent on autopilot. Autopilot recommended. | Approach to {dest}: asteroid belt, density {density} percent. Expected hull loss: {integ_manual} percent manual, {integ_auto} percent on autopilot. Autopilot recommended. | Names the destination like the other route lines; shorter. |
| route_reserve_breach | Reserve after arrival: {fuel_after}. To reach {reserve_target}: {reserve_needed} required. Landing is effectively final. | Fuel after arrival: {fuel_after} units. Required to reach {reserve_target}: {reserve_needed}. Landing will be effectively final. | Units and label order consistent with route_fuel; tense matches the star map warning. |
| route_oxygen | Oxygen used in stasis: {oxygen} percent. Oxygen reserve on arrival: {oxygen_after} percent. | Oxygen used in stasis: {oxygen} percent. Reserve on arrival: {oxygen_after} percent. | Removes repeated 'Oxygen'. |
| route_oxygen_low | Oxygen reserve on arrival: {oxygen_after} percent. That is below the recommended minimum of {low} percent. | Oxygen reserve on arrival: {oxygen_after} percent. Recommended minimum: {low} percent. | NAV voice: data, not prose. |
| status_oxygen_low | Oxygen reserve: {oxygen} percent. Below recommended minimum. The scrubbers can be repaired in the workshop. | Oxygen reserve: {oxygen} percent. Below the recommended minimum. Scrubber repair available in the workshop. | Article fix; NAV report phrasing. |
| status_oxygen_critical | Oxygen reserve: {oxygen} percent. Critical. At stasis consumption, reserve lasts {days_left} days. | Oxygen reserve: {oxygen} percent. Critical. At stasis consumption, the reserve lasts {days_left} days. | Missing article. |
| approach_field | Approach initiated. Scattered asteroids ahead. Reduce speed to allow time to turn. | Approach initiated. Scattered asteroids ahead. Reduce speed to increase reaction time. | NAV voice: technical instruction instead of conversational phrasing. |
| arrival | Orbit around {dest} established. Hull {integrity} percent. Fuel {fuel}. Oxygen {oxygen} percent. | Orbit around {dest} established. Hull {integrity} percent. Fuel {fuel} units. Oxygen {oxygen} percent. | Every value gets its unit, as in the other NAV lines. |
| surface_return_margin | Return margin is narrowing. Endurance {seconds} seconds. Return requires {return_s}. Consider your priorities. | Return margin is narrowing. Endurance: {seconds} seconds. Return requires {return_s} seconds. Consider your priorities. | Missing unit after {return_s}; label punctuation. |
| surface_return_now | Endurance {seconds} seconds. Return requires {return_s}. Turn back now. | Endurance: {seconds} seconds. Return requires {return_s} seconds. Turn back now. | Missing unit after {return_s}; label punctuation. |

## `data/events/crises.json`

| Id / key | Before | After | Why |
|---|---|---|---|
| crisis_spore_bloom.text | The forest is blooming. A yellow haze drifts over the colony, and the spores settle in air intakes and greenhouses. Without protection we lose the harvest, and the air in the housing grows heavy. | The forest is blooming. A yellow haze drifts over the colony, and the spores settle in air intakes and greenhouses. Without protection we lose the harvest, and the air in the habitats grows heavy. | Terminology: the building is the habitat. |
| crisis_spore_bloom.a.label | Run the filters at full | Run the filters at full power | Incomplete idiom. |
| crisis_spore_bloom.a.description | The filter module keeps the air clean in housing and greenhouses. Costs new filter bags. The harvest is saved. | The filter modules keep the air clean in the habitats and greenhouses. New filter bags cost components. The harvest is saved. | Terminology (habitats); names the actual cost resource. |
| crisis_spore_bloom.b.description | Build extra airlocks and keep the greenhouses separate. The food is saved, but the air in the housing turns bad for a week or so. | Build extra airlocks and keep the greenhouses separate. The food is saved, but the air in the habitats turns stale for a week or so. | Terminology (habitats); 'turns bad' -> 'turns stale'. |
| crisis_spore_bloom.b.result | The airlocks kept the spores out of the greenhouses. In the housing, people coughed for a week. | The airlocks kept the spores out of the greenhouses. In the habitats, people coughed for a week. | Terminology (habitats). |
| crisis_dust_storm.b.label | Send out cleaning crews | Send out the cleaning drones | The option uses drones, not people (children/adults don't do this work). |
| crisis_dust_storm.b.description | Drones and workshop keep the panels clean around the clock. Costs spare parts, but power holds. | Drones from the workshop keep the panels clean around the clock. Costs components, but the power holds. | Grammar; names the actual cost resource (components). |
| crisis_dust_storm.c.description | Do nothing and save power. Free now, but the dust wears on everything, and the panels yield less for a long time. | Do nothing and ride it out. Free now, but the dust wears on everything, and the panels yield less for a long time. | 'save power' contradicted the option (it costs no power and saves none). |
| crisis_dust_storm.c.result | When the storm settled, the dust lay a hand's breadth thick. It took two weeks to get the panels clean. | When the storm passed, the dust lay a hand's breadth thick. It took two weeks to get the panels clean. | Storms pass; dust settles. |
| crisis_deep_cold.text | The cold comes in waves. The pipes creak, and the water in the lines begins to freeze. Housing uses twice the usual heat, and the night is long. | The cold comes in waves. The pipes creak, and the water in the lines begins to freeze. The habitats need twice the usual heat, and the nights are long. | Terminology (habitats); smoother. |
| crisis_deep_cold.a.description | Heat from below ground is pumped straight into housing. Stable, but the generator wears. | Heat from below ground is pumped straight into the habitats. Stable, but hard on the generator. | Terminology; 'the generator wears' was unidiomatic. |
| crisis_deep_cold.b.description | The heating modules run at full power. Costs power from the reserve and a few spare parts. | The heating modules run at full power. Costs power from the reserve and a few components. | Names the actual cost resource. |

## `data/events/civic.json`

| Id / key | Before | After | Why |
|---|---|---|---|
| civic_first_night.a.description | Two drones move from construction to the center. The children do better, but construction slows. | Two drones move from construction to the care center. The children settle, but construction slows. | Full building name; 'do better' was vague. |
| civic_first_night.a.result | The center fell quiet. Construction lost a week. | The care center fell quiet. Construction lost a week. | Full building name. |
| civic_fever.text | A fever moves through the first cohort. ARK doesn't know the virus — it belongs to this planet. The youngest, a girl of seven months, won't eat. | A fever moves through the first cohort. ARK doesn't recognize the virus — it is native to this planet. The youngest, a girl of seven months, won't eat. | Idiom: 'know the virus / belongs to this planet'. |
| civic_fever.a.description | The clinic isolates and treats. Safe, but it costs medical components. | The clinic isolates and treats the sick. Safe, but it uses components for medical supplies. | Transitive verb needed an object; clarifies the cost. |
| civic_mine_accident.b.label | Drones only underground | Only drones underground | Word order: the rule is 'only drones', not 'drones only go underground'. |

## `data/endings/endings.json`

| Id / key | Before | After | Why |
|---|---|---|---|
| independent.epilogue[2] | The first cohort now teaches the fourth. The council has {council} members and meets in the old school hall. It is divided most of the time. As it should be. | The first cohort now teaches the fourth. The council has {council} members and meets in the old school hall. It disagrees most of the time. As it should be. | 'It is divided' reads as a crisis; 'disagrees' matches the warm tone. |
| shielded.epilogue[2] | The council raises it every year. The young from the latest cohorts want to build more generators at {site}. The elders will risk nothing. Both sides are right. | The council raises it every year. The young from the latest cohorts want to build more generators at {site}. The elders won't risk anything. Both sides are right. | More natural phrasing. |

## `data/objectives/objectives.json`

| Id / key | Before | After | Why |
|---|---|---|---|
| obj_expedition.hint | Choose a landing site and fly the lander down. Watch the suit's energy. | Choose a landing site and take the lander down. Watch the suit's energy. | The descent is not piloted by the player; 'fly' promised a mechanic that does not exist. |
| obj_school.hint | Build a school/town hall in the living zone once the first cohort is born. | Build the school and town hall in the living zone once the first cohort is born. | Terminology: building is 'School and town hall'. |
| obj_council.hint | The council gathers in the school/town hall once the first are adults. | The council meets in the school and town hall once the first cohort has grown up. | Terminology; 'the first are adults' was missing its noun. |
| obj_year_40_500.hint | Build reserves, more cohorts and less dependence on the Ark. | Build up reserves, start more cohorts and reduce dependence on the Ark. | Parallel verbs (you cannot 'build less dependence'). |

## `data/surveys/ferrum.json`

| Id / key | Before | After | Why |
|---|---|---|---|
| briefing | The rock glows in the midday sun, and the suit's cooling is already working. Somewhere beneath the ravine lies an aquifer. We need to know how deep it is before we build anything here. | The rock glows in the midday sun, and the suit's cooling is already working hard. Somewhere beneath the ravine lies an aquifer. We need to know how deep it is before we build anything here. | 'already working' was flat; the point is strain. |
| hazard_zones[0].label | Heat Flat | Heat flat | Hazard zone labels are sentence case (Dust plume, Cold pocket, Storm front, Dark zone). |
| evacuation | The suit's cooling is at its limit. ARK: “Find shade, captain, and walk slowly. The lander is waiting for you.” | The suit's cooling is at its limit. ARK: “Find shade, Captain, and walk slowly. The lander is waiting for you.” | Capitalize rank in direct address. |
| findings.main | Ferrum: The water lies deep. The water plant must be built first and have enough power. | Ferrum: The water lies deep. Build the water plant first, and give it enough power. | Passive, awkward 'must be built first and have'. |

## `data/surveys/nivalis.json`

| Id / key | Before | After | Why |
|---|---|---|---|
| evacuation | The suit spends all its power keeping you warm. ARK: “Keep moving, captain. Stay in the sun. The lander's heated cabin is on.” | The suit spends all its power keeping you warm. ARK: “Keep moving, Captain. Stay in the sun. The lander's cabin heating is on.” | A cabin isn't 'on'; capitalize rank in address. |

## `data/surveys/pelagos.json`

| Id / key | Before | After | Why |
|---|---|---|---|
| briefing | A storm front is rolling in from the sea within hours. The coast is fertile, but we don't know what lives in the tidal zone. Find out before the weather closes in. | A storm front is rolling in from the sea and will hit within hours. The coast is fertile, but we don't know what lives in the tidal zone. Find out before the weather closes in. | 'rolling in ... within hours' was ungrammatical. |

## `data/surveys/umbra.json`

| Id / key | Before | After | Why |
|---|---|---|---|
| evacuation | The suit shuts down everything that isn't keeping you alive. ARK: “I'm switching on the lander's floodlights. Walk toward the light, captain. Just toward the light.” | The suit shuts down everything that isn't keeping you alive. ARK: “I've lit the lander's floodlights. Walk toward the light, Captain. Just the light.” | Toast is shown 6 s: 165 -> 145 chars; capitalize rank in address. |

## `data/surveys/viridia.json`

| Id / key | Before | After | Why |
|---|---|---|---|
| title | Breath of the Hollow | Breath of the hollow | Survey titles are sentence case (Where the dust settles, Steam in the ice...). |
| hazard_zones[0].label | Spore Haze | Spore haze | Hazard zone labels are sentence case. |
| evacuation | The suit's filters are saturated, and energy is falling. ARK: “Turn back now, captain. The lander is lighting its beacon — follow the light home. The samples you have are saved.” | The suit's filters are clogged, and energy is falling. ARK: “Turn back now, Captain. Follow the lander's beacon home. Your samples are safe.” | Toast is shown 6 s: 178 -> 140 chars; capitalize rank in address. |

## `data/planets/ferrum.json`

| Id / key | Before | After | Why |
|---|---|---|---|
| price | Water must be drawn from deep and transported safely. | Water must be pumped up from deep underground. | 'drawn from deep and transported safely' was unclear; matches the survey finding (deep aquifer, pumps cost power). |

## `scripts/domain/population/population_service.gd`

| Id / key | Before | After | Why |
|---|---|---|---|
| Loc.t (incubation requirement) | The planet requires a habitat with a heater module. | The planet requires a habitat with a heating module. | Terminology: the module is called 'Heating module' everywhere else. |

## Verification

`tools/check.sh` (full, incl. campaign bot): `loc_exit=0 tests_exit=0 smoke_exit=0 touch_exit=0 campaign_exit=0`; `python3 tools/loc_extract.py --check`: 1150 keys, 0 new, 0 dropped, 0 untranslated.
