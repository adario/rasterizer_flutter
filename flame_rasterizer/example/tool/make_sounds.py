"""Synthesizes Tube Shooter's sounds as short mono 16-bit WAVs, 22050 Hz, one per
`Sound` in lib/stories/games/tube_shooter/sounds.dart. The noise is seeded, so the
files come out the same each run. From flame_rasterizer/example:
  python3 -I tool/make_sounds.py assets/audio
"""

import math
import random
import struct
import sys
import wave

RATE = 22050
rng = random.Random(1981)


def env(t, length, attack=0.005):
    """Linear attack, then exponential-ish decay to 0 at length."""
    if t < attack:
        return t / attack
    x = (t - attack) / max(1e-9, length - attack)
    return max(0.0, (1 - x)) ** 2


def sweep(f0, f1, length, wave_fn, n, power=1.0):
    """Samples of a tone sweeping from f0 to f1 (exponentially)."""
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        x = min(1.0, t / length) ** power
        f = f0 * (f1 / f0) ** x
        phase += f / RATE
        out.append(wave_fn(phase % 1.0))
    return out


def square(p):
    return 1.0 if p < 0.5 else -1.0


def saw(p):
    return 2 * p - 1


def tri(p):
    return 4 * abs(p - 0.5) - 1


def noise(n, cutoff_start, cutoff_end=None, length=None):
    """One-pole low-passed white noise, cutoff in Hz sweeping linearly."""
    cutoff_end = cutoff_start if cutoff_end is None else cutoff_end
    length = length or n / RATE
    out = []
    y = 0.0
    for i in range(n):
        t = i / RATE
        c = cutoff_start + (cutoff_end - cutoff_start) * min(1.0, t / length)
        a = 1 - math.exp(-2 * math.pi * c / RATE)
        y += a * (rng.uniform(-1, 1) - y)
        out.append(y)
    return out


def normalize(samples, peak):
    m = max(1e-9, max(abs(s) for s in samples))
    return [s * peak / m for s in samples]


def write(path, samples):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(
            struct.pack('<h', int(max(-1, min(1, s)) * 32767))
            for s in samples))


def fire():
    length = 0.09
    n = int(RATE * length)
    tone = sweep(2200, 500, length, square, n)
    return normalize([s * env(i / RATE, length) for i, s in enumerate(tone)],
                     0.35)


def enemy_fire():
    length = 0.14
    n = int(RATE * length)
    tone = sweep(700, 180, length, saw, n)
    return normalize([s * env(i / RATE, length) for i, s in enumerate(tone)],
                     0.3)


def explosion():
    length = 0.4
    n = int(RATE * length)
    hiss = noise(n, 5000, 400, length)
    thump = sweep(180, 50, length, tri, n)
    return normalize([(h + 0.5 * k) * env(i / RATE, length, 0.002)
                      for i, (h, k) in enumerate(zip(hiss, thump))], 0.7)


def crash():
    length = 1.3
    n = int(RATE * length)
    hiss = noise(n, 3000, 150, length)
    rumble = noise(n, 120, 60, length)
    thump = sweep(120, 30, length, tri, n)
    return normalize([(h + 2.5 * r + 0.6 * k) * env(i / RATE, length, 0.002)
                      for i, (h, r, k) in enumerate(zip(hiss, rumble, thump))],
                     0.9)


def spike():
    length = 0.06
    n = int(RATE * length)
    tone = sweep(1300, 900, length, tri, n)
    hiss = noise(n, 6000)
    return normalize([(t + 0.4 * h) * env(i / RATE, length, 0.001)
                      for i, (t, h) in enumerate(zip(tone, hiss))], 0.3)


def zap():
    length = 0.55
    n = int(RATE * length)
    buzz = sweep(95, 80, length, saw, n)
    high = sweep(190, 160, length, square, n)
    crackle = noise(n, 8000)
    out = []
    for i in range(n):
        t = i / RATE
        # Flutters at 30 Hz, as an arc does.
        flutter = 0.6 + 0.4 * square((t * 30) % 1.0)
        fade = min(1.0, t / 0.02) * min(1.0, (length - t) / 0.08)
        out.append((buzz[i] + 0.3 * high[i] + 0.5 * crackle[i]) * flutter * fade)
    return normalize(out, 0.35)


def purge():
    length = 0.9
    n = int(RATE * length)
    tone = sweep(150, 2400, length, square, n, power=0.6)
    hiss = noise(n, 500, 9000, length)
    return normalize([(0.6 * t + h) * env(i / RATE, length, 0.02)
                      for i, (t, h) in enumerate(zip(tone, hiss))], 0.6)


def whoosh(length, f0, f1, c0, c1):
    """Filtered noise with a sweeping tone, swelling then fading."""
    n = int(RATE * length)
    hiss = noise(n, c0, c1, length)
    tone = sweep(f0, f1, length, tri, n)
    out = []
    for i in range(n):
        x = i / n
        swell = math.sin(math.pi * x) ** 1.5
        out.append((hiss[i] + 0.25 * tone[i]) * swell)
    return normalize(out, 0.45)


SOUNDS = {
    'fire': fire,
    'enemy_fire': enemy_fire,
    'explosion': explosion,
    'crash': crash,
    'spike': spike,
    'zap': zap,
    'purge': purge,
    'zoom': lambda: whoosh(1.0, 120, 900, 300, 4000),
    'drop': lambda: whoosh(2.0, 900, 70, 4000, 200),
}

if __name__ == '__main__':
    out_dir = sys.argv[1]
    for name, make in SOUNDS.items():
        write(f'{out_dir}/{name}.wav', make())
        print(name)
