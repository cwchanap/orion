"""Public music asset contract and offline reproduction."""

from pathlib import Path
import math
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]
NAMES = ("music_map.wav", "music_build.wav", "music_wave.wav", "music_boss.wav")


class MusicAssetTest(unittest.TestCase):
    def test_assets_meet_contract(self):
        total = 0
        manifest = (ROOT / "pubspec.yaml").read_text()
        for name in NAMES:
            with self.subTest(track=name):
                path = ROOT / "assets/audio" / name
                self.assertIn(f"- assets/audio/{name}", manifest)
                total += path.stat().st_size
                with wave.open(str(path)) as audio:
                    self.assertEqual((audio.getnchannels(), audio.getsampwidth(), audio.getframerate()),
                                     (1, 2, 22050))
                    self.assertGreaterEqual(audio.getnframes() / audio.getframerate(), 15)
                    self.assertLessEqual(audio.getnframes() / audio.getframerate(), 25)
                    pcm = audio.readframes(audio.getnframes())
                samples = struct.unpack(f"<{len(pcm) // 2}h", pcm)
                peak = max(map(abs, samples))
                rms = math.sqrt(sum(s * s for s in samples) / len(samples))
                self.assertGreater(rms, 200)
                self.assertLess(peak, 16384)
                seam = abs(samples[0] - samples[-1])
                nearby = max(abs(samples[i + 1] - samples[i])
                             for i in (*range(1000), *range(len(samples) - 1001, len(samples) - 1)))
                self.assertLessEqual(seam, nearby + 10)
                for start in range(0, len(samples), 22050):
                    self.assertGreater(max(map(abs, samples[start:start + 22050])), 200)
        self.assertLessEqual(total, 5_000_000)

    def test_offline_regeneration(self):
        sources = ROOT / "assets/audio/music_sources"
        if not sources.is_dir():
            self.skipTest("music source takes are private; see assets/audio/README.md")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            shutil.copy(ROOT / "scripts/generate_music.py", root / "scripts")
            shutil.copytree(sources, root / "assets/audio/music_sources")
            shutil.copy(ROOT / "assets/audio/music_provenance.json", root / "assets/audio")
            command = [sys.executable, str(root / "scripts/generate_music.py")]
            subprocess.run(command, check=True, capture_output=True)
            output = root / "assets/audio"
            for name in NAMES:
                self.assertEqual((ROOT / "assets/audio" / name).read_bytes(),
                                 (output / name).read_bytes())
            source = output / "music_sources/music_boss.wav"
            source.write_bytes(source.read_bytes() + b"corrupt")
            before = {name: (output / name).read_bytes() for name in NAMES}
            result = subprocess.run(command, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"Source checksum mismatch", result.stderr)
            self.assertEqual(before, {name: (output / name).read_bytes() for name in NAMES})


if __name__ == "__main__":
    unittest.main()
