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
]


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
