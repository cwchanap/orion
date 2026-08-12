#!/usr/bin/env python3
from pathlib import Path
import math
import struct
import wave

RATE = 44_100
AMPLITUDE = 0.28
OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"


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

    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b"".join(struct.pack("<h", s) for s in samples))


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

for filename, notes in CUES.items():
    render(filename, notes)
