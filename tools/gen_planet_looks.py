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
SS = lambda n: "res://assets/Synty/SciFiSpace/FBX/" + n + ".fbx"
Bd = lambda n: "res://assets/Synty/PolygonSciFiWorlds/Prefabs/Buildings/" + n + ".tscn"


def c(mesh, count, s=(0.8, 1.3), cluster=5, **kw):
    d = {"mesh": mesh, "count": count, "scale": list(s), "cluster": cluster}
    d.update(kw)
    return d


def t(meshes, count, s=(0.8, 1.3), radius=0.5, cluster=1, **kw):
    d = {"meshes": meshes, "count": count, "scale": list(s), "radius": radius, "cluster": cluster}
    d.update(kw)
    return d


def lm(meshes, count, s=(1, 1.4), ring=(70, 86), tilt=0, sink=0.06):
    d = {"meshes": meshes, "count": count, "scale": list(s), "ring": list(ring)}
    if tilt:
        d["tilt"] = tilt  # crashed wrecks: random roll/pitch up to this many degrees
        d["sink"] = sink  # fraction of the height buried
    return d


PLANETS = {
    "viridia": {
        "blocked_rock": J("SM_Env_Rock_Pile_04"),
        "colony_style": "explorer",  # jungle: dense canopy, ferns, flowers, alien flora
        "sky": {"sun_size": 5, "sun_color": "#fff6d8", "creatures": [{"model": "res://assets/imported/meshy/creature_jelly.glb", "motion": "pulse", "size": 3, "count": 7, "height": [8, 18], "radius": [15, 45], "speed": 0.03, "beat": 1.4, "amount": 0.3, "glow": 1.2, "glow_color": "#7affd9"}], "bodies": [{"biome": "ice", "tint": "#cfd8e6", "azimuth": 35, "elevation": 22, "size": 14}, {"biome": "desert", "tint": "#d9a06a", "azimuth": 70, "elevation": 34, "size": 5}], "motes": "fx.spores", "motes_scale": 2.5, "fauna": {"mesh": N + "Jungle/FBX/FX_Bird_Mesh_01.fbx", "flocks": 3, "count": 9, "scale": 1.6}, "fauna_low": {"mesh": N + "Alpine/FBX/FX/FX_Butterfly_Mesh_Alpine_01.fbx", "flocks": 14, "count": 3, "scale": 0.45, "height": [1.0, 2.2], "radius": [1.5, 3.5]}},
        "terrain": {"ground_tex": N + "Jungle/Textures/Terrain/Grass_Debris_Texture_01.png", "cliff_tex": N + "Jungle/Textures/Terrain/RockWall_Texture_01.png", "amp": 1.25, "ground": "#4c8a2f", "patch": "#3a7426", "cliff": "#3f4a33"},
        "look": {"rock_top_tex": N + "Jungle/Textures/Terrain/Grass_Debris_Texture_01.png", "hue_shift": -0.02, "sat": 1.15, "wind": 0.07, "rock_tint": "#9aa58a", "rock_top_tint": "#6f9a3c"},
        "trees": [t([J("SM_Env_Tree_Palm_01"), J("SM_Env_Tree_Palm_02"), J("SM_Env_Tree_Palm_03"), J("SM_Env_Tree_Banana_01"), J("SM_Env_Tree_Banana_02"),
                     J("SM_Env_Tree_Pohutukawa_01"), J("SM_Env_Tree_Pohutukawa_02"), J("SM_Env_Tree_Forest_01"), J("SM_Env_Tree_Forest_02"),
                     Wp("SM_Env_Plant_Balloon_Tall_01")], 150, (0.9, 1.5), 0.6, 3)],
        "cover": [c(J("SM_Env_Rock_Pile_03"), 70, (0.7, 1.2), 3), c(J("SM_Env_DriftWood_03"), 40, (0.8, 1.2), 2), c(J("SM_Env_Flower_Pitcher_02"), 50, (0.8, 1.2), 3), c(Wp("SM_Env_Floating_Crystal_01"), 25, (0.04, 0.08), 3, emissive="#3fffe0"), c(J("SM_Env_Fern_01"), 260, (0.8, 1.4), 6), c(J("SM_Env_Fern_03"), 200, (0.8, 1.4), 6),
                  c(J("SM_Env_Bush_Tropical_01"), 140, (0.8, 1.3), 4), c(J("SM_Env_Bush_Tropical_03"), 120, (0.8, 1.3), 4),
                  c(J("SM_Env_Bush_Palm_02"), 110, (0.8, 1.3), 3), c(J("SM_Env_Grass_Tall_Clump_01"), 700, (0.9, 1.4), 10),
                  c(J("SM_Env_Grass_Med_Clump_02"), 700, (0.9, 1.4), 10), c(J("SM_Env_Flowers_01"), 220, (0.9, 1.3), 6),
                  c(J("SM_Env_Flower_Pitcher_01"), 60, (0.8, 1.2), 3), c(J("SM_Env_Ground_Cover_01"), 260, (0.9, 1.4), 6),
                  c(Wp("SM_Env_Plant_Bulb_01"), 50, (0.3, 0.5), 3), c(J("SM_Env_Rock_Pile_02"), 40, (0.6, 1.0), 2)],
        "landmarks": [
                      lm([Wp("SM_Env_Artifact_AlienRuin_02"), Wp("SM_Env_Artifact_AlienRuin_03"), Wp("SM_Env_Artifact_AlienRuin_09")], 4, (1.1, 1.5), (66, 80)), lm([Wp("SM_Env_Plant_Large_Spiral_Preset_01"), Wp("SM_Env_Plant_Large_Spiral_Preset_03"), Wp("SM_Env_Plant_Large_Spiral_01")], 7, (0.45, 0.7), (40, 72)), lm([Wp("SM_Env_Detail_Bridge_01")], 1, (0.55, 0.65), (78, 88)), lm([Wp("SM_Env_Skeleton_Preset_05")], 1, (0.16, 0.2), (66, 80)), lm([J("SM_Env_Rock_Cliff_01"), J("SM_Env_Rock_Cliff_02"), J("SM_Env_Rock_Cliff_03"), J("SM_Env_Rock_Arch_01")], 22, (1.6, 2.6))],
    },
    "pelagos": {
        "blocked_rock": J("SM_Env_Rock_Pile_06"),
        "colony_style": "explorer",  # water world: open sea, islands, mangroves, reeds, lily pads, coral shallows
        "sky": {"sun_size": 4, "sun_color": "#f2f8ff", "creatures": [{"model": "res://assets/imported/meshy/creature_manta.glb", "motion": "wing", "size": 9, "count": 5, "height": [12, 24], "radius": [25, 55], "speed": 0.06, "beat": 1.1, "amount": 0.3, "glow": 0.4}], "bodies": [{"biome": "green", "tint": "#7fb0c8", "azimuth": -40, "elevation": 18, "size": 22, "ring": "#cfe4ee"}], "fauna": {"mesh": N + "Jungle/FBX/FX_Bird_Mesh_01.fbx", "flocks": 4, "count": 11, "scale": 1.9}},
        "terrain": {"ground_tex": N + "Swamp/Textures/Terrain/Moss_Swamp_Texture_01.png", "cliff_tex": N + "Jungle/Textures/Terrain/RockWall_Texture_01.png", "amp": 1.55, "water": True, "ocean": True, "ground": "#4f8f5c", "patch": "#c9b98a", "cliff": "#46564c"},
        "look": {"rock_top_tex": N + "Jungle/Textures/Terrain/Grass_Debris_Texture_01.png", "hue_shift": 0.07, "sat": 1.05, "wind": 0.12, "rock_tint": "#8c9a98", "rock_top_tint": "#6b8f5a"},
        "trees": [t([S("SM_Env_Tree_Mangrove_01"), S("SM_Env_Tree_Mangrove_02"), S("SM_Env_Tree_Mangrove_03"), S("SM_Env_Tree_Swamp_01"),
                     S("SM_Env_Tree_Swamp_03"), J("SM_Env_Tree_Palm_04")], 90, (0.9, 1.4), 0.6, 3)],
        "cover": [c(J("SM_Env_Rock_Pile_05"), 50, (0.7, 1.1), 3, shore=True), c(J("SM_Prop_Coral_05"), 50, (0.7, 1.2), 4, on_water=True), c(S("SM_Env_Grass_Swamp_01"), 500, (0.9, 1.4), 9), c(S("SM_Env_Grass_Swamp_02"), 400, (0.9, 1.4), 9),
                  c(S("SM_Env_SwampGrass_Group_01"), 200, (0.8, 1.2), 6), c(S("SM_Env_Reeds_01"), 260, (0.9, 1.4), 8, shore=True),
                  c(S("SM_Env_Reeds_02"), 200, (0.9, 1.4), 8, shore=True), c(S("SM_Env_MossMound_01"), 50, (0.6, 1.0), 3),
                  c(J("SM_Env_DriftWood_02"), 40, (0.8, 1.2), 2, shore=True), c(J("SM_Env_Seaweed_Beach_01"), 120, (0.9, 1.3), 5, shore=True),
                  c(S("SM_Env_LillyPads_01"), 180, (0.9, 1.4), 6, on_water=True), c(S("SM_Env_LillyPads_03"), 140, (0.9, 1.4), 6, on_water=True),
                  c(J("SM_Prop_Coral_02"), 60, (0.8, 1.3), 4, on_water=True)],
        "landmarks": [
                      lm([Wp("SM_Env_Artifact_AlienRuin_04"), Wp("SM_Env_Detail_Spire_Group_01")], 4, (1.6, 2.4), (60, 82)), lm([J("SM_Env_Rock_Cliff_01"), J("SM_Env_Rock_Spike_01"), J("SM_Env_Rock_Spikes_02")], 18, (1.8, 2.8), (62, 86))],
    },
    "ferrum": {
        "blocked_rock": R("Environment/SM_Env_Rock_05"),
        "colony_style": "scav",  # rust desert: mesas, spikes, ore crystals, bones, sulphur
        "sky": {"sun_size": 9, "sun_color": "#ffe2a0", "debris": {"meshes": [Wp("SM_Env_Floating_Rocks_01"), Wp("SM_Env_Floating_Rocks_02"), Wp("SM_Env_Floating_Rocks_03"), Wp("SM_Env_Asteroid_02")], "count": 55, "scale": [0.25, 0.7]}, "bodies": [{"biome": "desert", "tint": "#b0583a", "azimuth": 20, "elevation": 26, "size": 26, "ring": "#e8c49a"}, {"biome": "ice", "tint": "#bfc9d6", "azimuth": -55, "elevation": 40, "size": 6}], "motes": "fx.dust", "motes_scale": 2.0},
        "terrain": {"ground_tex": N + "Arid/Textures/Dirt_Texture_Red_01.png", "cliff_tex": N + "Jungle/Textures/Terrain/RockWall_Texture_01.png", "amp": 1.1, "terraces": 2.6, "ground": "#c8662f", "patch": "#a84f26", "cliff": "#6e3420"},
        "look": {"rock_tint": "#d47c48", "rock_top_tint": "#e09a5c", "sat": 0.8},
        "trees": [t([R("Environment/SM_Env_Rocks_Spikes_Large_01"), R("Environment/SM_Env_Rocks_Spikes_Large_02"),
                     R("Environment/SM_Env_Rocks_Spikes_Large_03"), R("Environment/SM_Env_Tree_Dead_01")], 40, (0.7, 1.2), 1.2, 2)],
        "cover": [c(Wp("SM_Env_Blob_04"), 18, (2.5, 4.5), 2, emissive="#d8ff2a"), c(Wp("SM_Env_Blob_06"), 14, (2.0, 3.5), 2, emissive="#d8ff2a"), c(R("Environment/SM_Env_Rocks_Spikey_01"), 120, (0.6, 1.1), 4), c(R("Environment/SM_Env_Rocks_Spikey_03"), 100, (0.6, 1.1), 4),
                  c(R("Environment/SM_Env_Rock_Pebbles_02"), 260, (0.8, 1.4), 6), c(R("Environment/SM_Env_Bush_Bramble_01"), 90, (0.7, 1.2), 4),
                  c(R("Props/SM_Prop_Bones_03"), 25, (0.8, 1.2), 2), c(R("Props/SM_Prop_Bones_06"), 20, (0.8, 1.2), 2),
                  c(R("Environment/SM_Env_Sulphur_Blob_01"), 30, (0.6, 1.0), 3), c(Wp("SM_Env_Floating_Crystal_01"), 30, (0.05, 0.1), 3, emissive="#ffb35a"),
                  c(R("Environment/SM_Env_GroundCover_02"), 200, (0.9, 1.4), 6)],
        "landmarks": [lm([SS("SM_Ship_Bomber_02")], 1, (0.55, 0.65), (58, 72), 14, 0.3), lm([SS("SM_Ship_Fighter_Heavy_01")], 2, (0.75, 0.9), (52, 70), 22, 0.28), 
                      lm([Bd("SM_Bld_Scav_Dish_01")], 2, (0.3, 0.38), (74, 86), 24, 0.12), lm([Wp("SM_Env_Ground_Junk_01"), Wp("SM_Env_Ground_Junk_02")], 3, (0.35, 0.5), (46, 66)),
                      lm([Bd("SM_Bld_Scav_Refinery_Smoke_Stack_01"), Bd("SM_Bld_Scav_Refinery_Tower_01")], 2, (0.45, 0.6), (78, 90), 10, 0.1), 
                      lm([Wp("SM_Env_Skeleton_Preset_01"), Wp("SM_Env_Skeleton_Preset_03")], 2, (0.1, 0.13), (72, 86)), lm([Wp("SM_Env_Artifact_Head_01"), Wp("SM_Env_Artifact_AlienRuin_06")], 4, (0.9, 1.2), (76, 88)), lm([R("Environment/SM_Env_Rock_Cliff_05"), R("Environment/SM_Env_Rock_Cliff_06"), R("Environment/SM_Env_Rock_Cliff_10"),
                          R("Environment/SM_Env_Rock_Cliff_14"), R("Environment/SM_Env_Rock_Arch_01")], 26, (1.6, 2.6))],
    },
    "sere": {
        "blocked_rock": R("Environment/SM_Env_Rock_08"),
        "colony_style": "scav",  # pale dune desert: ripples, succulents, arches, distant hills
        "sky": {"sun_size": 7, "sun_color": "#fff0c8", "bodies": [{"biome": "ice", "tint": "#e8e0d0", "azimuth": -25, "elevation": 30, "size": 9}, {"biome": "ice", "tint": "#d0c8b8", "azimuth": 15, "elevation": 44, "size": 5}], "motes": "fx.dust", "motes_scale": 2.5},
        "terrain": {"ground_tex": N + "Jungle/Textures/Terrain/Sand_Wavy_Texture_01.png", "cliff_tex": N + "Jungle/Textures/Terrain/RockWall_Texture_01.png", "amp": 0.85, "dunes": 1.1, "ground": "#dcb57a", "patch": "#cfa565", "cliff": "#9a7650"},
        "look": {"rock_top_tex": N + "Jungle/Textures/Terrain/Sand_Wavy_Texture_01.png", "rock_tint": "#e7cfa3", "rock_top_tint": "#f0dcb0", "hue_shift": 0.03, "sat": 0.9},
        "trees": [t([R("Environment/SM_Env_Cactus_01"), R("Environment/SM_Env_Cactus_02"), R("Environment/SM_Env_Cactus_03"),
                     R("Environment/SM_Env_Tree_Dead_02")], 45, (0.9, 1.4), 0.5, 2)],
        "cover": [c(R("Environment/SM_Env_Succulent_01"), 140, (0.8, 1.3), 5), c(R("Environment/SM_Env_Succulent_03"), 120, (0.8, 1.3), 5),
                  c(R("Environment/SM_Env_Succulent_05"), 100, (0.8, 1.3), 4), c(R("Environment/SM_Env_GroundCover_01"), 220, (0.9, 1.4), 6),
                  c(R("Environment/SM_Env_Rock_Pebbles_04"), 200, (0.8, 1.3), 6), c(R("Environment/SM_Env_Bush_Bramble_02"), 60, (0.7, 1.1), 3),
                  c(R("Props/SM_Prop_Bones_01"), 12, (0.9, 1.2), 1),
                  c(SS("SM_Env_Debris_Shell_04"), 14, (0.8, 1.2), 3), c(SS("SM_Env_Debris_Shell_07"), 6, (0.6, 0.9), 2), c(SS("SM_Env_Debris_Pipe_01"), 8, (0.7, 1.0), 2)],
        "landmarks": [lm([SS("SM_Ship_Cruiser_01")], 1, (0.55, 0.65), (58, 70), 12, 0.32), lm([Bd("SM_Bld_Scav_Wreckage_01")], 1, (0.21, 0.23), (84, 90), 6, 0.3), 
                      lm([Wp("SM_Env_Skeleton_Preset_02"), Wp("SM_Env_Skeleton_Preset_04")], 2, (0.18, 0.24), (70, 84)), lm([Wp("SM_Env_Artifact_AlienRuin_05"), Wp("SM_Env_Artifact_Arm_01")], 3, (0.9, 1.3), (74, 88)), lm([R("Environment/SM_Env_Backrgound_Hill_01"), R("Environment/SM_Env_Backrgound_Hill_02"), R("Environment/SM_Env_Backrgound_Hill_03")], 10, (0.8, 1.2), (84, 96)),
                      lm([R("Environment/SM_Env_Rock_Arch_Half_01"), R("Environment/SM_Env_Rock_Arch_01"), R("Environment/SM_Env_Rock_Cliff_08")], 10, (0.7, 1.1), (62, 84))],
    },
    "nivalis": {
        "blocked_rock": A("SM_Env_Rock_09"),
        "colony_style": "corp",  # ice world: frosted pines, ice sheets, snow mounds, mountain ranges
        "sky": {"sun_size": 6, "sun_color": "#ffc890", "creatures": [{"model": "res://assets/imported/meshy/creature_whale.glb", "motion": "wing", "size": 40, "count": 2, "height": [70, 95], "radius": [130, 170], "speed": 0.012, "beat": 0.35, "amount": 0.12, "glow": 0.3}], "bodies": [{"biome": "green", "tint": "#6a8ec8", "azimuth": 30, "elevation": 24, "size": 18, "ring": "#dfe8f4"}], "aurora": "#3dffa8", "aurora_high": "#8a5cff", "motes": "fx.snow", "motes_scale": 2.5},
        "terrain": {"ground_tex": N + "Alpine/Textures/Snow_01.png", "cliff_tex": N + "Alpine/Textures/Snowcliff_Texture.png", "amp": 1.3, "ridges": 0.9, "ground": "#e2edf2", "patch": "#c7d9e4", "cliff": "#6a7c8c"},
        "look": {"rock_top_tex": N + "Alpine/Textures/Snow_01.png", "sat": 0.45, "leaf_tint": "#d6e6ee", "trunk_tint": "#8a8f96", "rock_tint": "#b4c8e0", "rock_top_tint": "#ffffff", "rock_top_amount": 0.2, "wind": 0.04},
        "trees": [t([A("SM_Env_Pine_01"), A("SM_Env_Pine_02"), A("SM_Env_Pine_03"), A("SM_Env_Pine_04"), A("SM_Env_Pine_05"), A("SM_Env_Pine_NoLeaves_01")], 110, (0.8, 1.4), 0.4, 4)],
        "cover": [c(A("SM_Env_Rock_Small_01"), 160, (0.9, 1.6), 5), c(A("SM_Env_Rock_Small_03"), 120, (0.9, 1.6), 5), c(A("SM_Env_Ice_Sheet_05"), 50, (0.8, 1.3), 3), c(A("SM_Env_Branch_02"), 40, (0.9, 1.3), 2), c(A("SM_Env_Pine_Stump_01"), 25, (0.9, 1.3), 2), c(Wp("SM_Env_Detail_Spikey_01"), 50, (0.25, 0.45), 3, emissive="#9fe8ff"), c(A("SM_Env_Snow_Mound_01"), 120, (0.8, 1.4), 4), c(A("SM_Env_Snow_Mound_03"), 100, (0.8, 1.3), 4),
                  c(A("SM_Env_Ice_Sheet_01"), 60, (0.8, 1.3), 3), c(A("SM_Env_Ice_Sheet_04"), 50, (0.8, 1.3), 3),
                  c(A("SM_Env_Rock_Pebbles_02"), 180, (0.8, 1.3), 5), c(A("SM_Env_Moss_Lumps_02"), 50, (0.7, 1.1), 3),
                  c(Wp("SM_Env_Floating_Crystal_02"), 30, (0.05, 0.1), 3, emissive="#9fe8ff")],
        "landmarks": [lm([Wp("SM_Env_Skeleton_Preset_02"), Wp("SM_Env_Skeleton_Preset_04")], 1, (0.2, 0.24), (64, 76)),
                      lm([Wp("SM_Env_Artifact_AlienRuin_07"), Wp("SM_Env_Artifact_AlienRuin_08"), Wp("SM_Env_Detail_Spire_Group_01")], 4, (1.8, 2.6), (62, 82)), lm([A("SM_Env_MountainRange_01"), A("SM_Env_MountainRange_02"), A("SM_Env_MountainRange_03"), A("SM_Env_MountainRange_04")], 8, (0.5, 0.7), (92, 104)),
                      lm([A("SM_Env_Rock_08"), A("SM_Env_Rock_09"), A("SM_Env_Rock_010"), A("SM_Env_Rock_Cliff_Arch_01"), Wp("SM_Env_Detail_Spire_Group_01")], 16, (2.4, 3.6), (60, 84))],
    },
    "umbra": {
        "blocked_rock": A("SM_Env_Rock_08"),
        "colony_style": "corp",  # long night: jagged ridges, glowing crystals, bioluminescent ground life
        "sky": {"creatures": [{"model": "res://assets/imported/meshy/creature_jelly.glb", "motion": "pulse", "size": 4, "count": 9, "height": [10, 24], "radius": [15, 55], "speed": 0.025, "beat": 1.2, "amount": 0.3, "glow": 2.5, "glow_color": "#4dffe0"}], "bodies": [{"biome": "desert", "tint": "#e0904a", "azimuth": 10, "elevation": 20, "size": 30, "ring": "#ffcf8a"}, {"biome": "ice", "tint": "#9fb8ff", "azimuth": -60, "elevation": 46, "size": 7}], "aurora": "#41ffd9", "aurora_high": "#c05cff"},
        "terrain": {"ground_tex": N + "Alpine/Textures/Snow_01.png", "cliff_tex": N + "Jungle/Textures/Terrain/RockWall_Texture_01.png", "amp": 1.2, "ridges": 1.2, "ground": "#4c5a74", "patch": "#3e4b66", "cliff": "#242b3a"},
        "look": {"rock_top_tex": N + "Alpine/Textures/Snow_01.png", "glow": 1.6, "glow_color": "#54ffe0", "hue_shift": 0.38, "sat": 1.2, "rock_tint": "#6a7896", "rock_top_tint": "#c8d4ec", "rock_top_amount": 0.25, "trunk_tint": "#4a4f5c", "wind": 0.03},
        "trees": [t([A("SM_Env_Pine_NoLeaves_01"), S("SM_Env_Tree_Dead_01"), S("SM_Env_Tree_Dead_02"), Wp("SM_Env_Rock_Spike_01"), Wp("SM_Env_Rock_Spike_03")], 60, (0.8, 1.3), 0.6, 3)],
        "cover": [c(A("SM_Env_Rock_Small_02"), 140, (0.9, 1.5), 5), c(A("SM_Env_Ice_Sheet_02"), 40, (0.8, 1.3), 3), c(J("SM_Env_Ground_Cover_02"), 260, (0.9, 1.4), 7), c(J("SM_Env_Fern_Part_02"), 160, (0.7, 1.1), 6),
                  c(J("SM_Env_Flowers_Flat_02"), 160, (0.8, 1.3), 6),
                  c(Wp("SM_Env_Floating_Crystal_01"), 70, (0.06, 0.13), 4, emissive="#54ffe0"), c(Wp("SM_Env_Floating_Crystal_02"), 50, (0.06, 0.12), 4, emissive="#b37bff"),
                  c(A("SM_Env_Rock_Pebbles_04"), 200, (0.8, 1.3), 6), c(A("SM_Env_Snow_Mound_02"), 60, (0.7, 1.2), 3)],
        "landmarks": [
                      lm([Wp("SM_Env_Artifact_AlienRuin_01"), Wp("SM_Env_Artifact_AlienRuin_08"), Wp("SM_Env_Artifact_AlienRuin_11")], 5, (1.8, 2.6), (60, 82)), lm([A("SM_Env_MountainRange_02"), A("SM_Env_MountainRange_04")], 7, (0.5, 0.7), (92, 104)),
                      lm([A("SM_Env_Rock_08"), A("SM_Env_Rock_010"), Wp("SM_Env_Rock_Spike_02"), Wp("SM_Env_Rock_Spike_04"), A("SM_Env_Stalactite_03")], 18, (2.2, 3.4), (58, 84))],
    },
}

# Alien flora from POLYGON Sci-Fi Worlds (the key art's plants): layered on top of
# the Nature Biomes base so every world reads as another planet, not Earth.
# glow = [energy, sat_min, val_min] -> only bright saturated texels emit.
P = lambda n: Wp("SM_Env_Plant_" + n)
ALIEN = {
    "viridia": {
        "trees": [t([P("Palm_01"), P("Palm_02"), P("Mushroom_01"), P("Mushroom_02")], 28, (0.8, 1.2), 0.7, 2)],
        "cover": [c(P("Flower_Large_01"), 9, (0.35, 0.5), 2), c(P("Flower_Large_03"), 7, (0.35, 0.5), 2), c(P("Spikey_02"), 16, (0.35, 0.55), 2),
                  c(P("Spikey_03"), 22, (0.5, 0.8), 3), c(P("Fern_02"), 60, (0.6, 1.0), 4), c(P("Grass_Flower_01"), 90, (0.6, 1.0), 5),
                  c(P("Flower_Large_Pod_01"), 26, (0.5, 0.8), 3), c(P("Flower_01"), 80, (0.8, 1.2), 5)],
    },
    "pelagos": {
        "cover": [c(P("Coral_01"), 40, (0.35, 0.6), 4, shore=True), c(P("Coral_03"), 50, (0.4, 0.7), 4, shore=True),
                  c(P("Kelp_01"), 90, (0.6, 1.0), 6, on_water=True), c(P("Kelp_02"), 70, (0.5, 0.9), 5, on_water=True),
                  c(P("Balloon_Group_01"), 40, (0.7, 1.1), 3, glow=[1.2, 0.3, 0.7]), c(P("Small_02"), 80, (0.6, 1.0), 4)],
    },
    "ferrum": {
        "trees": [t([P("Hallowed_01"), P("Hallowed_02"), P("Hallowed_03")], 14, (0.35, 0.55), 1.2, 2)],
        "cover": [c(P("Cactus_01"), 60, (0.9, 1.4), 4), c(P("Cactus_02"), 50, (0.9, 1.4), 4), c(P("Cactus_03"), 50, (0.9, 1.4), 4),
                  c(P("Pinecone_02"), 18, (0.5, 0.8), 2), c(P("Succulent_Large_01"), 12, (0.35, 0.55), 2)],
    },
    "sere": {
        "cover": [c(P("Succulent_Large_01"), 14, (0.3, 0.5), 2), c(P("Cactus_01"), 30, (0.9, 1.3), 3), c(P("Pinecone_03"), 14, (0.5, 0.8), 2)],
    },
    "nivalis": {
        "cover": [c(P("Fester_03"), 14, (0.4, 0.7), 2, glow=[1.4, 0.25, 0.75]), c(P("Fester_04"), 24, (0.5, 0.8), 3, glow=[1.4, 0.25, 0.75]),
                  c(P("Shrub_01"), 60, (0.8, 1.2), 4)],
    },
    "umbra": {
        "trees": [t([P("Balloon_Tall_01"), P("Balloon_Tall_02"), P("Kelp_04"), P("Kelp_05")], 70, (0.9, 1.5), 0.4, 4, glow=[3.0, 0.22, 0.7]),
                  t([P("Mushroom_01"), P("Mushroom_02"), P("Mushroom_03")], 16, (0.7, 1.1), 0.9, 2)],
        "cover": [c(P("Balloon_01"), 60, (0.8, 1.3), 5, glow=[3.0, 0.22, 0.7]), c(P("Balloon_Group_01"), 70, (0.8, 1.3), 5, glow=[3.0, 0.22, 0.7]),
                  c(P("Balloon_Group_02"), 90, (0.8, 1.3), 6, glow=[3.0, 0.22, 0.7]), c(P("Kelp_06"), 60, (0.8, 1.2), 4, glow=[3.0, 0.22, 0.7]),
                  c(P("Fester_01"), 8, (0.4, 0.6), 1, glow=[2.4, 0.22, 0.7]), c(P("Fester_02"), 10, (0.4, 0.6), 2, glow=[2.4, 0.22, 0.7]),
                  c(P("Fester_04"), 30, (0.6, 0.9), 3, glow=[2.4, 0.22, 0.7]), c(P("Tall_01"), 60, (0.7, 1.1), 4, glow=[1.6, 0.5, 0.6])],
    },
}
for _pid, _extra in ALIEN.items():
    for _k, _v in _extra.items():
        PLANETS[_pid].setdefault(_k, []).extend(_v)


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
