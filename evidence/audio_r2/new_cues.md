# New cues (D-064)

Generated with ElevenLabs Sound Effects (`tools/audio/eleven_sfx.py --only ...`, model eleven_text_to_sound_v2, prompt influence 0.45), normalised with `tools/audio/normalize.py`. Files are local only (gitignored).

| cue | bus | s | hook | prompt |
|---|---|---|---|---|
| `sfx_entry_roar_loop` | SFX | 10 | planet_descent.gd _update_fx | Spacecraft atmospheric re-entry heard from inside the cabin, roaring plasma buffeting against the heat shield, deep turbulent rumble with hissing wind shear, seamless loop |
| `sfx_cloud_punch` | SFX | 3 | planet_descent.gd _process | Small spacecraft punching through a thick cloud layer at high speed, deep muffled sonic whoomp, rushing wind whoosh that swells and quickly falls away |
| `sfx_retro_burst` | SFX | 2.5 | planet_descent.gd _begin_landing | Lander retro thrusters igniting for a landing burn, sharp jet ignition burst settling into a strong steady roar |
| `sfx_touchdown` | SFX | 3 | planet_descent.gd _touchdown | Small spacecraft touching down on rocky ground, landing struts compressing with a heavy hydraulic thud, thrusters cutting off with a falling whoosh, metal settling ticks |
| `sfx_liftoff` | SFX | 7 | planet_descent.gd start_ascent | Spacecraft lifting off from the ground, thrusters igniting, deep powerful rumble building and rattling, rising roar as it climbs away into the sky |
| `sfx_cryo_hatch` | SFX | 2.5 | ship_wakeup.gd _open_now | Cryogenic sleep pod hatch unsealing, pressurized seal releasing with a sharp hiss, mechanical latch clunk, hatch gliding open |
| `sfx_cryo_vapour` | SFX | 5 | ship_wakeup.gd _open_now | Cold cryogenic vapour gently venting and rolling out, soft airy hiss slowly fading away |
| `sfx_power_surge` | SFX | 4.5 | ship_builder.gd power_wave | Electrical power surge rolling through a large spaceship, deep hum rising from low to high, transformers energising, ending in a steady charged drone |
| `sfx_lamp_clunk_01` | SFX | 0.8 | ship_builder.gd power_wave | Heavy industrial ceiling light switching on, solid relay clunk followed by a faint fluorescent buzz |
| `sfx_lamp_clunk_02` | SFX | 0.8 | ship_builder.gd power_wave | Big spaceship corridor lamp powering on, deep electrical contactor thunk with a short bright hum |
| `sfx_lamp_clunk_03` | SFX | 0.8 | ship_builder.gd power_wave | Industrial floodlight breaker clacking on, metallic clunk and a brief rising electrical tick |
| `sfx_scan_ping` | SFX | 2 | surface_scanner.gd pulse | Sci-fi suit scanner emitting a sonar ping, a clean resonant pulse expanding outward with a soft shimmering tail |
| `sfx_scan_blip` | SFX | 0.5 | surface_scanner.gd _tag | Single soft returning radar blip, short bright digital ping |
| `sfx_pod_incoming` | SFX | 3 | surface_scene.gd _on_pod_beat | Small cargo drop pod descending from the sky on retro thrusters, jet roar growing louder and closer, then a sudden cut-off |
| `sfx_pod_impact` | SFX | 1.5 | surface_scene.gd _on_pod_impact | Heavy metal cargo pod slamming onto rocky ground, deep thud, landing struts compressing with a hydraulic clunk, gravel scatter |
| `sfx_pod_unlock` | SFX | 1 | surface_scene.gd _on_pod_beat | Pressurised hatch unlocking, magnetic latch clack followed by a short gas hiss |
| `sfx_pod_strain` | SFX | 0.8 | surface_scene.gd _on_pod_beat | Metal hatch straining against its hinges, short tense creak and groan |
| `sfx_pod_snap` | SFX | 0.8 | surface_scene.gd _on_pod_snap | Metal hatch snapping open with a sharp clang and a small electric energy pop |
| `sfx_energy_whoosh` | SFX | 1 | surface_scene.gd _on_pod_beat | Glowing energy cell whooshing through the air into a space suit, rising sci-fi swoosh ending in a soft charging chime |
| `sfx_wild_grazer_01` | Ambience | 1.5 | ground_wildlife.gd _call | Alien grazing animal giving a soft low hooting call, gentle throaty warble, like a deer crossed with a whale, outdoors, distant |
| `sfx_wild_grazer_02` | Ambience | 1.2 | ground_wildlife.gd _call | Alien herd animal short nasal grunt and snort with a strange chirping overtone, outdoors |
| `sfx_wild_grazer_03` | Ambience | 2 | ground_wildlife.gd _call | Alien grazing creature calling to its herd, airy rising two-note moan with a fluttering throat trill, outdoors, distant |
| `sfx_wild_beast_01` | Ambience | 2 | ground_wildlife.gd _call | Large alien beast low guttural growl and huffing breath, deep and resonant, outdoors |
| `sfx_wild_beast_02` | Ambience | 1.8 | ground_wildlife.gd _call | Heavy alien animal grunting bellow with a rattling throat, short, outdoors |
| `sfx_wild_giant_01` | Ambience | 4 | ground_wildlife.gd _call | Colossal alien creature distant deep bellow echoing across a valley, slow, subsonic rumble, mournful |
| `sfx_wild_giant_02` | Ambience | 4 | ground_wildlife.gd _call | Giant alien beast far away, long low groaning call with stone-like grinding resonance, echoing |
| `sfx_wild_flyer_01` | Ambience | 1.5 | ground_wildlife.gd _call | Alien winged creature shrill screeching cry with a melodic trill, outdoors, echoing |
| `sfx_wild_flyer_02` | Ambience | 1.5 | ground_wildlife.gd _call | Alien bird-beast sharp piercing call, two descending notes, distant, outdoors |
| `sfx_leviathan_song` | Ambience | 8 | sea_leviathan.gd _process | Distant deep whale song echoing across an alien ocean, low mournful moan with resonant harmonics, then a deep rumbling exhale, very distant |
| `ui_card_whoosh` | UI | 1.5 | app_flow.gd goto | Soft cinematic whoosh with a low airy sweep and a faint shimmer, subtle and smooth |
| `ui_holo_boot` | UI | 0.5 | holo_anim.gd boot_in | Subtle holographic display powering on, soft glassy shimmer blip, very short and quiet |
