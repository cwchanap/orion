"""Asset contract and offline regeneration checks for HPA-385 (stdlib only)."""

from pathlib import Path
import hashlib
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]
COMBAT = {
    "fire_laser", "fire_cryo", "fire_rocket", "fire_railgun", "fire_ion_chain",
    "fire_nanite", "fire_gravity_well", "fire_drone_bay", "impact_splash",
    "impact_chain", "impact_pierce", "enemy_destroyed", "core_hit", "wave_start",
    "boss_arrival", "boss_defeated", "tower_sold",
}
ORIGINAL = {
    "confirm": "36e645c3f2866c98116423e328fb2ea273bada082b4cd4c61bb62ab7196a1971",
    "clear": "db70d28def200e84651953a6b8d2387db1e53607eb1938e0e573d754d2341334",
    "victory": "68820334cb1f2741c3c01e3b64ddf70a39415f7e42c40b22f4dfd68e80c61814",
    "defeat": "93da3d430074a87d55864994b828defbedf17fd2f1fdf4ddc28dbf9542d2bff5",
}


class FeedbackAudioTest(unittest.TestCase):
    def test_offline_regeneration_preserves_cues_and_meets_combat_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / "scripts"
            scripts.mkdir()
            shutil.copy(ROOT / "scripts/generate_feedback_audio.py", scripts)
            sources = ROOT / "assets/audio/sources"
            if sources.exists():
                shutil.copytree(sources, root / "assets/audio/sources")
            subprocess.run([sys.executable, str(scripts / "generate_feedback_audio.py")],
                           check=True, capture_output=True)
            output = root / "assets/audio"
            expected = {f"{name}.wav" for name in COMBAT | ORIGINAL.keys()}
            self.assertEqual({p.name for p in output.glob("*.wav")}, expected)
            for name, digest in ORIGINAL.items():
                self.assertEqual(hashlib.sha256((output / f"{name}.wav").read_bytes()).hexdigest(),
                                 digest, name)
            for name in COMBAT:
                with self.subTest(cue=name):
                    path = output / f"{name}.wav"
                    self.assertEqual(path.read_bytes(), (ROOT / "assets/audio" / path.name).read_bytes())
                    with wave.open(str(path)) as audio:
                        self.assertEqual((audio.getnchannels(), audio.getsampwidth(), audio.getframerate()),
                                         (1, 2, 44100))
                        duration = audio.getnframes() / audio.getframerate()
                        self.assertGreater(duration, 0)
                        self.assertLessEqual(duration, 0.5)
                        if name.startswith(("fire_", "impact_")) or name == "enemy_destroyed":
                            self.assertLessEqual(duration, 0.25)
                        pcm = audio.readframes(audio.getnframes())
                    samples = struct.unpack(f"<{len(pcm) // 2}h", pcm)
                    self.assertEqual((samples[0], samples[-1]), (0, 0))
                    self.assertGreater(max(map(abs, samples)), 100)
                    self.assertLess(max(map(abs, samples)), 7500)

            # A changed source must fail before touching known-good outputs.
            source = root / "assets/audio/sources/fire_laser.wav"
            source.write_bytes(source.read_bytes() + b"corrupt")
            before = {p.name: p.read_bytes() for p in output.glob("*.wav")}
            result = subprocess.run([sys.executable, str(scripts / "generate_feedback_audio.py")],
                                    capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"Source checksum mismatch", result.stderr)
            self.assertEqual(before, {p.name: p.read_bytes() for p in output.glob("*.wav")})


if __name__ == "__main__":
    unittest.main()
