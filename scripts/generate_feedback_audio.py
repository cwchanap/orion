#!/usr/bin/env python3
from pathlib import Path
import hashlib
import json
import math
import struct
import wave

RATE = 44_100
AMPLITUDE = 0.28
OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"
SOURCES = OUT / "sources"


def envelope(t: float, duration: float) -> float:
    attack = min(1.0, t / 0.008)
    release = min(1.0, max(0.0, duration - t) / 0.025)
    return max(0.0, min(attack, release))


def render(name: str, notes: list[tuple[float, float]]) -> None:
    samples: list[int] = []
    for frequency, duration in notes:
        frame_count = int(RATE * duration)
        for index in range(frame_count):
            t = index / RATE
            value = (
                AMPLITUDE
                * envelope(t, duration)
                * math.sin(2 * math.pi * frequency * t)
            )
            samples.append(int(max(-1.0, min(1.0, value)) * 32767))
        samples.extend([0] * int(RATE * 0.012))

    write_wav(name, samples)


def write_wav(name: str, samples: list[int]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b"".join(struct.pack("<h", s) for s in samples))


def master_combat(cue: dict) -> list[int]:
    source = SOURCES / f"{cue['name']}.wav"
    if hashlib.sha256(source.read_bytes()).hexdigest() != cue["source_sha256"]:
        raise ValueError(f"Source checksum mismatch: {source.name}")
    with wave.open(str(source)) as audio:
        if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) != (1, 2, RATE):
            raise ValueError(f"Expected 44.1 kHz, 16-bit mono PCM: {source.name}")
        pcm = audio.readframes(audio.getnframes())
    samples = [float(s[0]) for s in struct.iter_unpack("<h", pcm)]
    if not samples or not max(map(abs, samples)):
        raise ValueError(f"Empty or silent source: {source.name}")
    if not 0 < cue["duration"] <= 0.5 or not -30 <= cue["peak_db"] <= -13:
        raise ValueError(f"Invalid mastering settings: {source.name}")

    # Keep the attacks clear while softening generated high-frequency hiss.
    alpha = 1 - math.exp(-2 * math.pi * 6500 / RATE)
    filtered = 0.0
    for index, sample in enumerate(samples):
        filtered += alpha * (sample - filtered)
        samples[index] = filtered
    mean = sum(samples) / len(samples)
    samples = [s - mean for s in samples]
    threshold = max(map(abs, samples)) * 0.01
    onset = next(i for i, s in enumerate(samples) if abs(s) >= threshold)
    start = max(0, onset - int(RATE * 0.003))
    count = round(RATE * cue["duration"])
    samples = samples[start:start + count]
    samples.extend([0.0] * (count - len(samples)))
    for index in range(count):
        samples[index] *= min(1.0, index / (RATE * 0.003),
                              (count - 1 - index) / (RATE * 0.025))
    peak = max(map(abs, samples))
    if peak == 0:
        raise ValueError(f"Silent mastered cue: {source.name}")
    gain = 32767 * 10 ** (cue["peak_db"] / 20) / peak
    return [int(s * gain) for s in samples]


CUES = {
    "confirm.wav": [(660, 0.055), (880, 0.070)],
    "clear.wav": [(523.25, 0.060), (659.25, 0.060), (783.99, 0.090)],
    "victory.wav": [
        (523.25, 0.070),
        (659.25, 0.070),
        (783.99, 0.070),
        (1046.50, 0.140),
    ],
    "defeat.wav": [(329.63, 0.080), (246.94, 0.090), (196.00, 0.150)],
}

if __name__ == "__main__":
    provenance = json.loads((SOURCES / "provenance.json").read_text())
    combat = [(cue, master_combat(cue)) for cue in provenance["cues"]]
    for filename, notes in CUES.items():
        render(filename, notes)
    for cue, samples in combat:
        write_wav(f"{cue['name']}.wav", samples)
        print(f"{cue['name']}.wav: {len(samples) / RATE * 1000:.0f} ms, "
              f"peak {cue['peak_db']} dBFS")
