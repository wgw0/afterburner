"""Menu and radio sounds for Afterburner (DEVELOPMENT.md §21, AUD-05), made here so we own them outright.

    python tools/audio/ui_sounds.py            # writes tools/audio/out/*.wav

Each is a short mono 44.1 kHz WAV, synthesised from tones and filtered noise:
  UIClick      a soft, dry tick for buttons
  UIConfirm    two rising bell notes: a purchase, research or a lineup change that went through
  LevelUp      a bright four-note arpeggio for a new pilot level
  MatchFound   three quick rising beeps (radar-ish) as the matchmaker finds a match
  RadioIn      the squelch before a radio call: a click and a burst of band-limited static
  RadioOut     the shorter squelch tail after it
Upload them with Studio's Asset Manager (Bulk Import) and put the ids in ReplicatedStorage.Assets.Audio.
"""

import os
import wave

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
rng = np.random.default_rng(7)  # fixed seed: the same files every run


def t(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def envelope(n, attack=0.004, decay=0.1):
    """Fast attack, exponential decay (seconds), for n samples."""
    time = np.arange(n) / RATE
    env = np.exp(-time / decay)
    a = max(int(RATE * attack), 1)
    env[:a] *= np.linspace(0, 1, a)
    return env


def bell(freq, seconds, decay):
    """A soft bell: the note plus a quieter octave and twelfth, decaying."""
    x = t(seconds)
    tone = np.sin(2 * np.pi * freq * x) + 0.35 * np.sin(4 * np.pi * freq * x) + 0.12 * np.sin(6 * np.pi * freq * x)
    return tone * envelope(len(x), 0.003, decay)


def bandpass(signal, low, high):
    """Brick-wall band-pass in the frequency domain (fine for short one-shots)."""
    spectrum = np.fft.rfft(signal)
    freqs = np.fft.rfftfreq(len(signal), 1 / RATE)
    spectrum[(freqs < low) | (freqs > high)] = 0
    return np.fft.irfft(spectrum, len(signal))


def place(parts, seconds):
    """Mixes (start seconds, signal) pairs into one buffer."""
    out = np.zeros(int(RATE * seconds))
    for start, signal in parts:
        i = int(RATE * start)
        end = min(i + len(signal), len(out))
        out[i:end] += signal[: end - i]
    return out


def write(name, signal, peak=0.8):
    signal = signal / (np.max(np.abs(signal)) or 1) * peak
    fade = min(int(RATE * 0.005), len(signal))  # no click at the end
    signal[-fade:] *= np.linspace(1, 0, fade)
    data = (signal * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{name}.wav")
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())
    print(f"{path}  {len(signal) / RATE:.2f} s")


def ui_click():
    n = int(RATE * 0.06)
    noise = bandpass(rng.standard_normal(n), 1800, 6000) * envelope(n, 0.0005, 0.006)
    x = t(0.06)
    blip = np.sin(2 * np.pi * 2400 * x) * envelope(n, 0.0005, 0.012)
    return 0.6 * noise + blip


def ui_confirm():
    return place([(0.0, bell(880, 0.35, 0.12)), (0.09, bell(1318.5, 0.45, 0.16))], 0.55)


def level_up():
    notes = [523.25, 659.25, 783.99, 1046.5]  # C E G C
    parts = [(i * 0.09, bell(f, 0.8, 0.22) * (0.8 + 0.1 * i)) for i, f in enumerate(notes)]
    return place(parts, 1.1)


def match_found():
    x = t(0.07)
    parts = []
    for i, f in enumerate([1000, 1250, 1600]):
        beep = np.sin(2 * np.pi * f * x) * envelope(len(x), 0.002, 0.05)
        parts.append((i * 0.11, beep))
    return place(parts, 0.5)


def radio(seconds, decay, click=True):
    n = int(RATE * seconds)
    static = bandpass(rng.standard_normal(n), 400, 3200)
    static *= envelope(n, 0.002, decay) * (0.75 + 0.25 * np.sin(2 * np.pi * 60 * t(seconds)))  # a hint of hum
    if click:
        m = int(RATE * 0.004)
        static[:m] += np.linspace(1, 0, m) * 3  # the key-up click
    return static


def main():
    write("UIClick", ui_click(), 0.5)
    write("UIConfirm", ui_confirm(), 0.6)
    write("LevelUp", level_up(), 0.7)
    write("MatchFound", match_found(), 0.6)
    write("RadioIn", radio(0.2, 0.07), 0.55)
    write("RadioOut", radio(0.12, 0.035, click=False), 0.45)


if __name__ == "__main__":
    main()
