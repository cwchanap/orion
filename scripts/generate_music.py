#!/usr/bin/env python3
"""Master retained ElevenLabs takes into compact loops without network access."""

import hashlib
import json
import math
from pathlib import Path
import struct
import wave

RATE = 22_050
OUT = Path(__file__).resolve().parents[1] / "assets/audio"
SOURCES = OUT / "music_sources"
NAMES = ("map", "build", "wave", "boss")


def master(name, metadata):
    source = SOURCES / f"music_{name}.wav"
    if hashlib.sha256(source.read_bytes()).hexdigest() != metadata["source_sha256"]:
        raise ValueError(f"Source checksum mismatch: {source.name}")
    with wave.open(str(source)) as audio:
        if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) != (1, 2, RATE):
            raise ValueError(f"Expected 22.05 kHz 16-bit mono PCM: {source.name}")
        data = audio.readframes(audio.getnframes())
    samples = list(s[0] for s in struct.iter_unpack("<h", data))
    start = int(metadata["start_seconds"] * RATE)
    length = 20 * RATE
    overlap = 2 * RATE
    if len(samples) < start + length + overlap:
        raise ValueError(f"Source too short: {source.name}")
    segment = samples[start:start + length + overlap]
    # Overlap the tail onto the head; the wrap joins adjacent source samples.
    mixed = []
    for i in range(overlap):
        blend = 0.5 - 0.5 * math.cos(math.pi * i / overlap)
        mixed.append(segment[length + i] * (1 - blend) + segment[i] * blend)
    mixed.extend(segment[overlap:length])
    peak = max(map(abs, mixed))
    if peak == 0:
        raise ValueError(f"Silent source: {source.name}")
    gain = 0.16 * 32767 / peak
    return [round(s * gain) for s in mixed]


def main():
    metadata = json.loads((OUT / "music_provenance.json").read_text())
    rendered = [(name, master(name, metadata[name])) for name in NAMES]
    for name, samples in rendered:
        with wave.open(str(OUT / f"music_{name}.wav"), "wb") as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(RATE)
            audio.writeframes(struct.pack(f"<{len(samples)}h", *samples))


if __name__ == "__main__":
    main()
