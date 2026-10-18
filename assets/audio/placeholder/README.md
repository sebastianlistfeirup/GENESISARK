# Placeholder-lyde (PROXY)

Alle filer i denne mappe er **midlertidige PROXY-lyde**, syntetiseret af
`tools/gen_placeholder_audio.py` (kun Python-standardbibliotek, fast seed 1337).
De er lavet af os selv og har ingen tredjepartslicens. De skal **erstattes** af
rigtige lyde (fx ElevenLabs/SFX-bibliotek, jf. biblen s. 28) før fase 2-porten.

Format: 22050 Hz, mono, 16-bit PCM WAV. Peak ca. -6 dBFS (musik ca. -9 dBFS).
Genskab: `python3 tools/gen_placeholder_audio.py`

| Fil | Brug | Loop | Status |
|---|---|---|---|
| amb_ship_hum.wav | Arkens ventilator-brum + fjern mekanik (6 s) | ja | PROXY |
| amb_colony_wind.wav | Vind på kolonien/overfladen (6 s) | ja | PROXY |
| amb_space.wav | Dyb rum-drone, stjernekort/indflyvning (6 s) | ja | PROXY |
| ui_click.wav | UI-klik | nej | PROXY |
| ui_hover.wav | UI-hover | nej | PROXY |
| ui_confirm.wav | Bekræft | nej | PROXY |
| ui_error.wav | Fejl/blokeret handling | nej | PROXY |
| alarm_critical.wav | Kritisk alarm (tydelig, ikke skinger) | nej | PROXY |
| alarm_warning.wav | Advarsel | nej | PROXY |
| sfx_footstep.wav | Fodtrin | nej | PROXY |
| sfx_interact.wav | Interaktion (E) | nej | PROXY |
| sfx_power_on.wav | Nødstrøm genstartes (stigende) | nej | PROXY |
| sfx_sample.wav | Prøvetagning | nej | PROXY |
| sfx_build_place.wav | Bygning placeret | nej | PROXY |
| sfx_build_done.wav | Byggeri færdigt | nej | PROXY |
| sfx_thruster.wav | Thruster under indflyvning (3 s) | ja | PROXY |
| sfx_probe_launch.wav | Probe affyres | nej | PROXY |
| sfx_scan.wav | Orbital scan / puls | nej | PROXY |
| music_hope.wav | Stille ambient-pad, mol -> dur (36 s) | ja | PROXY |
| stinger_birth.wav | Varm akkord-swell ved første fødsel (6 s) | nej | PROXY |
| amb_embryo_bank.wav | Lag: embryobanken (kølerør, glasklang) | ja | PROXY |
| amb_colony_people.wav | Lag: kolonien med befolkning (mumlen, fjerne stemmer) | ja | PROXY |
| amb_hazard_spores/storm/dust/cold.wav | Lag: fareområder på overfladen | ja | PROXY |
| sfx_footstep_01..03.wav | Fodtrin-varianter (skib) | nej | PROXY |
| sfx_footstep_soil(_01..03).wav | Fodtrin på jord/sand/is | nej | PROXY |
| sfx_door.wav | Dørpassage i arken | nej | PROXY |
| sfx_sample_loop.wav | Under prøvetagning (hold E) | ja | PROXY |
| sfx_relay_place.wav, sfx_drone_refill.wav | Ekspedition | nej | PROXY |
| sfx_ring_pass.wav, sfx_landing.wav | Indflyvning og landing | nej | PROXY |
| sfx_build_loop.wav | Byggeplads, positionel | ja | PROXY |
| sfx_demolish.wav, sfx_power_cut.wav, sfx_incubation_start.wav | Koloni | nej | PROXY |
| music_ark_alone.wav | Akt I i arken (24 s) | ja | PROXY |
| stinger_crisis.wav | Kritisk hændelse | nej | PROXY |
| music_ending_independent/shielded/fragile.wav | Epilog pr. slutning | nej | PROXY |

Ved udskiftning: behold filnavnet (eller opdatér referencen i AudioService) og
registrér den nye kilde/licens i lyd-ledgeren.
