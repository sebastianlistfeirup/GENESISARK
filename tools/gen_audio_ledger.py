#!/usr/bin/env python3
"""Writes docs/AUDIO_LEDGER.csv: every sound cue the game needs, where it is
triggered, its bus, whether code already calls it (HOOKED) and a ready-to-use
generation prompt. Status columns are preserved on re-run.
Usage: python3 tools/gen_audio_ledger.py"""
import csv, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "AUDIO_LEDGER.csv")
# cue_id, category, where/trigger, bus, loop, length_s, hook, tool, prompt (EN, for SFX/music generators)
C = [
 # --- Ark ambience (bible p.13: fans, distant machinery, muted AI -> loneliness)
 ("amb_ship_dark","ambience","Arken før strøm","Ambience",1,60,"HOOKED","ElevenLabs SFX","Dark derelict spaceship interior, slow failing ventilation fans, distant metal creaks, faint electrical hum, very sparse, lonely, seamless loop"),
 ("amb_ship_powered","ambience","Arken efter strøm","Ambience",1,60,"HOOKED","ElevenLabs SFX","Spaceship interior with steady air circulation, soft server hum, gentle cryogenic pumps, calm and clean, seamless loop"),
 ("amb_ship_hum","ambience","Fallback for arken","Ambience",1,6,"HOOKED (placeholder)","—","(placeholder synthesized)"),
 ("amb_embryo_bank","ambience","Embryobanken (zone)","Ambience",1,45,"PLANNED","ElevenLabs SFX","Quiet cryogenic storage hall, soft rhythmic coolant flow, faint glassy resonance, reverent, seamless loop"),
 ("amb_space","ambience","Menu, indflyvning","Ambience",1,60,"HOOKED","ElevenLabs SFX","Deep space drone from inside a ship hull, low sub rumble, distant radio static, vast and empty, seamless loop"),
 # --- Surfaces per biome
 ("amb_surface_green","ambience","Ekspedition grøn biome","Ambience",1,60,"HOOKED","ElevenLabs SFX","Alien temperate forest clearing, soft wind in strange foliage, distant unfamiliar bird calls, wet ground, seamless loop"),
 ("amb_surface_desert","ambience","Ekspedition ørken","Ambience",1,60,"HOOKED","ElevenLabs SFX","Hot rocky desert plateau, dry wind over stone, fine sand hiss, heat shimmer tone, seamless loop"),
 ("amb_surface_ice","ambience","Ekspedition is","Ambience",1,60,"HOOKED","ElevenLabs SFX","Frozen ice field, cold howling wind, ice cracking far away, crystalline tinkles, seamless loop"),
 ("amb_colony_green","ambience","Koloni grøn","Ambience",1,60,"HOOKED","ElevenLabs SFX","Small frontier settlement in a green valley, light machinery, wind, distant water, occasional robot servo, seamless loop"),
 ("amb_colony_desert","ambience","Koloni ørken","Ambience",1,60,"HOOKED","ElevenLabs SFX","Small frontier settlement on a desert plain, dry wind, solar panel ticking, mining drill far away, seamless loop"),
 ("amb_colony_ice","ambience","Koloni is","Ambience",1,60,"HOOKED","ElevenLabs SFX","Small frontier settlement on ice, cold wind, steam vents, heaters humming, seamless loop"),
 ("amb_colony_wind","ambience","Fallback koloni/overflade","Ambience",1,6,"HOOKED (placeholder)","—","(placeholder synthesized)"),
 ("amb_colony_people","ambience","Koloni med befolkning (lag)","Ambience",1,45,"PLANNED","ElevenLabs SFX","Distant children playing and muffled conversations in a small settlement, no intelligible words, seamless loop"),
 ("amb_hazard_spores","ambience","Sporezone","SFX",1,20,"PLANNED","ElevenLabs SFX","Soft puffing spores, organic crackle, wet hiss, unsettling but subtle, loop"),
 ("amb_hazard_storm","ambience","Stormfront","SFX",1,30,"PLANNED","ElevenLabs SFX","Approaching coastal storm, heavy wind gusts, rain on suit helmet, loop"),
 ("amb_hazard_dust","ambience","Støvfane","SFX",1,30,"PLANNED","ElevenLabs SFX","Sandstorm hitting a suit visor, gritty hiss, low roar, loop"),
 ("amb_hazard_cold","ambience","Kuldelomme","SFX",1,30,"PLANNED","ElevenLabs SFX","Extreme cold wind, ice crystals on visor, suit heater straining, loop"),
 # --- Character / interaction
 ("sfx_footstep","sfx","Kaptajnens trin (skib)","SFX",0,0.3,"HOOKED","ElevenLabs SFX","Single footstep, magnetic boot on metal deck grating, short, dry (make 6 variations)"),
 ("sfx_footstep_soil","sfx","Trin på jord/sand/is","SFX",0,0.3,"PLANNED","ElevenLabs SFX","Single footstep, heavy suit boot on gravel (variations: soil, sand, snow)"),
 ("sfx_interact","sfx","Brug af terminal/objekt","SFX",0,0.4,"HOOKED","ElevenLabs SFX","Sci-fi console touch, soft confirming blip with tactile click"),
 ("sfx_power_on","sfx","Nødstrøm genoprettet","SFX",0,3,"HOOKED","ElevenLabs SFX","Spaceship power coming back online, rising electrical whine, relays clicking, lights buzzing on"),
 ("sfx_door","sfx","Dør åbner/lukker","SFX",0,1,"PLANNED","ElevenLabs SFX","Heavy sci-fi bulkhead door sliding open with pneumatic hiss"),
 ("sfx_sample","sfx","Prøve taget","SFX",0,1.5,"HOOKED","ElevenLabs SFX","Handheld drill sampling soil, short whir then capsule sealing click"),
 ("sfx_sample_loop","sfx","Under prøvetagning (8 s)","SFX",1,8,"PLANNED","ElevenLabs SFX","Handheld core drill grinding into rock, steady, loop"),
 ("sfx_relay_place","sfx","Relæ placeret","SFX",0,2,"PLANNED","ElevenLabs SFX","Deployable beacon unfolding, metallic clanks, antenna extending, radio chirp"),
 ("sfx_suit_warning","sfx","Dragt under reserve","SFX",0,1.5,"HOOKED via alarm_warning","ElevenLabs SFX","Space suit low energy warning, two soft descending tones, inside helmet"),
 ("sfx_drone_refill","sfx","Dronereserve leverer","SFX",0,3,"PLANNED","ElevenLabs SFX","Small drone flying in, hovering, dropping a cargo pod, flying away"),
 # --- Voyage
 ("sfx_probe_launch","sfx","Sonde sendt","SFX",0,2.5,"HOOKED","ElevenLabs SFX","Small probe launched from a ship, pneumatic thump then rocket whoosh fading"),
 ("sfx_scan","sfx","Orbital scanning","SFX",0,3,"HOOKED","ElevenLabs SFX","Orbital sensor sweep, rising digital pulse, data chirps"),
 ("sfx_thruster","sfx","Indflyvning (motor)","SFX",1,6,"HOOKED","ElevenLabs SFX","Large spaceship main engine heard from inside, deep steady thrust rumble, loop"),
 ("sfx_ring_pass","sfx","Gennem indflyvningsring","SFX",0,1,"PLANNED","ElevenLabs SFX","Passing through a navigation gate, soft whoosh with harmonic chime"),
 ("sfx_landing","sfx","Landing committed","SFX",0,8,"PLANNED","ElevenLabs SFX","Huge ship landing on a planet, retro rockets roaring, heavy touchdown, settling metal groans"),
 # --- Colony
 ("sfx_build_place","sfx","Byggeordre","SFX",0,1,"HOOKED","ElevenLabs SFX","Construction order placed, holographic placement thunk"),
 ("sfx_build_loop","sfx","Byggeplads (positionel)","SFX",1,10,"PLANNED","ElevenLabs SFX","Small construction robots welding and riveting, distant, loop"),
 ("sfx_build_done","sfx","Bygning færdig","SFX",0,2,"HOOKED","ElevenLabs SFX","Building completed, systems powering up, satisfying settle"),
 ("sfx_demolish","sfx","Nedrivning","SFX",0,2,"PLANNED","ElevenLabs SFX","Prefab module dismantled by robots, metal panels unbolted"),
 ("sfx_power_cut","sfx","Strøm afbrudt (bygning)","SFX",0,1.5,"PLANNED","ElevenLabs SFX","Machinery powering down, falling whine, relay clack"),
 ("sfx_incubation_start","sfx","Inkubation startet","SFX",0,4,"PLANNED","ElevenLabs SFX","Gentle medical machinery starting, soft heartbeat-like pulse, warm"),
 # --- UI
 ("ui_click","ui","Knap","UI",0,0.1,"HOOKED","ElevenLabs SFX","Subtle sci-fi UI click"),
 ("ui_hover","ui","Hover","UI",0,0.1,"HOOKED","ElevenLabs SFX","Very soft UI hover tick"),
 ("ui_confirm","ui","Bekræft / mål fuldført","UI",0,0.6,"HOOKED","ElevenLabs SFX","Positive confirmation chime, two rising tones, warm"),
 ("ui_error","ui","Afvist kommando","UI",0,0.4,"HOOKED","ElevenLabs SFX","Gentle UI denial buzz, not harsh"),
 ("alarm_warning","alarm","Advarsel (cooldown 6 s)","SFX",0,1.5,"HOOKED","Manuel/ElevenLabs","Calm ship warning tone, two notes, clearly different from critical"),
 ("alarm_critical","alarm","Kritisk (cooldown 6 s)","SFX",0,2,"HOOKED","Manuel/ElevenLabs","Critical ship alarm, three urgent pulses, unmistakable but not painful"),
 # --- Music (bible p.13: human voices arrive gradually)
 ("music_hope","music","Menu + fallback","Music",1,120,"HOOKED","ElevenLabs Music / komponist","Ambient orchestral pad, solitary piano motif, hope emerging from loneliness, slow, 60 BPM"),
 ("music_ark_alone","music","Akt I i arken","Music",1,120,"PLANNED","ElevenLabs Music / komponist","Sparse ambient synth and cello, lonely spaceship, sustained tones, very quiet"),
 ("music_colony_act2","music","Akt II koloni","Music",1,150,"HOOKED","ElevenLabs Music / komponist","Warm ambient with acoustic guitar and soft strings, building a home, gentle optimism"),
 ("music_colony_act3","music","Akt III koloni","Music",1,150,"HOOKED","ElevenLabs Music / komponist","Fuller arrangement, wordless human choir enters softly, community and pride"),
 ("stinger_birth","music","Første fødsel","Music",0,8,"HOOKED","Komponist anbefales","Tender swell, celesta and strings, a single held breath then warmth"),
 ("stinger_crisis","music","Kritisk hændelse","Music",0,5,"PLANNED","ElevenLabs Music","Short tense low string swell, unresolved"),
 ("music_ending_independent","music","Epilog selvstændig","Music",0,120,"PLANNED","Komponist anbefales","Main theme in full, choir and orchestra, letting go"),
 ("music_ending_shielded","music","Epilog skærmet","Music",0,120,"PLANNED","Komponist anbefales","Main theme, restrained, bittersweet"),
 ("music_ending_fragile","music","Epilog skrøbelig","Music",0,120,"PLANNED","Komponist anbefales","Main theme fragmented, piano alone, unresolved hope"),
]
old = {}
if os.path.exists(OUT):
    for r in csv.DictReader(open(OUT, encoding="utf-8")):
        old[r["cue_id"]] = r
fields = ["cue_id","category","trigger","bus","loop","length_s","code_hook","tool","prompt","file","loudness_target","status","license","notes"]
loud = {"ambience": "-28 LUFS", "sfx": "-20 LUFS (peak -3 dBFS)", "ui": "-22 LUFS", "alarm": "-16 LUFS", "music": "-23 LUFS"}
with open(OUT, "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields); w.writeheader()
    for c in C:
        p = old.get(c[0], {})
        w.writerow({"cue_id": c[0], "category": c[1], "trigger": c[2], "bus": c[3], "loop": c[4], "length_s": c[5], "code_hook": c[6],
                    "tool": c[7], "prompt": c[8], "file": p.get("file", f"assets/audio/final/{c[0]}.ogg"), "loudness_target": loud[c[1]],
                    "status": p.get("status", "PLACEHOLDER" if os.path.exists(os.path.join(ROOT, "assets/audio/placeholder", c[0] + ".wav")) else "NEEDED"),
                    "license": p.get("license", ""), "notes": p.get("notes", "")})
print(len(C), "cues")
