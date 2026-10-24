#!/usr/bin/env python3
"""Generates data/art/asset_slots.json: the proxy (greybox) definition for every
VisualSlot. Existing "scene" mappings made by the owner are preserved on rerun.
Run: python3 tools/gen_asset_slots.py"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "art", "asset_slots.json")

PETROL = "#1f6f78"; PETROL_D = "#173b45"; STEEL = "#3b4a54"; STEEL_L = "#6a7c86"; AMBER = "#e8a33d"
WHITE = "#d8e2e6"; DARK = "#1b252c"; GREEN = "#5fae6e"; BLUE = "#4fa3d9"; RED = "#d25b4c"

def box(size, pos=(0, None, 0), color=STEEL, rot=0.0, emissive=None):
    p = [pos[0], size[1] / 2 if pos[1] is None else pos[1], pos[2]]
    d = {"shape": "box", "size": list(size), "pos": p, "color": color}
    if rot: d["rot_y"] = rot
    if emissive: d["emissive"] = emissive
    return d

def cyl(r, h, pos=(0, None, 0), color=STEEL, emissive=None, top=None):
    d = {"shape": "cylinder", "radius": r, "height": h, "pos": [pos[0], h / 2 if pos[1] is None else pos[1], pos[2]], "color": color}
    if top is not None: d["top_radius"] = top
    if emissive: d["emissive"] = emissive
    return d

def sph(r, pos=(0, None, 0), color=STEEL, emissive=None):
    d = {"shape": "sphere", "radius": r, "pos": [pos[0], r if pos[1] is None else pos[1], pos[2]], "color": color}
    if emissive: d["emissive"] = emissive
    return d

def cap(r, h, pos=(0, None, 0), color=STEEL):
    return {"shape": "capsule", "radius": r, "height": h, "pos": [pos[0], h / 2 if pos[1] is None else pos[1], pos[2]], "color": color}

S = {}
# --- Ship modular kit (4 m grid)
S["ship.floor"] = [box((4, 0.2, 4), (0, -0.1, 0), "#26343c")]
S["ship.wall"] = [box((4, 3.6, 0.3), color=STEEL), box((4, 0.25, 0.32), (0, 3.4, 0), PETROL_D), box((3.6, 0.08, 0.34), (0, 1.1, 0), PETROL, emissive=0.4)]
S["ship.wall_window"] = [box((4, 0.9, 0.3), color=STEEL), box((4, 0.6, 0.3), (0, 3.3, 0), STEEL), box((3.6, 2.1, 0.1), (0, 1.95, 0), "#0b1a2a", emissive=0.15)]
S["ship.door"] = [box((0.5, 3.6, 0.5), (-1.75, None, 0), STEEL_L), box((0.5, 3.6, 0.5), (1.75, None, 0), STEEL_L), box((4, 0.5, 0.5), (0, 3.35, 0), STEEL_L), box((3, 0.1, 0.55), (0, 3.05, 0), AMBER, emissive=0.8)]
S["ship.ceiling_light"] = [box((1.6, 0.1, 0.4), (0, 3.55, 0), WHITE, emissive=1.5)]
S["ship.pillar"] = [box((0.6, 3.6, 0.6), color=STEEL_L)]
S["ship.terminal"] = [box((0.9, 1.0, 0.6), color=STEEL), box((0.8, 0.55, 0.06), (0, 1.3, -0.1), "#0d2b33", emissive=0.9)]
S["ship.terminal_bridge"] = [box((2.2, 0.9, 0.9), color=STEEL), box((2.0, 0.7, 0.06), (0, 1.35, -0.25), "#0d2b33", emissive=1.0)]
S["ship.starmap_table"] = [cyl(1.4, 0.9, color=STEEL), cyl(1.2, 0.05, (0, 0.95, 0), PETROL, emissive=1.2), sph(0.35, (0, 1.6, 0), AMBER, emissive=0.8)]
S["ship.captain_chair"] = [box((0.8, 0.5, 0.8), color=DARK), box((0.8, 1.0, 0.15), (0, 0.9, 0.35), DARK)]
S["ship.embryo_tank"] = [cyl(0.45, 2.4, color=STEEL_L), cyl(0.38, 1.8, (0, 1.2, 0), "#7fd6d0", emissive=0.6)]
S["ship.embryo_bank_core"] = [cyl(1.6, 0.6, color=STEEL), cyl(1.1, 2.6, (0, 1.9, 0), "#2a7f86", emissive=0.5), cyl(1.6, 0.3, (0, 3.35, 0), STEEL)]
S["ship.cryo_pod"] = [box((1.0, 0.6, 2.2), color=STEEL_L), box((0.9, 0.3, 1.9), (0, 0.75, 0), "#9fd6e0", emissive=0.3)]
S["ship.workbench"] = [box((2.2, 0.95, 1.0), color=STEEL), box((2.0, 0.05, 0.8), (0, 0.98, 0), AMBER)]
S["ship.power_coupling"] = [box((1.4, 2.2, 0.4), color=DARK), cyl(0.25, 0.5, (0, 1.2, -0.3), AMBER, emissive=0.6)]
S["ship.robot_station"] = [box((1.6, 0.2, 1.6), color=STEEL), box((1.4, 2.4, 0.3), (0, 1.2, 0.65), STEEL_L)]
S["ship.crate"] = [box((1.0, 0.8, 1.0), color="#5b6770")]
S["ship.pipe"] = [cyl(0.15, 4.0, (0, 2.0, 0), STEEL_L)]
S["ship.window_space"] = [box((4, 2.4, 0.05), (0, 1.9, 0), "#050a12", emissive=0.05)]
# --- Characters
S["char.captain"] = [cap(0.32, 1.75, color="#c9d3d8"), box((0.36, 0.14, 0.12), (0, 1.55, -0.26), AMBER, emissive=0.8), box((0.42, 0.5, 0.22), (0, 1.2, 0.25), STEEL)]
S["char.ark_ai_hologram"] = [sph(0.35, (0, 1.6, 0), "#7fd6d0", emissive=2.0), cyl(0.5, 0.05, (0, 0.02, 0), PETROL, emissive=1.0)]
S["char.robot_worker"] = [box((0.7, 0.9, 0.5), (0, 0.85, 0), "#c8a24a"), box((0.4, 0.3, 0.3), (0, 1.45, 0), "#3a3a3a"), cyl(0.12, 0.4, (0.2, 0.2, 0), DARK), cyl(0.12, 0.4, (-0.2, 0.2, 0), DARK)]
S["char.robot_drone"] = [sph(0.3, (0, 0.3, 0), "#c8a24a"), box((0.9, 0.05, 0.1), (0, 0.35, 0), DARK)]
S["char.citizen_adult"] = [cap(0.28, 1.7, color="#b8865b")]
S["char.citizen_child"] = [cap(0.22, 1.15, color="#d0a070")]
# --- Buildings (footprints from data/buildings/buildings.json)
S["building.ark_core"] = [box((14, 6, 10), color="#4a5a64"), box((10, 3, 7), (0, 7.5, 0), "#56707a"), cyl(1.2, 4, (4.5, 8, 2.5), STEEL_L), box((14.2, 0.3, 10.2), (0, 3.2, 0), PETROL, emissive=0.6)]
S["building.solar_array"] = [box((0.3, 1.2, 0.3), (-2, None, 0), STEEL), box((0.3, 1.2, 0.3), (2, None, 0), STEEL), box((5.6, 0.1, 5.6), (0, 1.3, 0), "#1d3a6b", emissive=0.15)]
S["building.geothermal_generator"] = [cyl(2.6, 3.5, color="#7a5a48"), cyl(1.0, 3.0, (0, 5.0, 0), STEEL_L), cyl(1.4, 0.3, (0, 3.6, 0), AMBER, emissive=0.8)]
S["building.battery"] = [box((3.6, 2.2, 3.6), color="#3c4d39"), box((3.0, 0.15, 3.0), (0, 2.3, 0), GREEN, emissive=0.8)]
S["building.water_plant"] = [box((5.6, 2.6, 4.0), (0, None, -1.8), STEEL_L), cyl(1.4, 4.0, (-1.4, None, 2.0), "#5a87a0"), cyl(1.4, 4.0, (1.6, None, 2.0), "#5a87a0"), box((5.7, 0.2, 0.2), (0, 2.7, -1.8), BLUE, emissive=0.8)]
S["building.greenhouse"] = [box((7.6, 0.4, 5.6), color=STEEL), box((7.4, 2.6, 5.4), (0, 1.7, 0), "#8fd18f", emissive=0.25)]
S["building.mine"] = [box((7.6, 1.2, 7.6), color="#5d4c3e"), box((2.0, 6.0, 2.0), (0, 3.0, 0), STEEL), box((4.5, 0.4, 0.6), (1.5, 5.6, 0), AMBER)]
S["building.workshop"] = [box((7.6, 3.8, 5.6), color="#6b6f74"), box((3.0, 2.6, 0.2), (0, 1.3, -2.85), AMBER, emissive=0.3)]
S["building.drone_hub"] = [cyl(2.8, 1.0, color=STEEL), box((0.5, 3.0, 0.5), (0, 2.0, 0), STEEL_L), cyl(1.6, 0.2, (0, 3.6, 0), PETROL, emissive=1.0)]
S["building.habitat"] = [box((9.6, 3.2, 7.6), color="#cfd8dc"), box((9.0, 0.3, 7.0), (0, 3.3, 0), STEEL), box((9.7, 0.4, 0.1), (0, 2.0, -3.85), AMBER, emissive=1.2)]
S["building.care_center"] = [box((9.6, 3.6, 9.6), color="#e2e7e2"), cyl(3.0, 1.6, (0, 4.4, 0), "#f2d8a7", emissive=0.5), box((9.7, 0.3, 0.1), (0, 2.4, -4.85), "#f0c070", emissive=1.0)]
S["building.clinic"] = [box((7.6, 3.0, 5.6), color="#e6eef0"), box((1.4, 0.4, 0.1), (0, 2.4, -2.85), RED, emissive=1.0), box((0.4, 1.4, 0.1), (0, 2.4, -2.86), RED, emissive=1.0)]
S["building.school_hall"] = [box((9.6, 3.4, 7.6), color="#d8c8a8"), box((10.0, 0.4, 8.0), (0, 3.6, 0), "#8a6a4a"), box((1.6, 4.0, 1.6), (3.5, 5.0, 2.5), "#d8c8a8")]
S["building.module_filter"] = [box((1.6, 1.2, 1.6), (0, None, 0), "#9fb5a0"), cyl(0.5, 0.4, (0, 1.4, 0), GREEN, emissive=0.6)]
S["building.module_heater"] = [box((1.6, 1.2, 1.6), (0, None, 0), "#a07a60"), cyl(0.5, 0.4, (0, 1.4, 0), AMBER, emissive=0.8)]
S["building.construction_frame"] = [box((1.0, 1.0, 1.0), color=AMBER)]
# --- Surface
S["surface.lander"] = [cyl(2.2, 2.5, (0, 1.6, 0), STEEL_L, top=1.2), box((0.25, 1.4, 0.25), (1.8, 0.7, 1.8), STEEL), box((0.25, 1.4, 0.25), (-1.8, 0.7, 1.8), STEEL), box((0.25, 1.4, 0.25), (1.8, 0.7, -1.8), STEEL), box((0.25, 1.4, 0.25), (-1.8, 0.7, -1.8), STEEL), cyl(1.0, 0.3, (0, 3.0, 0), AMBER, emissive=0.8)]
S["surface.rock_small"] = [sph(0.8, (0, 0.4, 0), "#6c6c66")]
S["surface.rock_large"] = [box((3.0, 2.4, 2.6), (0, 1.0, 0), "#5f5d58", rot=0.4)]
S["surface.tree_green"] = [cyl(0.25, 3.0, color="#5a4632"), sph(1.6, (0, 3.8, 0), "#3f7a3a"), sph(1.1, (0.6, 4.8, 0.3), "#4f8a3a")]
S["surface.plant_green"] = [sph(0.6, (0, 0.4, 0), "#5e9a48"), sph(0.3, (0.3, 0.9, 0), "#d6c447", emissive=0.4)]
S["surface.crystal_ice"] = [cyl(0.5, 2.2, color="#bfe6f5", top=0.05, emissive=0.3)]
S["surface.ice_spire"] = [cyl(1.2, 6.0, color="#d8edf5", top=0.1)]
S["surface.desert_rock"] = [box((4.0, 5.0, 3.0), (0, 2.0, 0), "#9a5b3a", rot=0.3), box((2.4, 2.0, 2.0), (1.6, 5.2, 0.4), "#a8653f")]
S["surface.sample_marker"] = [cyl(0.08, 2.2, color=WHITE), sph(0.25, (0, 2.3, 0), AMBER, emissive=2.0)]
S["surface.relay_beacon"] = [box((0.6, 0.4, 0.6), color=STEEL), cyl(0.06, 2.8, (0, 1.8, 0), STEEL_L), sph(0.2, (0, 3.3, 0), PETROL, emissive=2.0)]
S["surface.hazard_marker"] = [cyl(0.1, 1.6, color=DARK), box((0.6, 0.6, 0.05), (0, 1.5, 0), "#d6c447", emissive=0.8)]
# --- Space
S["space.ark_exterior"] = [box((6, 4, 26), color="#5a6870"), cyl(3.2, 6, (0, 0, -14), STEEL_L), box((14, 0.6, 5), (0, 0, 4), "#46555d"), sph(1.0, (0, 0, -18), "#ffb050", emissive=3.0)]
S["space.planet_green"] = [sph(60, (0, 0, 0), "#4f8a5a")]
S["space.planet_desert"] = [sph(60, (0, 0, 0), "#c08850")]
S["space.planet_ice"] = [sph(60, (0, 0, 0), "#cfe3ea")]
S["space.asteroid"] = [sph(2.0, (0, 0, 0), "#5e5850")]
S["space.approach_ring"] = [{"shape": "torus", "inner": 5.5, "outer": 6.2, "pos": [0, 0, 0], "color": PETROL, "emissive": 1.5, "rot_x": 90}]
# --- FX (proxy = small emissive hint; real FX via particle scenes)
for fx, col in {"fx.spores": "#d6c447", "fx.dust": "#b08a5a", "fx.snow": "#ffffff", "fx.storm": "#6b7fd6", "fx.steam_vent": "#e6eef0", "fx.smoke_plume": "#4a4642", "fx.smoke_toxic": "#c8e04a",
                "fx.thruster": "#7fd6ff", "fx.construction_sparks": AMBER, "fx.power_surge": "#7fd6d0", "fx.scan_pulse": PETROL, "fx.landing_dust": "#b08a5a"}.items():
    S[fx] = [{"shape": "particles", "color": col, "amount": 64, "extent": [6, 3, 6]}]
# --- UI (2D slots: "texture" path when mapped; proxy is a flat color)
for ui, col in {"ui.panel": "#0f1c24", "ui.button": "#1f6f78", "ui.icon_power": AMBER, "ui.icon_water": BLUE, "ui.icon_food": GREEN,
                "ui.icon_alloy": STEEL_L, "ui.icon_components": "#c8a24a", "ui.icon_embryo": "#7fd6d0", "ui.icon_population": "#f0c070",
                "ui.icon_fuel": "#ffb050", "ui.icon_integrity": "#a8c0c8", "ui.hud_frame": "#1f6f78", "ui.crosshair_interact": "#ffffff"}.items():
    S[ui] = [{"shape": "ui", "color": col}]

old = {}
if os.path.exists(OUT):
    old = json.load(open(OUT)).get("slots", {})
slots = {}
for sid, parts in S.items():
    prev = old.get(sid, {})
    slots[sid] = {
        "scene": prev.get("scene", ""),
        "scale": prev.get("scale", 1.0),
        "offset": prev.get("offset", [0, 0, 0]),
        "rotation_y": prev.get("rotation_y", 0),
        "proxy": parts,
    }
doc = {"_note": "VisualSlot registry. Set \"scene\" to a res:// path of an imported Synty wrapper scene (art/prefabs/...) to replace the proxy everywhere. scale/offset/rotation_y adjust the imported scene. Regenerate proxies with tools/gen_asset_slots.py (keeps your scene mappings).",
       "slots": slots}
json.dump(doc, open(OUT, "w"), indent=1, ensure_ascii=False)
sug = json.load(open(os.path.join(ROOT, "data/art/synty_suggestions.json")))["slots"]
missing = sorted(set(sug) - set(slots)); extra = sorted(set(slots) - set(sug))
print("slots:", len(slots), "missing vs suggestions:", missing, "extra:", extra)
