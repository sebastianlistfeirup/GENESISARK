# assets/imported/

Udvalgte Synty-filer, som `tools/synty/stage.py` kopierer ind fra karantænen.
**Mappen er udelukket fra git**, fordi repositoryet er offentligt, og købte filer
aldrig må deles (bibel s. 23, Syntys licens). På en ny maskine: pak pakkerne ud
med `tools/synty/unpack.py` og kør `tools/synty/build.sh`; valgene i
`data/art/synty_choices.json` gør resultatet ens hver gang.

Wrapper-scener (`art/prefabs/`), atlas-materialer (`art/materials/`), bone maps
(`art/rigs/`) og animationsbiblioteker (`art/animations/`) indeholder ingen
Synty-data og må gerne committes; de virker, når filerne her er bygget.

**Dyreliv (D-053):** `assets/imported/polyperfect/` holder de Poly Perfect-dyr
("Low Poly Animated Fantasy Creatures"), som `tools/polyperfect/stage.py` kopierer
ind fra ejerens pakke (FBX med indlejrede klip + COL/EMIT-teksturer). Også kun lokalt.
Synty-aliens' klip bages med
`godot --headless --path . --script res://tools/synty/bake_alien_clips.gd`
til `art/animations/beast.*.res` (lokale ligesom de andre biblioteker).
