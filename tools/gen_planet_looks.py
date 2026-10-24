#!/usr/bin/env python3
"""Writes the per-planet identity into data/art/ground_cover.json (D-039).

Each planet gets its own terrain style, NatureKit look (tints/glow/wind), trees
with trunk collision, dense ground cover and landmarks. Biome keys stay as the
fallback. Paths point at local Synty packs (never committed); missing files are
skipped at runtime.  Usage: python3 tools/gen_planet_looks.py
"""
import json, os

N = "res://assets/Synty/Nature/"
W = "res://assets/Synty/PolygonSciFiWorlds/Prefabs/Environments/"
J = lambda n: N + "Jungle/FBX/" + n + ".fbx"
S = lambda n: N + "Swamp/FBX/" + n + ".fbx"
A = lambda n: N + "Alpine/FBX/Environment/" + n + ".fbx"
R = lambda n: N + "Arid/FBX/" + n + ".fbx"
Wp = lambda n: W + n + ".tscn"


def c(mesh, count, s=(0.8, 1.3), cluster=5, **kw):
    d = {"mesh": mesh, "count": count, "scale": list(s), "cluster": cluster}
    d.update(kw)
    return d


def t(meshes, count, s=(0.8, 1.3), radius=0.5, cluster=1):
    return {"meshes": meshes, "count": count, "scale": list(s), "radius": radius, "cluster": cluster}


def lm(meshes, count, s=(1, 1.4), ring=(70, 86)):
    return {"meshes": meshes, "count": count, "scale": list(s), "ring": list(ring)}


PLANETS = {
    "viridia": {  # jungle: dense canopy, ferns, flowers, alien flora
        "sky": {"bodies": [{"biome": "ice", "tint": "#cfd8e6", "azimuth": 35, "elevation": 22, "size": 14}, {"biome": "desert", "tint": "#d9a06a", "azimuth": 70, "elevation": 34, "size": 5}], "motes": "fx.spores", "motes_scale": 2.5},
        "terrain": {"amp": 1.25, "ground": "#4c8a2f", "patch": "#3a7426", "cliff": "#3f4a33"},
        "look": {"hue_shift": -0.02, "sat": 1.15, "wind": 0.07, "rock_tint": "#9aa58a", "rock_top_tint": "#6f9a3c"},
        "trees": [t([J("SM_Env_Tree_Palm_01"), J("SM_Env_Tree_Palm_02"), J("SM_Env_Tree_Palm_03"), J("SM_Env_Tree_Banana_01"), J("SM_Env_Tree_Banana_02"),
                     J("SM_Env_Tree_Pohutukawa_01"), J("SM_Env_Tree_Pohutukawa_02"), J("SM_Env_Tree_Forest_01"), J("SM_Env_Tree_Forest_02"),
                     Wp("SM_Env_Plant_Large_Spiral_01"), Wp("SM_Env_Plant_Balloon_Tall_01")], 150, (0.9, 1.5), 0.6, 3)],
        "cover": [c(J("SM_Env_Fern_01"), 260, (0.8, 1.4), 6), c(J("SM_Env_Fern_03"), 200, (0.8, 1.4), 6),
                  c(J("SM_Env_Bush_Tropical_01"), 140, (0.8, 1.3), 4), c(J("SM_Env_Bush_Tropical_03"), 120, (0.8, 1.3), 4),
                  c(J("SM_Env_Bush_Palm_02"), 110, (0.8, 1.3), 3), c(J("SM_Env_Grass_Tall_Clump_01"), 700, (0.9, 1.4), 10),
                  c(J("SM_Env_Grass_Med_Clump_02"), 700, (0.9, 1.4), 10), c(J("SM_Env_Flowers_01"), 220, (0.9, 1.3), 6),
                  c(J("SM_Env_Flower_Pitcher_01"), 60, (0.8, 1.2), 3), c(J("SM_Env_Ground_Cover_01"), 260, (0.9, 1.4), 6),
                  c(Wp("SM_Env_Plant_Bulb_01"), 50, (0.3, 0.5), 3), c(J("SM_Env_Rock_Pile_02"), 40, (0.6, 1.0), 2)],
        "landmarks": [lm([J("SM_Env_Rock_Cliff_01"), J("SM_Env_Rock_Cliff_02"), J("SM_Env_Rock_Cliff_03"), J("SM_Env_Rock_Arch_01")], 22, (1.6, 2.6))],
    },
    "pelagos": {  # water world: open sea, islands, mangroves, reeds, lily pads, coral shallows
        "sky": {"bodies": [{"biome": "green", "tint": "#7fb0c8", "azimuth": -40, "elevation": 18, "size": 22, "ring": "#cfe4ee"}]},
        "terrain": {"amp": 1.55, "water": True, "ground": "#4f8f5c", "patch": "#c9b98a", "cliff": "#46564c"},
        "look": {"hue_shift": 0.07, "sat": 1.05, "wind": 0.12, "rock_tint": "#8c9a98", "rock_top_tint": "#6b8f5a"},
        "trees": [t([S("SM_Env_Tree_Mangrove_01"), S("SM_Env_Tree_Mangrove_02"), S("SM_Env_Tree_Mangrove_03"), S("SM_Env_Tree_Swamp_01"),
                     S("SM_Env_Tree_Swamp_03"), J("SM_Env_Tree_Palm_04")], 90, (0.9, 1.4), 0.6, 3)],
        "cover": [c(S("SM_Env_Grass_Swamp_01"), 500, (0.9, 1.4), 9), c(S("SM_Env_Grass_Swamp_02"), 400, (0.9, 1.4), 9),
                  c(S("SM_Env_SwampGrass_Group_01"), 200, (0.8, 1.2), 6), c(S("SM_Env_Reeds_01"), 260, (0.9, 1.4), 8, shore=True),
                  c(S("SM_Env_Reeds_02"), 200, (0.9, 1.4), 8, shore=True), c(S("SM_Env_MossMound_01"), 50, (0.6, 1.0), 3),
                  c(J("SM_Env_DriftWood_02"), 40, (0.8, 1.2), 2, shore=True), c(J("SM_Env_Seaweed_Beach_01"), 120, (0.9, 1.3), 5, shore=True),
                  c(S("SM_Env_LillyPads_01"), 180, (0.9, 1.4), 6, on_water=True), c(S("SM_Env_LillyPads_03"), 140, (0.9, 1.4), 6, on_water=True),
                  c(J("SM_Prop_Coral_02"), 60, (0.8, 1.3), 4, on_water=True)],
        "landmarks": [lm([J("SM_Env_Rock_Cliff_01"), J("SM_Env_Rock_Spike_01"), J("SM_Env_Rock_Spikes_02")], 18, (1.8, 2.8), (62, 86))],
    },
    "ferrum": {  # rust desert: mesas, spikes, ore crystals, bones, sulphur
        "sky": {"bodies": [{"biome": "desert", "tint": "#b0583a", "azimuth": 20, "elevation": 26, "size": 26, "ring": "#e8c49a"}, {"biome": "ice", "tint": "#bfc9d6", "azimuth": -55, "elevation": 40, "size": 6}], "motes": "fx.dust", "motes_scale": 2.0},
        "terrain": {"amp": 1.1, "terraces": 2.6, "ground": "#c8662f", "patch": "#a84f26", "cliff": "#6e3420"},
        "look": {"rock_tint": "#d47c48", "rock_top_tint": "#e09a5c", "sat": 0.8},
        "trees": [t([R("Environment/SM_Env_Rocks_Spikes_Large_01"), R("Environment/SM_Env_Rocks_Spikes_Large_02"),
                     R("Environment/SM_Env_Rocks_Spikes_Large_03"), R("Environment/SM_Env_Tree_Dead_01")], 40, (0.7, 1.2), 1.2, 2)],
        "cover": [c(R("Environment/SM_Env_Rocks_Spikey_01"), 120, (0.6, 1.1), 4), c(R("Environment/SM_Env_Rocks_Spikey_03"), 100, (0.6, 1.1), 4),
                  c(R("Environment/SM_Env_Rock_Pebbles_02"), 260, (0.8, 1.4), 6), c(R("Environment/SM_Env_Bush_Bramble_01"), 90, (0.7, 1.2), 4),
                  c(R("Props/SM_Prop_Bones_03"), 25, (0.8, 1.2), 2), c(R("Props/SM_Prop_Bones_06"), 20, (0.8, 1.2), 2),
                  c(R("Environment/SM_Env_Sulphur_Blob_01"), 30, (0.6, 1.0), 3), c(Wp("SM_Env_Floating_Crystal_01"), 30, (0.05, 0.1), 3, emissive="#ffb35a"),
                  c(R("Environment/SM_Env_GroundCover_02"), 200, (0.9, 1.4), 6)],
        "landmarks": [lm([R("Environment/SM_Env_Rock_Cliff_05"), R("Environment/SM_Env_Rock_Cliff_06"), R("Environment/SM_Env_Rock_Cliff_10"),
                          R("Environment/SM_Env_Rock_Cliff_14"), R("Environment/SM_Env_Rock_Arch_01")], 26, (1.6, 2.6))],
    },
    "sere": {  # pale dune desert: ripples, succulents, arches, distant hills
        "sky": {"bodies": [{"biome": "ice", "tint": "#e8e0d0", "azimuth": -25, "elevation": 30, "size": 9}, {"biome": "ice", "tint": "#d0c8b8", "azimuth": 15, "elevation": 44, "size": 5}], "motes": "fx.dust", "motes_scale": 2.5},
        "terrain": {"amp": 0.85, "dunes": 1.1, "ground": "#dcb57a", "patch": "#cfa565", "cliff": "#9a7650"},
        "look": {"rock_tint": "#e7cfa3", "rock_top_tint": "#f0dcb0", "hue_shift": 0.03, "sat": 0.9},
        "trees": [t([R("Environment/SM_Env_Cactus_01"), R("Environment/SM_Env_Cactus_02"), R("Environment/SM_Env_Cactus_03"),
                     R("Environment/SM_Env_Tree_Dead_02")], 45, (0.9, 1.4), 0.5, 2)],
        "cover": [c(R("Environment/SM_Env_Succulent_01"), 140, (0.8, 1.3), 5), c(R("Environment/SM_Env_Succulent_03"), 120, (0.8, 1.3), 5),
                  c(R("Environment/SM_Env_Succulent_05"), 100, (0.8, 1.3), 4), c(R("Environment/SM_Env_GroundCover_01"), 220, (0.9, 1.4), 6),
                  c(R("Environment/SM_Env_Rock_Pebbles_04"), 200, (0.8, 1.3), 6), c(R("Environment/SM_Env_Bush_Bramble_02"), 60, (0.7, 1.1), 3),
                  c(R("Props/SM_Prop_Bones_01"), 12, (0.9, 1.2), 1)],
        "landmarks": [lm([R("Environment/SM_Env_Backrgound_Hill_01"), R("Environment/SM_Env_Backrgound_Hill_02"), R("Environment/SM_Env_Backrgound_Hill_03")], 10, (0.8, 1.2), (84, 96)),
                      lm([R("Environment/SM_Env_Rock_Arch_Half_01"), R("Environment/SM_Env_Rock_Arch_01"), R("Environment/SM_Env_Rock_Cliff_08")], 10, (1.2, 2.0), (55, 80))],
    },
    "nivalis": {  # ice world: frosted pines, ice sheets, snow mounds, mountain ranges
        "sky": {"bodies": [{"biome": "green", "tint": "#6a8ec8", "azimuth": 30, "elevation": 24, "size": 18, "ring": "#dfe8f4"}], "aurora": "#3dffa8", "aurora_high": "#8a5cff", "motes": "fx.snow", "motes_scale": 2.5},
        "terrain": {"amp": 1.3, "ridges": 0.9, "ground": "#e2edf2", "patch": "#c7d9e4", "cliff": "#6a7c8c"},
        "look": {"sat": 0.45, "leaf_tint": "#d6e6ee", "trunk_tint": "#8a8f96", "rock_tint": "#b4c8e0", "rock_top_tint": "#ffffff", "rock_top_amount": 0.2, "wind": 0.04},
        "trees": [t([A("SM_Env_Pine_01"), A("SM_Env_Pine_02"), A("SM_Env_Pine_03"), A("SM_Env_Pine_04"), A("SM_Env_Pine_05"), A("SM_Env_Pine_NoLeaves_01")], 110, (0.8, 1.4), 0.4, 4)],
        "cover": [c(A("SM_Env_Snow_Mound_01"), 120, (0.8, 1.4), 4), c(A("SM_Env_Snow_Mound_03"), 100, (0.8, 1.3), 4),
                  c(A("SM_Env_Ice_Sheet_01"), 60, (0.8, 1.3), 3), c(A("SM_Env_Ice_Sheet_04"), 50, (0.8, 1.3), 3),
                  c(A("SM_Env_Rock_Pebbles_02"), 180, (0.8, 1.3), 5), c(A("SM_Env_Moss_Lumps_02"), 50, (0.7, 1.1), 3),
                  c(Wp("SM_Env_Floating_Crystal_02"), 30, (0.05, 0.1), 3, emissive="#9fe8ff")],
        "landmarks": [lm([A("SM_Env_MountainRange_01"), A("SM_Env_MountainRange_02"), A("SM_Env_MountainRange_03"), A("SM_Env_MountainRange_04")], 8, (0.5, 0.7), (92, 104)),
                      lm([A("SM_Env_Rock_Cliff_01"), A("SM_Env_Rock_Cliff_04"), A("SM_Env_Rock_Cliff_06"), A("SM_Env_Rock_Cliff_Arch_01")], 16, (1.4, 2.2), (60, 84))],
    },
    "umbra": {  # long night: jagged ridges, glowing crystals, bioluminescent ground life
        "sky": {"bodies": [{"biome": "desert", "tint": "#e0904a", "azimuth": 10, "elevation": 20, "size": 30, "ring": "#ffcf8a"}, {"biome": "ice", "tint": "#9fb8ff", "azimuth": -60, "elevation": 46, "size": 7}], "aurora": "#41ffd9", "aurora_high": "#c05cff"},
        "terrain": {"amp": 1.2, "ridges": 1.2, "ground": "#4c5a74", "patch": "#3e4b66", "cliff": "#242b3a"},
        "look": {"glow": 1.6, "glow_color": "#54ffe0", "hue_shift": 0.38, "sat": 1.2, "rock_tint": "#6a7896", "rock_top_tint": "#c8d4ec", "rock_top_amount": 0.3, "trunk_tint": "#4a4f5c", "wind": 0.03},
        "trees": [t([A("SM_Env_Pine_NoLeaves_01"), S("SM_Env_Tree_Dead_01"), S("SM_Env_Tree_Dead_02"), Wp("SM_Env_Rock_Spike_01"), Wp("SM_Env_Rock_Spike_03")], 60, (0.8, 1.3), 0.6, 3)],
        "cover": [c(J("SM_Env_Ground_Cover_02"), 260, (0.9, 1.4), 7), c(J("SM_Env_Fern_Part_02"), 160, (0.7, 1.1), 6),
                  c(J("SM_Env_Flowers_Flat_02"), 160, (0.8, 1.3), 6),
                  c(Wp("SM_Env_Floating_Crystal_01"), 70, (0.06, 0.13), 4, emissive="#54ffe0"), c(Wp("SM_Env_Floating_Crystal_02"), 50, (0.06, 0.12), 4, emissive="#b37bff"),
                  c(A("SM_Env_Rock_Pebbles_04"), 200, (0.8, 1.3), 6), c(A("SM_Env_Snow_Mound_02"), 60, (0.7, 1.2), 3)],
        "landmarks": [lm([A("SM_Env_MountainRange_02"), A("SM_Env_MountainRange_04")], 7, (0.5, 0.7), (92, 104)),
                      lm([A("SM_Env_Rock_Cliff_02"), A("SM_Env_Rock_Cliff_05"), A("SM_Env_Rock_Cliff_07"), A("SM_Env_Stalactite_03")], 18, (1.4, 2.4), (58, 84))],
    },
}

if __name__ == "__main__":
    path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "art", "ground_cover.json")
    old = json.load(open(path, encoding="utf8"))
    out = {"_note": "Planet identity (GroundCover/TerrainBuilder, D-039): per planet a terrain style (amp, dunes, ridges, terraces, water, ground colours), a NatureKit look (tints/glow/wind for Nature Biomes foliage and rocks), trees with trunk collision, dense clustered ground cover (shore/on_water placement), landmarks in an outer ring. Biome keys are the fallback. Generated by tools/gen_planet_looks.py. Purchased files are local only; missing files are skipped."}
    out.update(PLANETS)
    for b in ("green", "desert", "ice"):
        out[b] = old[b]
    json.dump(out, open(path, "w", encoding="utf8", newline="\n"), indent=1)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    missing = set()
    for k, v in PLANETS.items():
        for sec in ("cover", "trees", "landmarks"):
            for it in v.get(sec, []):
                for m in it.get("meshes", [it.get("mesh")]):
                    if not os.path.exists(os.path.join(root, m.replace("res://", ""))):
                        missing.add(m)
    print("planets:", len(PLANETS), "missing:", sorted(missing) if missing else "none")
