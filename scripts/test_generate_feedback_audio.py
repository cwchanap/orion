"""Asset contract and offline regeneration checks for HPA-385/HPA-927 (stdlib only)."""

from pathlib import Path
import hashlib
import json
import math
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from generate_feedback_audio import CUES, max_duration_for  # noqa: E402

AUDIO = ROOT / "assets/audio"
COMBAT = {
    "fire_laser", "fire_cryo", "fire_rocket", "fire_railgun", "fire_ion_chain",
    "fire_nanite", "fire_gravity_well", "fire_drone_bay", "impact_splash",
    "impact_chain", "impact_pierce", "enemy_destroyed", "core_hit", "wave_start",
    "boss_arrival", "boss_defeated", "tower_sold",
}
UI_NEW = {"flare_launch", "recruit_reveal", "recruit_reveal_rare", "level_up", "scrip_gain"}
GENERATED = COMBAT | {"victory", "defeat"} | UI_NEW
PROCEDURAL = {
    "confirm": "36e645c3f2866c98116423e328fb2ea273bada082b4cd4c61bb62ab7196a1971",
    "clear": "db70d28def200e84651953a6b8d2387db1e53607eb1938e0e573d754d2341334",
}
ALL_SFX = GENERATED | PROCEDURAL.keys()


def read_wav(path):
    with wave.open(str(path)) as audio:
        fmt = (audio.getnchannels(), audio.getsampwidth(), audio.getframerate())
        frames = audio.getnframes()
        pcm = audio.readframes(frames)
    return fmt, frames, struct.unpack(f"<{len(pcm) // 2}h", pcm)


def peak_db(samples):
    return 20 * math.log10(max(map(abs, samples)) / 32767)


def trailing_zeros(samples):
    count = 0
    for value in reversed(samples):
        if value:
            break
        count += 1
    return count


class PublicAssetContractTest(unittest.TestCase):
    def test_exactly_26_sfx_wavs_are_registered_in_pubspec(self):
        found = {p.stem for p in AUDIO.glob("*.wav") if not p.name.startswith("music_")}
        self.assertEqual(found, ALL_SFX)
        pubspec = (ROOT / "pubspec.yaml").read_text().splitlines()
        for name in sorted(ALL_SFX):
            self.assertIn(f"    - assets/audio/{name}.wav", pubspec, name)

    def test_procedural_cues_keep_original_bytes(self):
        self.assertEqual(set(CUES), {f"{name}.wav" for name in PROCEDURAL})
        for name, digest in PROCEDURAL.items():
            self.assertEqual(hashlib.sha256((AUDIO / f"{name}.wav").read_bytes()).hexdigest(),
                             digest, name)

    def test_provenance_tracks_exactly_the_24_generated_cues(self):
        cues = json.loads((AUDIO / "sfx_provenance.json").read_text())["cues"]
        self.assertEqual({c["name"] for c in cues}, GENERATED)
        self.assertEqual(len(cues), len(GENERATED))

    def test_duration_tiers(self):
        for name in ("fire_laser", "impact_splash", "enemy_destroyed"):
            self.assertEqual(max_duration_for(name), 0.25, name)
        for name in ("core_hit", "wave_start", "boss_arrival", "boss_defeated",
                     "tower_sold", "victory", "defeat"):
            self.assertEqual(max_duration_for(name), 0.5, name)
        for name in UI_NEW:
            self.assertEqual(max_duration_for(name), 1.5, name)

    def test_generated_wavs_match_format_tier_and_selected_metadata(self):
        cues = json.loads((AUDIO / "sfx_provenance.json").read_text())["cues"]
        for cue in cues:
            name = cue["name"]
            with self.subTest(cue=name):
                fmt, frames, samples = read_wav(AUDIO / f"{name}.wav")
                self.assertEqual(len(samples), frames,
                                 "WAV data chunk shorter than its header declares")
                self.assertEqual(fmt, (1, 2, 44100))
                self.assertEqual(frames, round(44100 * cue["duration"]))
                self.assertLessEqual(frames / 44100, max_duration_for(name))
                self.assertEqual((samples[0], samples[-1]), (0, 0))
                # The 25 ms release fade must land on real audio, not on padding.
                self.assertLessEqual(trailing_zeros(samples), 220, "cue is padded with silence")
                self.assertGreater(max(map(abs, samples)), 100)
                self.assertTrue(-30 <= cue["peak_db"] <= -13)
                self.assertAlmostEqual(peak_db(samples), cue["peak_db"], delta=0.05)

    def test_missing_private_sources_fail_with_clear_message(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "assets/audio").mkdir(parents=True)
            shutil.copy(ROOT / "scripts/generate_feedback_audio.py", root / "scripts")
            shutil.copy(AUDIO / "sfx_provenance.json", root / "assets/audio")
            result = subprocess.run([sys.executable, str(root / "scripts/generate_feedback_audio.py")],
                                    capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"source takes are not tracked", result.stderr)
            self.assertNotIn(b"Traceback", result.stderr)


PRIVATE_SKIP = ("assets/audio/sources/ is not tracked; obtain the private bundle "
                "per assets/audio/README.md before regenerating")


class FeedbackAudioTest(unittest.TestCase):
    def test_duration_longer_than_source_is_rejected_before_write(self):
        sources = AUDIO / "sources"
        if not sources.is_dir():
            self.skipTest(PRIVATE_SKIP)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            output = root / "assets/audio"
            output.mkdir(parents=True)
            shutil.copy(ROOT / "scripts/generate_feedback_audio.py", root / "scripts")
            shutil.copytree(sources, output / "sources")
            provenance = json.loads((AUDIO / "sfx_provenance.json").read_text())
            # recruit_reveal's decoded take is 1.0 s long, so 1.4 s would be padded.
            next(c for c in provenance["cues"] if c["name"] == "recruit_reveal")["duration"] = 1.4
            (output / "sfx_provenance.json").write_text(json.dumps(provenance))
            result = subprocess.run([sys.executable, str(root / "scripts/generate_feedback_audio.py")],
                                    capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"shorter than the selected duration", result.stderr)
            self.assertEqual(list(output.glob("*.wav")), [])

    def test_offline_regeneration_reproduces_all_26_and_fails_before_write(self):
        sources = AUDIO / "sources"
        if not sources.is_dir():
            self.skipTest(PRIVATE_SKIP)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / "scripts"
            scripts.mkdir()
            shutil.copy(ROOT / "scripts/generate_feedback_audio.py", scripts)
            output = root / "assets/audio"
            output.mkdir(parents=True)
            shutil.copy(AUDIO / "sfx_provenance.json", output)
            shutil.copytree(sources, output / "sources")
            subprocess.run([sys.executable, str(scripts / "generate_feedback_audio.py")],
                           check=True, capture_output=True)
            self.assertEqual({p.stem for p in output.glob("*.wav")}, ALL_SFX)
            for name in sorted(ALL_SFX):
                with self.subTest(cue=name):
                    self.assertEqual((output / f"{name}.wav").read_bytes(),
                                     (AUDIO / f"{name}.wav").read_bytes())

            # A changed LAST source must fail before any output is written, even
            # though every earlier cue would already be mastered. Outputs are
            # replaced with sentinels so a partial rewrite cannot look unchanged.
            last = json.loads((output / "sfx_provenance.json").read_text())["cues"][-1]["name"]
            source = output / f"sources/{last}.wav"
            source.write_bytes(source.read_bytes() + b"corrupt")
            sentinel = {p.name: b"sentinel " + p.name.encode() for p in output.glob("*.wav")}
            for name, data in sentinel.items():
                (output / name).write_bytes(data)
            result = subprocess.run([sys.executable, str(scripts / "generate_feedback_audio.py")],
                                    capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"Source checksum mismatch", result.stderr)
            self.assertEqual(sentinel, {p.name: p.read_bytes() for p in output.glob("*.wav")})


if __name__ == "__main__":
    unittest.main()
