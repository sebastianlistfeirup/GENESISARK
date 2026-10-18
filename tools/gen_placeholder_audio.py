#!/usr/bin/env python3
"""GENESIS ARK - placeholder audio generator (PROXY sounds).

Synthesises simple, licence-free placeholder sounds so the game has audio
feedback before real SFX/music exist (bible p.13, p.28: "Lokale
placeholderlyde holder udviklingen i gang").

Standard library only (wave, struct, math, random). Deterministic: fixed seed.
Output: assets/audio/placeholder/*.wav  -- 22050 Hz, mono, 16-bit PCM.

Usage:
    python3 tools/gen_placeholder_audio.py            # writes next to repo root
    python3 tools/gen_placeholder_audio.py --out DIR  # custom output dir

Loopable files (amb_*, sfx_thruster, music_hope) are built with a tail->head
crossfade and integer-cycle oscillators so the loop point does not click.
One-shots get short fade in/out. Peaks are normalised to about -6 dBFS
(music to -9 dBFS so it sits quietly under the ambience).
"""

import argparse
import math
import os
import random
import struct
import wave

SR = 22050
TWO_PI = 2.0 * math.pi
SEED = 1337

rng = random.Random(SEED)


# ---------------------------------------------------------------- helpers
def n_samples(seconds):
    return int(round(seconds * SR))


def loop_freq(freq, seconds):
    """Snap a frequency to a whole number of cycles over `seconds` (seamless loop)."""
    cycles = max(1, round(freq * seconds))
    return cycles / seconds


def sine(freq, seconds, amp=1.0, phase=0.0):
    n = n_samples(seconds)
    w = TWO_PI * freq / SR
    return [amp * math.sin(w * i + phase) for i in range(n)]


def white(seconds, amp=1.0):
    return [amp * (rng.random() * 2.0 - 1.0) for _ in range(n_samples(seconds))]


def lowpass(sig, cutoff_hz):
    """One-pole low-pass. cutoff may be a float or a per-sample list."""
    out = []
    y = 0.0
    if isinstance(cutoff_hz, (int, float)):
        a = 1.0 - math.exp(-TWO_PI * cutoff_hz / SR)
        for x in sig:
            y += a * (x - y)
            out.append(y)
    else:
        for x, c in zip(sig, cutoff_hz):
            a = 1.0 - math.exp(-TWO_PI * max(10.0, c) / SR)
            y += a * (x - y)
            out.append(y)
    return out


def highpass(sig, cutoff_hz):
    lp = lowpass(sig, cutoff_hz)
    return [x - l for x, l in zip(sig, lp)]


def mix(*sigs):
    n = max(len(s) for s in sigs)
    out = [0.0] * n
    for s in sigs:
        for i, v in enumerate(s):
            out[i] += v
    return out


def mul(sig, env):
    return [a * b for a, b in zip(sig, env)]


def gain(sig, g):
    return [v * g for v in sig]


def concat(*sigs):
    out = []
    for s in sigs:
        out.extend(s)
    return out


def silence(seconds):
    return [0.0] * n_samples(seconds)


def env_adsr(seconds, a, d, s_level, r):
    n = n_samples(seconds)
    na, nd, nr = n_samples(a), n_samples(d), n_samples(r)
    ns = max(0, n - na - nd - nr)
    env = []
    for i in range(na):
        env.append(i / max(1, na))
    for i in range(nd):
        env.append(1.0 - (1.0 - s_level) * i / max(1, nd))
    env.extend([s_level] * ns)
    for i in range(nr):
        env.append(s_level * (1.0 - i / max(1, nr)))
    return (env + [0.0] * n)[:n]


def env_exp(seconds, decay):
    """Exponential decay; `decay` = time constant in seconds."""
    return [math.exp(-(i / SR) / decay) for i in range(n_samples(seconds))]


def sweep(f0, f1, seconds, amp=1.0, curve=1.0):
    n = n_samples(seconds)
    out, ph = [], 0.0
    for i in range(n):
        t = (i / max(1, n - 1)) ** curve
        f = f0 + (f1 - f0) * t
        ph += TWO_PI * f / SR
        out.append(amp * math.sin(ph))
    return out


def fade(sig, fin=0.005, fout=0.02):
    out = list(sig)
    ni, no = n_samples(fin), n_samples(fout)
    for i in range(min(ni, len(out))):
        out[i] *= i / ni
    for i in range(min(no, len(out))):
        out[-1 - i] *= i / no
    return out


def make_loop(sig, xfade_s):
    """Fold the last `xfade_s` seconds over the start (equal-power) -> seamless loop."""
    nx = n_samples(xfade_s)
    body = list(sig[:-nx])
    tail = sig[-nx:]
    for i in range(nx):
        t = i / nx
        body[i] = body[i] * math.sin(0.5 * math.pi * t) + tail[i] * math.cos(0.5 * math.pi * t)
    return body


def normalise(sig, peak_db=-6.0):
    peak = max(1e-9, max(abs(v) for v in sig))
    target = 10.0 ** (peak_db / 20.0)
    return [v * target / peak for v in sig]


def write_wav(path, sig):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for v in sig:
            v = max(-1.0, min(1.0, v))
            frames += struct.pack("<h", int(round(v * 32767)))
        w.writeframes(bytes(frames))


def lfo(freq, seconds, lo, hi, phase=0.0):
    return [lo + (hi - lo) * 0.5 * (1 + math.sin(TWO_PI * freq * i / SR + phase))
            for i in range(n_samples(seconds))]


def note(midi):
    return 440.0 * 2 ** ((midi - 69) / 12.0)


# ---------------------------------------------------------------- ambiences (loop)
def amb_ship_hum():
    T, X = 6.0, 0.75
    L = T + X
    hum = mix(sine(loop_freq(55, T), L, 0.5), sine(loop_freq(110, T), L, 0.22),
              sine(loop_freq(165, T), L, 0.08))
    # slow beating from the second fan
    hum2 = sine(loop_freq(56.5, T), L, 0.25)
    vent = gain(lowpass(white(L), 420), 1.6)
    vent = mul(vent, lfo(1.0 / T * 2, L, 0.6, 1.0))
    # soft distant machinery ticks
    mech = silence(L)
    for k in range(9):
        start = n_samples(0.3 + k * 0.7 + rng.random() * 0.2)
        click = mul(lowpass(white(0.12), 900), env_exp(0.12, 0.03))
        for i, v in enumerate(click):
            if start + i < len(mech):
                mech[start + i] += 0.12 * v
    return make_loop(mix(hum, hum2, vent, mech), X)


def amb_colony_wind():
    T, X = 6.0, 1.0
    L = T + X
    base = white(L)
    cut = lfo(loop_freq(0.33, T), L, 250, 1100)
    gust = lowpass(base, cut)
    amp = lfo(loop_freq(0.5, T), L, 0.5, 1.0, 1.3)
    whistle = mul(lowpass(highpass(white(L), 1800), 2600), lfo(loop_freq(0.17, T), L, 0.0, 0.25))
    return make_loop(mix(mul(gust, amp), whistle), X)


def amb_space():
    T, X = 6.0, 1.0
    L = T + X
    drone = mix(sine(loop_freq(41.2, T), L, 0.5), sine(loop_freq(61.7, T), L, 0.3),
                sine(loop_freq(82.4, T), L, 0.18), sine(loop_freq(123.6, T), L, 0.07))
    shimmer = mul(sine(loop_freq(659.3, T), L, 0.03), lfo(loop_freq(0.25, T), L, 0.0, 1.0))
    air = gain(lowpass(white(L), 180), 0.9)
    return make_loop(mix(drone, shimmer, air), X)


# ---------------------------------------------------------------- UI
def ui_click():
    s = mul(mix(sine(1800, 0.04, 0.6), lowpass(white(0.04), 4000)), env_exp(0.04, 0.008))
    return fade(s, 0.001, 0.005)


def ui_hover():
    s = mul(sine(1200, 0.06, 0.5), env_adsr(0.06, 0.01, 0.02, 0.4, 0.03))
    return fade(s, 0.002, 0.01)


def ui_confirm():
    a = mul(sine(note(76), 0.09, 0.5), env_adsr(0.09, 0.005, 0.03, 0.6, 0.04))
    b = mul(mix(sine(note(83), 0.18, 0.5), sine(note(88), 0.18, 0.15)), env_adsr(0.18, 0.005, 0.05, 0.6, 0.1))
    return fade(concat(a, b), 0.002, 0.02)


def ui_error():
    def buzz(f, d):
        s = [math.copysign(1, v) * 0.3 for v in sine(f, d)]
        return mul(lowpass(s, 1400), env_adsr(d, 0.005, 0.03, 0.7, 0.04))
    return fade(concat(buzz(196, 0.11), silence(0.04), buzz(165, 0.16)), 0.002, 0.02)


# ---------------------------------------------------------------- alarms
def alarm_critical():
    # two-tone falling chime, repeated 3x: clear, urgent, not harsh
    out = []
    for _ in range(3):
        hi = mul(mix(sine(note(81), 0.22, 0.6), sine(note(93), 0.22, 0.12)), env_adsr(0.22, 0.01, 0.05, 0.7, 0.08))
        lo = mul(mix(sine(note(76), 0.3, 0.6), sine(note(88), 0.3, 0.12)), env_adsr(0.3, 0.01, 0.05, 0.6, 0.15))
        out = concat(out, hi, lo, silence(0.12))
    return fade(out, 0.003, 0.05)


def alarm_warning():
    out = []
    for _ in range(2):
        p = mul(mix(sine(note(72), 0.35, 0.6), sine(note(79), 0.35, 0.25)), env_adsr(0.35, 0.03, 0.1, 0.6, 0.15))
        out = concat(out, p, silence(0.2))
    return fade(out, 0.003, 0.05)


# ---------------------------------------------------------------- SFX
def sfx_footstep():
    thud = mul(sine(90, 0.14, 0.7), env_exp(0.14, 0.03))
    scuff = mul(lowpass(white(0.14), 2500), env_exp(0.14, 0.02))
    return fade(mix(thud, gain(scuff, 0.5)), 0.001, 0.02)


def sfx_interact():
    tick = mul(lowpass(white(0.03), 5000), env_exp(0.03, 0.006))
    tone = mul(sweep(600, 900, 0.15, 0.5), env_adsr(0.15, 0.005, 0.05, 0.5, 0.08))
    return fade(concat(tick, tone), 0.001, 0.02)


def sfx_power_on():
    d = 1.6
    rise = mul(sweep(60, 420, d, 0.5, 0.7), env_adsr(d, 0.3, 0.2, 0.9, 0.3))
    harm = mul(sweep(120, 840, d, 0.18, 0.7), env_adsr(d, 0.5, 0.2, 0.9, 0.3))
    hiss = mul(lowpass(white(d), lfo(0.5 / d, d, 300, 3000, -math.pi / 2)), env_adsr(d, 0.2, 0.3, 0.5, 0.4))
    ding = concat(silence(d - 0.4), mul(sine(note(84), 0.4, 0.3), env_exp(0.4, 0.12)))
    return fade(mix(rise, harm, gain(hiss, 0.4), ding), 0.005, 0.08)


def sfx_sample():
    d = 0.9
    whirr = mul(mix(sine(320, d, 0.3), gain(lowpass(white(d), 1500), 0.5)), lfo(18, d, 0.5, 1.0))
    whirr = mul(whirr, env_adsr(d, 0.05, 0.1, 0.8, 0.2))
    beep = mul(sine(note(86), 0.12, 0.4), env_adsr(0.12, 0.005, 0.03, 0.7, 0.05))
    return fade(concat(whirr, beep), 0.003, 0.03)


def sfx_build_place():
    clunk = mul(mix(sine(70, 0.35, 0.8), sine(140, 0.35, 0.25)), env_exp(0.35, 0.07))
    clank = mul(highpass(white(0.35), 1200), env_exp(0.35, 0.02))
    return fade(mix(clunk, gain(clank, 0.3)), 0.001, 0.05)


def sfx_build_done():
    notes = [72, 76, 79, 84]
    out = silence(1.2)
    for k, m in enumerate(notes):
        s = mul(mix(sine(note(m), 0.7, 0.4), sine(note(m) * 2, 0.7, 0.08)), env_exp(0.7, 0.25))
        off = n_samples(k * 0.11)
        for i, v in enumerate(s):
            if off + i < len(out):
                out[off + i] += v
    return fade(out, 0.002, 0.1)


def sfx_thruster():
    T, X = 3.0, 0.5
    L = T + X
    roar = lowpass(white(L), 700)
    rumble = sine(loop_freq(48, T), L, 0.3)
    flutter = lfo(loop_freq(11, T), L, 0.75, 1.0)
    return make_loop(mix(mul(gain(roar, 1.6), flutter), rumble), X)


def sfx_probe_launch():
    d = 1.4
    thump = mul(sine(55, d, 0.9), env_exp(d, 0.08))
    whoosh = mul(lowpass(white(d), lfo(0.5 / d, d, 2500, 300, -math.pi / 2)), env_adsr(d, 0.02, 0.2, 0.6, 0.9))
    tone = mul(sweep(300, 1200, d, 0.15, 0.5), env_adsr(d, 0.1, 0.3, 0.5, 0.8))
    return fade(mix(thump, whoosh, tone), 0.001, 0.1)


def sfx_scan():
    d = 1.5
    ping = mul(mix(sine(note(84), d, 0.5), sine(note(91), d, 0.12)), env_exp(d, 0.35))
    echo = concat(silence(0.35), gain(mul(sine(note(84), d - 0.35, 0.5), env_exp(d - 0.35, 0.3)), 0.35))
    swp = mul(sweep(400, 2400, d, 0.12), env_adsr(d, 0.05, 0.3, 0.3, 0.8))
    return fade(mix(ping, echo, swp), 0.002, 0.1)


# ---------------------------------------------------------------- music
def pad_chord(midis, seconds, overlap):
    L = seconds + overlap
    voices = []
    for m in midis:
        f = note(m)
        v = mix(sine(f, L, 0.22), sine(f * 1.003, L, 0.18), sine(f * 2.0, L, 0.04))
        voices.append(v)
    s = mix(*voices)
    s = lowpass(s, 1600)
    return mul(s, env_adsr(L, 1.2, 0.5, 0.85, overlap + 0.6))


def music_hope():
    # minor -> major: Am  F  C  G  | Am  F  C  G(sus->maj) ... loops to Am
    chords = [
        [45, 57, 60, 64],  # Am
        [41, 57, 60, 65],  # F
        [48, 55, 60, 64],  # C
        [43, 55, 59, 62],  # G
        [45, 57, 60, 64],  # Am
        [41, 57, 60, 65],  # F
        [48, 55, 60, 67],  # C (open)
        [43, 55, 59, 62],  # G
    ]
    seg, ov = 4.5, 1.5
    total = seg * len(chords)  # 36 s
    out = [0.0] * n_samples(total + ov)
    for k, ch in enumerate(chords):
        p = pad_chord(ch, seg, ov)
        off = n_samples(k * seg)
        for i, v in enumerate(p):
            if off + i < len(out):
                out[off + i] += v
    # gentle melody bell, sparse, rising to the major section
    mel = [(0.5, 69), (2.8, 72), (9.5, 72), (11.5, 69), (14.0, 67), (19.0, 71),
           (22.5, 72), (25.0, 76), (27.5, 79), (31.5, 74), (34.0, 71)]
    for t, m in mel:
        b = mul(mix(sine(note(m + 12), 2.0, 0.08), sine(note(m + 24), 2.0, 0.015)), env_exp(2.0, 0.6))
        off = n_samples(t)
        for i, v in enumerate(b):
            if off + i < len(out):
                out[off + i] += v
    # wrap the release tail over the start -> seamless loop
    return make_loop(out, ov)


def stinger_birth():
    d = 6.0
    chord = [48, 55, 60, 64, 67, 72]  # C major, warm, open
    voices = []
    for k, m in enumerate(chord):
        f = note(m)
        v = mix(sine(f, d, 0.2), sine(f * 1.004, d, 0.15), sine(f * 0.998, d, 0.12))
        voices.append(mul(v, env_adsr(d, 1.6 + 0.25 * k, 1.0, 0.8, 2.2)))
    s = lowpass(mix(*voices), lfo(0.5 / d, d, 500, 2200, -math.pi / 2))
    bell = concat(silence(2.2), mul(sine(note(84), d - 2.2, 0.12), env_exp(d - 2.2, 1.2)))
    return fade(mix(s, bell), 0.01, 0.3)


# ---------------------------------------------------------------- v2 cues (AUDIO_LEDGER PLANNED -> HOOKED)
# Appended after the originals so the shared RNG leaves the first 20 files byte-identical.
def _place(out, sig, t, g=1.0):
    off = n_samples(t)
    for i, v in enumerate(sig):
        if off + i < len(out):
            out[off + i] += v * g


def amb_embryo_bank():
    T, X = 8.0, 1.0
    L = T + X
    hum = mix(sine(loop_freq(73.4, T), L, 0.3), sine(loop_freq(146.8, T), L, 0.08))
    flow = mul(lowpass(white(L), 600), lfo(loop_freq(0.5, T), L, 0.25, 0.7))
    glass = mul(mix(sine(loop_freq(1174.7, T), L, 0.03), sine(loop_freq(1760.0, T), L, 0.02)),
                lfo(loop_freq(0.125, T), L, 0.0, 1.0))
    return make_loop(mix(hum, flow, glass), X)


def amb_colony_people():
    T, X = 8.0, 1.0
    L = T + X
    murmur = lowpass(highpass(white(L), 250), lfo(loop_freq(0.75, T), L, 700, 1500))
    murmur = mul(murmur, lfo(loop_freq(2.25, T), L, 0.35, 0.9))
    out = mix(gain(murmur, 0.8), silence(L))
    for k in range(6):  # distant voices / children calling: soft vowel-like tones
        d = 0.5 + rng.random() * 0.4
        f = 380 + rng.random() * 320
        v = mul(mix(sweep(f, f * (1.1 + rng.random() * 0.2), d, 0.06), sine(f * 2.01, d, 0.02)), env_adsr(d, 0.06, 0.1, 0.6, 0.25))
        _place(out, lowpass(v, 1800), 0.4 + k * 1.3 + rng.random() * 0.3)
    return make_loop(out, X)


def amb_hazard_spores():
    T, X = 6.0, 1.0
    L = T + X
    hiss = mul(lowpass(highpass(white(L), 900), 3000), lfo(loop_freq(0.66, T), L, 0.1, 0.35))
    out = list(hiss)
    for k in range(14):
        puff = mul(lowpass(white(0.18), 1200), env_exp(0.18, 0.05))
        _place(out, puff, 0.2 + k * 0.42 + rng.random() * 0.15, 0.5)
    return make_loop(out, X)


def amb_hazard_storm():
    T, X = 6.0, 1.0
    L = T + X
    wind = mul(lowpass(white(L), lfo(loop_freq(0.33, T), L, 300, 1600)), lfo(loop_freq(0.5, T), L, 0.5, 1.0, 0.7))
    rain = gain(highpass(white(L), 2500), 0.25)
    rumble = mul(lowpass(white(L), 90), lfo(loop_freq(0.17, T), L, 0.2, 0.9))
    return make_loop(mix(gain(wind, 1.2), rain, gain(rumble, 2.0)), X)


def amb_hazard_dust():
    T, X = 6.0, 1.0
    L = T + X
    grit = mul(highpass(white(L), 1500), lfo(loop_freq(1.5, T), L, 0.25, 0.6))
    roar = gain(lowpass(white(L), 400), 1.4)
    return make_loop(mix(grit, roar), X)


def amb_hazard_cold():
    T, X = 6.0, 1.0
    L = T + X
    howl = mul(lowpass(highpass(white(L), 500), lfo(loop_freq(0.25, T), L, 900, 2200)), lfo(loop_freq(0.33, T), L, 0.3, 0.9))
    whistle = mul(sine(loop_freq(1318.5, T), L, 0.05), lfo(loop_freq(0.5, T), L, 0.0, 1.0))
    heater = sine(loop_freq(120, T), L, 0.06)
    return make_loop(mix(howl, whistle, heater), X)


def _step(f_thud, cut, crunch):
    thud = mul(sine(f_thud, 0.16, 0.6), env_exp(0.16, 0.03))
    scr = mul(lowpass(highpass(white(0.16), 300), cut), env_exp(0.16, 0.025 + crunch))
    return fade(mix(thud, gain(scr, 0.8)), 0.001, 0.02)


def sfx_footstep_soil(): return _step(80, 1800, 0.01)
def sfx_footstep_soil_01(): return _step(76, 1600, 0.012)
def sfx_footstep_soil_02(): return _step(86, 2100, 0.008)
def sfx_footstep_soil_03(): return _step(72, 1400, 0.015)
def sfx_footstep_01(): return fade(mix(mul(sine(95, 0.14, 0.7), env_exp(0.14, 0.03)), gain(mul(highpass(white(0.14), 2000), env_exp(0.14, 0.015)), 0.4)), 0.001, 0.02)
def sfx_footstep_02(): return fade(mix(mul(sine(84, 0.14, 0.7), env_exp(0.14, 0.03)), gain(mul(highpass(white(0.14), 2600), env_exp(0.14, 0.012)), 0.4)), 0.001, 0.02)
def sfx_footstep_03(): return fade(mix(mul(sine(100, 0.14, 0.7), env_exp(0.14, 0.028)), gain(mul(highpass(white(0.14), 1700), env_exp(0.14, 0.018)), 0.4)), 0.001, 0.02)


def sfx_door():
    d = 1.0
    hiss = mul(lowpass(highpass(white(d), 1500), 6000), env_adsr(d, 0.02, 0.15, 0.4, 0.5))
    slide = mul(mix(sweep(140, 90, d, 0.4), lowpass(white(d), 300)), env_adsr(d, 0.1, 0.2, 0.7, 0.3))
    clunk = concat(silence(0.8), mul(sine(60, 0.2, 0.8), env_exp(0.2, 0.05)))
    return fade(mix(hiss, slide, clunk), 0.002, 0.05)


def sfx_sample_loop():
    T, X = 2.0, 0.3
    L = T + X
    drill = mix(sine(loop_freq(220, T), L, 0.25), sine(loop_freq(440, T), L, 0.1), gain(lowpass(white(L), 2200), 0.6))
    return make_loop(mul(drill, lfo(loop_freq(24, T), L, 0.6, 1.0)), X)


def sfx_relay_place():
    out = silence(1.8)
    for k in range(3):
        _place(out, mul(highpass(white(0.12), 1500), env_exp(0.12, 0.03)), 0.05 + k * 0.22, 0.5)
        _place(out, mul(sine(160 + k * 30, 0.2, 0.5), env_exp(0.2, 0.05)), 0.05 + k * 0.22)
    _place(out, mul(sweep(300, 900, 0.5, 0.25), env_adsr(0.5, 0.05, 0.1, 0.6, 0.2)), 0.75)
    for k in range(3):
        _place(out, mul(sine(note(88 + 2 * k), 0.08, 0.3), env_exp(0.08, 0.03)), 1.3 + k * 0.1)
    return fade(out, 0.001, 0.05)


def sfx_drone_refill():
    d = 2.6
    buzz = mul(mix(sine(180, d, 0.2), sine(183, d, 0.2), gain(lowpass(white(d), 900), 0.4)),
               env_adsr(d, 0.6, 0.2, 0.8, 0.9))
    drop = concat(silence(1.2), mul(sine(70, 0.3, 0.8), env_exp(0.3, 0.06)))
    return fade(mix(buzz, drop), 0.01, 0.2)


def sfx_ring_pass():
    d = 1.0
    whoosh = mul(lowpass(white(d), lfo(1.0 / d, d, 400, 3000, -math.pi / 2)), env_adsr(d, 0.25, 0.2, 0.4, 0.5))
    chime = mul(mix(sine(note(84), d, 0.25), sine(note(91), d, 0.12), sine(note(96), d, 0.06)), env_exp(d, 0.35))
    return fade(mix(whoosh, concat(silence(0.25), chime)), 0.005, 0.1)


def sfx_landing():
    d = 7.0
    roar = mul(lowpass(white(d), lfo(0.5 / d, d, 1400, 250, 0.0)), env_adsr(d, 0.8, 1.0, 0.8, 1.5))
    rumble = mul(sine(38, d, 0.5), env_adsr(d, 1.0, 1.0, 0.9, 1.8))
    out = mix(gain(roar, 1.4), rumble)
    _place(out, mul(mix(sine(45, 0.8, 1.0), lowpass(white(0.8), 300)), env_exp(0.8, 0.2)), 4.6)
    for k in range(3):
        _place(out, mul(sweep(220 - k * 30, 150 - k * 20, 0.6, 0.15), env_adsr(0.6, 0.1, 0.1, 0.6, 0.3)), 5.3 + k * 0.5)
    return fade(out, 0.05, 0.4)


def sfx_build_loop():
    T, X = 4.0, 0.5
    L = T + X
    out = gain(lowpass(white(L), 500), 0.3)
    for k in range(10):
        _place(out, mul(highpass(white(0.05), 2500), env_exp(0.05, 0.01)), 0.15 + k * 0.38, 0.6)
    weld = mul(highpass(white(1.2), 3000), lfo(30, 1.2, 0.3, 1.0))
    _place(out, mul(weld, env_adsr(1.2, 0.05, 0.1, 0.8, 0.2)), 1.8, 0.3)
    return make_loop(out, X)


def sfx_demolish():
    out = silence(1.8)
    for k in range(4):
        _place(out, mul(mix(sine(110 - k * 12, 0.3, 0.5), highpass(white(0.3), 1200)), env_exp(0.3, 0.05)), k * 0.33, 0.7)
    _place(out, mul(lowpass(white(0.6), 500), env_exp(0.6, 0.15)), 1.2)
    return fade(out, 0.001, 0.08)


def sfx_power_cut():
    d = 1.3
    fall = mul(mix(sweep(420, 60, d, 0.5, 0.6), sweep(840, 120, d, 0.15, 0.6)), env_adsr(d, 0.01, 0.2, 0.8, 0.5))
    clack = mul(highpass(white(0.06), 1500), env_exp(0.06, 0.01))
    return fade(mix(concat(clack, silence(d - 0.06)), fall), 0.001, 0.1)


def sfx_incubation_start():
    d = 3.6
    pad = mul(mix(sine(note(60), d, 0.15), sine(note(67), d, 0.12), sine(note(72), d, 0.08)), env_adsr(d, 1.0, 0.5, 0.8, 1.2))
    out = list(pad)
    for k in range(4):  # heartbeat-like double pulse
        _place(out, mul(sine(62, 0.12, 0.6), env_exp(0.12, 0.03)), 0.6 + k * 0.75)
        _place(out, mul(sine(55, 0.12, 0.4), env_exp(0.12, 0.03)), 0.78 + k * 0.75)
    return fade(out, 0.01, 0.3)


def music_ark_alone():
    # sparse, lonely: Dm add9 drone, long gaps, single cello-like line
    chords = [[38, 50, 57, 64], [38, 50, 55, 62], [34, 50, 57, 62], [36, 48, 55, 62]]
    seg, ov = 6.0, 2.0
    out = [0.0] * n_samples(seg * len(chords) + ov)
    for k, ch in enumerate(chords):
        _place(out, gain(pad_chord(ch, seg, ov), 0.7), k * seg)
    for t, m in [(1.0, 62), (4.5, 60), (9.0, 57), (14.0, 58), (18.5, 57)]:
        d = 3.0
        cello = mul(mix(sine(note(m - 12), d, 0.12), sine(note(m - 12) * 2, d, 0.04), sine(note(m - 12) * 3, d, 0.015)),
                    mul(env_adsr(d, 0.6, 0.4, 0.8, 1.2), lfo(5.0, d, 0.9, 1.0)))
        _place(out, cello, t)
    return make_loop(out, ov)


def stinger_crisis():
    d = 4.5
    low = mul(mix(sine(note(38), d, 0.3), sine(note(39), d, 0.2), sine(note(50), d, 0.12)), env_adsr(d, 1.8, 0.5, 0.9, 1.5))
    swell = mul(lowpass(mix(sine(note(62), d, 0.1), sine(note(63), d, 0.08)), 1200), env_adsr(d, 2.2, 0.3, 0.8, 1.4))
    return fade(mix(low, swell), 0.01, 0.3)


def _ending(chords, mel, seg, warmth):
    ov = 2.0
    out = [0.0] * n_samples(seg * len(chords) + ov + 2.0)
    for k, ch in enumerate(chords):
        _place(out, pad_chord(ch, seg, ov), k * seg)
    for t, m in mel:
        b = mul(mix(sine(note(m + 12), 2.5, 0.09), sine(note(m + 24), 2.5, 0.02 * warmth)), env_exp(2.5, 0.8))
        _place(out, b, t)
    return fade(out, 0.05, 2.0)


def music_ending_independent():
    return _ending([[48, 55, 60, 64], [41, 57, 60, 65], [45, 57, 60, 64], [43, 55, 59, 62], [48, 55, 64, 72]],
                   [(0.5, 72), (3.0, 76), (5.5, 79), (10.5, 81), (13.0, 79), (16.0, 76), (20.5, 84)], 4.5, 1.5)


def music_ending_shielded():
    return _ending([[45, 57, 60, 64], [41, 57, 60, 65], [48, 55, 60, 64], [43, 55, 59, 62], [48, 55, 60, 67]],
                   [(1.0, 69), (5.0, 72), (9.5, 71), (14.0, 72), (19.0, 76)], 4.5, 1.0)


def music_ending_fragile():
    return _ending([[45, 57, 60, 64], [41, 53, 57, 60], [43, 55, 58, 62], [45, 57, 60, 66]],
                   [(1.0, 69), (6.5, 67), (12.0, 65), (17.5, 66)], 5.0, 0.5)


SOUNDS = [
    ("amb_ship_hum", amb_ship_hum, -6.0),
    ("amb_colony_wind", amb_colony_wind, -6.0),
    ("amb_space", amb_space, -6.0),
    ("ui_click", ui_click, -6.0),
    ("ui_hover", ui_hover, -6.0),
    ("ui_confirm", ui_confirm, -6.0),
    ("ui_error", ui_error, -6.0),
    ("alarm_critical", alarm_critical, -6.0),
    ("alarm_warning", alarm_warning, -6.0),
    ("sfx_footstep", sfx_footstep, -6.0),
    ("sfx_interact", sfx_interact, -6.0),
    ("sfx_power_on", sfx_power_on, -6.0),
    ("sfx_sample", sfx_sample, -6.0),
    ("sfx_build_place", sfx_build_place, -6.0),
    ("sfx_build_done", sfx_build_done, -6.0),
    ("sfx_thruster", sfx_thruster, -6.0),
    ("sfx_probe_launch", sfx_probe_launch, -6.0),
    ("sfx_scan", sfx_scan, -6.0),
    ("music_hope", music_hope, -9.0),
    ("stinger_birth", stinger_birth, -6.0),
] + [(fn.__name__, fn, -9.0 if fn.__name__.startswith("music_") else -6.0) for fn in [
    amb_embryo_bank, amb_colony_people, amb_hazard_spores, amb_hazard_storm, amb_hazard_dust, amb_hazard_cold,
    sfx_footstep_soil, sfx_footstep_soil_01, sfx_footstep_soil_02, sfx_footstep_soil_03,
    sfx_footstep_01, sfx_footstep_02, sfx_footstep_03, sfx_door, sfx_sample_loop, sfx_relay_place,
    sfx_drone_refill, sfx_ring_pass, sfx_landing, sfx_build_loop, sfx_demolish, sfx_power_cut,
    sfx_incubation_start, music_ark_alone, stinger_crisis, music_ending_independent, music_ending_shielded,
    music_ending_fragile]]


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default_out = os.path.join(os.path.dirname(here), "assets", "audio", "placeholder")
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default=default_out)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    total = 0
    for name, fn, peak in SOUNDS:
        sig = normalise(fn(), peak)
        path = os.path.join(args.out, name + ".wav")
        write_wav(path, sig)
        size = os.path.getsize(path)
        total += size
        print("%-20s %6.2f s  %8d bytes" % (name, len(sig) / SR, size))
    print("total %.2f MB" % (total / 1e6))


if __name__ == "__main__":
    main()
