#!/usr/bin/env python3
"""Synthesises Klay's 28 UI sounds into NotchBuddy/Resources/sounds/.

Every sound is generated from scratch here (FM marimba / bell voices, sine
sweeps and a little filtered noise), so the set can be regenerated and tuned
without any third-party asset:

    python3 scripts/gen-sounds.py

Output: mono, 16-bit PCM, 44.1 kHz WAV. Peaks are normalised to -3.5 dBFS
(-14 dBFS for the very quiet tick / hover / blip) and every file gets a short
fade in and out so nothing clicks. Deterministic: the noise generator is seeded.
"""

import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "NotchBuddy", "Resources", "sounds")
RNG = np.random.default_rng(20261008)


# ── Building blocks ──────────────────────────────────────────────────────────

def t_axis(dur):
    return np.arange(int(round(dur * SR))) / SR


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def env(dur, attack=0.004, decay=0.25):
    """Fast attack, exponential decay (decay = time constant in seconds)."""
    t = t_axis(dur)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) / decay)


def marimba(freq, dur, decay=0.18, bright=1.6):
    """Warm wooden bar: FM with ratio 1 whose index falls quickly, plus a soft 4x partial."""
    t = t_axis(dur)
    idx = bright * np.exp(-t / 0.03)
    mod = idx * np.sin(2 * np.pi * freq * t)
    body = np.sin(2 * np.pi * freq * t + mod)
    over = 0.18 * np.sin(2 * np.pi * freq * 4.0 * t) * np.exp(-t / 0.02)
    return (body + over) * env(dur, 0.003, decay)


def bell(freq, dur, decay=0.35, bright=1.2):
    """Small glassy bell: FM ratio 3.5 with a gently falling index."""
    t = t_axis(dur)
    idx = bright * np.exp(-t / 0.12)
    mod = idx * np.sin(2 * np.pi * freq * 3.5 * t)
    body = np.sin(2 * np.pi * freq * t + mod)
    return body * env(dur, 0.002, decay)


def glide(f0, f1, dur, curve=1.0, harmonics=(1.0, 0.25, 0.08), vibrato=0.0, vib_rate=6.0):
    """Phase-continuous pitch sweep with a few soft harmonics."""
    t = t_axis(dur)
    x = (t / dur) ** curve if dur > 0 else t
    f = f0 * (f1 / f0) ** x  # exponential (musical) glide
    if vibrato:
        f = f * (1 + vibrato * np.sin(2 * np.pi * vib_rate * t))
    phase = 2 * np.pi * np.cumsum(f) / SR
    out = np.zeros_like(t)
    for k, a in enumerate(harmonics, start=1):
        out += a * np.sin(k * phase)
    return out


def shape(sig, attack=0.01, release=0.05, hold_curve=1.0):
    """Linear-ish attack, smooth (raised cosine) release over the tail."""
    n = len(sig)
    e = np.ones(n)
    na = max(1, int(attack * SR))
    nr = max(1, int(release * SR))
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] *= 0.5 * (1 + np.cos(np.linspace(0, np.pi, nr)))
    if hold_curve != 1.0:
        e *= np.linspace(1, hold_curve, n)
    return sig * e


def noise(dur, lp=4000.0, hp=0.0):
    """Seeded white noise through simple one-pole low/high-pass filters."""
    n = int(round(dur * SR))
    x = RNG.standard_normal(n)
    a = np.exp(-2 * np.pi * lp / SR)
    y = np.zeros(n)
    acc = 0.0
    for i in range(n):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    if hp > 0:
        b = np.exp(-2 * np.pi * hp / SR)
        z = np.zeros(n)
        lo = 0.0
        for i in range(n):
            lo = (1 - b) * y[i] + b * lo
            z[i] = y[i] - lo
        y = z
    return y / (np.max(np.abs(y)) + 1e-9)


def mix(total, *parts):
    """parts: (start_seconds, signal, gain)."""
    out = np.zeros(int(round(total * SR)))
    for start, sig, gain in parts:
        s = int(round(start * SR))
        n = min(len(sig), len(out) - s)
        if n > 0:
            out[s:s + n] += gain * sig[:n]
    return out


def seq(notes, voice=marimba, step=0.08, tail=0.3, gains=None, **kw):
    """Plays midi notes one after another with the given voice."""
    total = step * (len(notes) - 1) + tail
    parts = []
    for i, m in enumerate(notes):
        g = gains[i] if gains else 1.0
        parts.append((i * step, voice(hz(m), tail, **kw), g))
    return mix(total, *parts)


# ── The palette ──────────────────────────────────────────────────────────────
# Home key: C major pentatonic around C5–C7. Notes as midi (C5 = 72).

def s_annoyed():
    # "hmph": two short low notes, the second flatter, with a little wobble
    a = glide(hz(62), hz(60), 0.14, harmonics=(1, 0.35, 0.12)) * env(0.14, 0.006, 0.08)
    b = glide(hz(60), hz(56), 0.2, harmonics=(1, 0.35, 0.12), vibrato=0.012, vib_rate=11) * env(0.2, 0.006, 0.1)
    return mix(0.34, (0, a, 1), (0.12, b, 1))


def s_approval():
    # gentle two-tone attention chime, rising a major sixth
    return mix(0.75,
               (0.0, bell(hz(79), 0.6, decay=0.3), 1.0),
               (0.0, marimba(hz(67), 0.4, decay=0.2), 0.35),
               (0.16, bell(hz(88), 0.59, decay=0.32), 0.9),
               (0.16, marimba(hz(76), 0.4, decay=0.2), 0.3))


def s_approve():
    return seq([84, 91], voice=marimba, step=0.07, tail=0.2, gains=[0.8, 1.0], decay=0.08)


def s_attach():
    click = noise(0.012, lp=6000) * env(0.012, 0.0005, 0.003)
    return mix(0.16, (0, click, 0.3), (0.006, marimba(hz(81), 0.15, decay=0.05), 1.0))


def s_blip():
    return marimba(hz(93), 0.05, decay=0.015, bright=0.8)


def s_close():
    return seq([79, 72], voice=marimba, step=0.07, tail=0.18, gains=[1.0, 0.8], decay=0.06)


def s_dizzy():
    # spiralling wobble that slowly sinks
    t = t_axis(0.85)
    f = hz(79) * 2 ** (-t / 0.85 * 1.0) * (1 + 0.06 * np.sin(2 * np.pi * 7 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    sig = np.sin(ph) + 0.2 * np.sin(2 * ph)
    trem = 0.75 + 0.25 * np.sin(2 * np.pi * 5 * t)
    return shape(sig * trem, attack=0.02, release=0.25)


def s_error():
    # soft low descending pair
    return mix(0.5,
               (0.0, marimba(hz(64), 0.3, decay=0.12, bright=1.0), 1.0),
               (0.15, marimba(hz(59), 0.35, decay=0.14, bright=1.0), 1.0))


def s_finish():
    # bright ascending arpeggio, ending on a sparkle
    notes = [72, 76, 79, 84, 88]
    parts = [(i * 0.065, bell(hz(m), 0.45, decay=0.18 + 0.04 * i), 0.7 + 0.06 * i) for i, m in enumerate(notes)]
    parts += [(i * 0.065, marimba(hz(m), 0.25, decay=0.07), 0.35) for i, m in enumerate(notes)]
    return mix(0.75, *parts)


def s_greet():
    return seq([79, 84], voice=marimba, step=0.09, tail=0.22, gains=[0.85, 1.0], decay=0.09)


def s_greeting():
    # a little rising three-note motif, then a held sparkle
    motif = [(0.0, 72), (0.17, 76), (0.34, 79)]
    parts = []
    for s, m in motif:
        parts.append((s, marimba(hz(m), 0.5, decay=0.16), 0.9))
        parts.append((s, bell(hz(m + 12), 0.5, decay=0.12, bright=0.7), 0.25))
    parts.append((0.55, bell(hz(84), 0.85, decay=0.32), 0.85))
    parts.append((0.55, marimba(hz(72), 0.75, decay=0.28, bright=0.8), 0.45))
    parts.append((0.55, marimba(hz(79), 0.75, decay=0.28, bright=0.8), 0.3))
    return mix(1.4, *parts)


def s_gulp():
    sig = glide(560, 190, 0.17, curve=0.6, harmonics=(1, 0.3, 0.1))
    return sig * env(0.17, 0.008, 0.07)


def s_hover():
    return marimba(hz(96), 0.035, decay=0.01, bright=0.5)


def s_love():
    # warm "aww": two notes with a soft vibrato, a sparkle on top
    a = glide(hz(76), hz(76), 0.5, vibrato=0.008, vib_rate=5.5, harmonics=(1, 0.2)) * env(0.5, 0.02, 0.22)
    b = glide(hz(81), hz(81), 0.42, vibrato=0.008, vib_rate=5.5, harmonics=(1, 0.2)) * env(0.42, 0.02, 0.2)
    return mix(0.58, (0, a, 0.7), (0.12, b, 0.8), (0.12, bell(hz(93), 0.4, decay=0.15), 0.25))


def s_open():
    return seq([72, 79], voice=marimba, step=0.07, tail=0.18, gains=[0.8, 1.0], decay=0.06)


def s_peek():
    sig = glide(hz(79), hz(86), 0.11, curve=0.7, harmonics=(1, 0.15))
    return sig * env(0.11, 0.005, 0.05)


def s_pop():
    sig = glide(320, 980, 0.07, curve=0.5, harmonics=(1, 0.1))
    return sig * env(0.07, 0.002, 0.022)


def s_proud():
    notes = [79, 84, 88]
    parts = [(i * 0.08, marimba(hz(m), 0.3, decay=0.1), 0.8) for i, m in enumerate(notes)]
    parts.append((0.24, bell(hz(91), 0.36, decay=0.18), 0.6))
    parts.append((0.24, marimba(hz(84), 0.36, decay=0.18), 0.4))
    return mix(0.6, *parts)


def s_question():
    # rising inflection: a short note that bends upward
    sig = glide(hz(72), hz(79), 0.28, curve=2.2, harmonics=(1, 0.3, 0.1))
    t = t_axis(0.28)
    return sig * np.minimum(1, t / 0.01) * (0.55 + 0.45 * np.exp(-t / 0.08)) * np.cos(np.pi / 2 * t / 0.28) ** 0.5


def s_rate():
    return seq([81, 86], voice=marimba, step=0.08, tail=0.2, gains=[0.9, 1.0], decay=0.08)


def s_search():
    # four soft notes scanning upward and back
    return seq([84, 88, 91, 88], voice=bell, step=0.07, tail=0.2, gains=[0.6, 0.7, 0.8, 0.6], decay=0.07, bright=0.8)


def s_send():
    # soft whoosh up with a closing pluck
    whoosh = noise(0.24, lp=3500, hp=600)
    t = t_axis(0.24)
    whoosh *= np.sin(np.pi * t / 0.24) ** 2
    rise = glide(hz(72), hz(84), 0.2, curve=1.5, harmonics=(1, 0.15)) * np.sin(np.pi * t_axis(0.2) / 0.2)
    return mix(0.36, (0, whoosh, 0.35), (0, rise, 0.45), (0.19, marimba(hz(91), 0.16, decay=0.05), 0.8))


def s_slap():
    # short soft thump: low falling sine with a puff of noise
    thump = glide(150, 55, 0.12, curve=0.5, harmonics=(1, 0.2)) * env(0.12, 0.002, 0.04)
    puff = noise(0.04, lp=1800) * env(0.04, 0.001, 0.01)
    return mix(0.13, (0, thump, 1.0), (0, puff, 0.35))


def s_sleep():
    # slow soft descending notes, like drifting off
    parts = [(i * 0.22, marimba(hz(m), 0.5, decay=0.2, bright=0.6), g)
             for i, (m, g) in enumerate([(79, 0.7), (76, 0.6), (72, 0.55)])]
    hum = glide(hz(60), hz(57), 0.9, harmonics=(1, 0.1)) * np.sin(np.pi * t_axis(0.9) / 0.9) ** 2
    return mix(0.95, *parts, (0, hum, 0.18))


def s_think():
    # "hmm": two soft identical taps, the second quieter
    return seq([74, 74], voice=marimba, step=0.13, tail=0.18, gains=[0.8, 0.55], decay=0.06, bright=0.9)


def s_tick():
    click = noise(0.02, lp=7000, hp=1500) * env(0.02, 0.0005, 0.004)
    return mix(0.025, (0, click, 0.6), (0, marimba(hz(100), 0.025, decay=0.006, bright=0.4), 0.6))


def s_wink():
    sig = glide(hz(86), hz(93), 0.08, curve=0.6, harmonics=(1, 0.1)) * env(0.08, 0.003, 0.03)
    return mix(0.16, (0, sig, 0.8), (0.05, bell(hz(98), 0.11, decay=0.035, bright=0.6), 0.5))


def s_work():
    # busy double tap on a lower bar
    return seq([67, 71], voice=marimba, step=0.09, tail=0.15, gains=[1.0, 0.85], decay=0.045)


def s_yawn():
    # a vocal-ish glide that rises a little, then sinks for a long time
    up = glide(hz(67), hz(72), 0.25, curve=0.7, harmonics=(1, 0.45, 0.2, 0.08))
    down = glide(hz(72), hz(60), 0.65, curve=0.8, harmonics=(1, 0.45, 0.2, 0.08), vibrato=0.006, vib_rate=5)
    sig = np.concatenate([up, down])
    t = t_axis(0.9)
    e = np.minimum(1, t / 0.12) * np.where(t < 0.3, 1, np.exp(-(t - 0.3) / 0.3))
    return sig * e


SOUNDS = {
    "annoyed": s_annoyed, "approval": s_approval, "approve": s_approve, "attach": s_attach,
    "blip": s_blip, "close": s_close, "dizzy": s_dizzy, "error": s_error, "finish": s_finish,
    "greet": s_greet, "greeting": s_greeting, "gulp": s_gulp, "hover": s_hover, "love": s_love,
    "open": s_open, "peek": s_peek, "pop": s_pop, "proud": s_proud, "question": s_question,
    "rate": s_rate, "search": s_search, "send": s_send, "slap": s_slap, "sleep": s_sleep,
    "think": s_think, "tick": s_tick, "wink": s_wink, "work": s_work, "yawn": s_yawn,
}

QUIET = {"tick", "hover", "blip"}  # -14 dBFS


def finalise(name, sig):
    sig = np.asarray(sig, dtype=np.float64)
    # gentle low-pass to take the edge off the FM partials
    a = np.exp(-2 * np.pi * 9000 / SR)
    y = np.empty_like(sig)
    acc = 0.0
    for i, v in enumerate(sig):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    sig = y - np.mean(y)
    # anti-click fades: 1.5 ms in, 6 ms out (shorter for tiny sounds)
    n = len(sig)
    fi = min(int(0.0015 * SR), n // 8)
    fo = min(int(0.006 * SR), n // 4)
    if fi > 0:
        sig[:fi] *= np.linspace(0, 1, fi)
    if fo > 0:
        sig[-fo:] *= np.linspace(1, 0, fo)
    peak_db = -14.0 if name in QUIET else -3.5
    sig *= (10 ** (peak_db / 20)) / (np.max(np.abs(sig)) + 1e-12)
    return np.round(sig * 32767).astype("<i2")


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in SOUNDS.items():
        pcm = finalise(name, fn())
        with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
    print(f"wrote {len(SOUNDS)} sounds to {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
