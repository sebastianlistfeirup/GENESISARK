# assets/imported/

Udvalgte Synty-filer, som `tools/synty/stage.py` kopierer ind fra karantænen.
**Mappen er udelukket fra git**, fordi repositoryet er offentligt, og købte filer
aldrig må deles (bibel s. 23, Syntys licens). På en ny maskine: pak pakkerne ud
med `tools/synty/unpack.py` og kør `tools/synty/build.sh`; valgene i
`data/art/synty_choices.json` gør resultatet ens hver gang.

Wrapper-scener (`art/prefabs/`), atlas-materialer (`art/materials/`), bone maps
(`art/rigs/`) og animationsbiblioteker (`art/animations/`) indeholder ingen
Synty-data og må gerne committes; de virker, når filerne her er bygget.
