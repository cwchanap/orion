import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/feedback/combat_sound_limiter.dart';
import 'package:orion/game/feedback/game_feedback.dart';
import 'package:orion/game/feedback/game_music.dart';

/// The 17 combat WAVs owned by the HPA-385 asset PR: the 13 pooled cue
/// filenames plus the four always-audible rare transition cues. Derived
/// from production code, independently of the generator script and of the
/// filename mapping tables in the unit tests.
final List<String> _combatWavs = [
  for (final cue in CombatSoundCue.values) cue.filename,
  waveStartedSound,
  bossArrivalSound,
  bossDefeatedSound,
  towerSoldSound,
];

/// Every WAV the platform feedback can request: the 17 combat clips plus
/// the four pre-existing stingers warm-up loads at construction.
final List<String> _allAdvertisedWavs = [
  ..._combatWavs,
  ...PlatformGameFeedback.sounds,
];

/// The four music files owned by the separate HPA-168 asset PR.
final List<String> _musicWavs = [
  for (final track in MusicTrack.values) track.filename,
];

/// HPA-385 cross-PR gate: skips with an explicit reason until the asset PR
/// lands all 17 combat WAVs under `assets/audio/`, then enforces the full
/// contract.
final String? _hpa385SkipReason = () {
  final missing = _combatWavs
      .where((name) => !File('assets/audio/$name').existsSync())
      .toList();
  if (missing.isEmpty) return null;
  return 'HPA-385 asset pack not merged yet: missing assets/audio/'
      '${missing.join(', assets/audio/')}';
}();

/// HPA-168 cross-PR gate: enforce the music contract once all four asset-only
/// PR files are present; until then, skip with the missing filenames listed.
final String? _hpa168SkipReason = () {
  final missing = _musicWavs
      .where((name) => !File('assets/audio/$name').existsSync())
      .toList();
  if (missing.isEmpty) return null;
  return 'HPA-168 music asset pack not merged yet: missing assets/audio/'
      '${missing.join(', assets/audio/')}';
}();

/// Returns WAV encoding details and duration from the RIFF/WAV chunk headers.
({int audioFormat, int channels, int durationMs}) _wavInfo(List<int> bytes) {
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw FormatException('not a RIFF/WAVE file');
  }

  var offset = 12;
  int? audioFormat;
  int? channels;
  int? byteRate;
  int? dataBytes;
  while (offset + 8 <= bytes.length) {
    final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize =
        bytes[offset + 4] |
        (bytes[offset + 5] << 8) |
        (bytes[offset + 6] << 16) |
        (bytes[offset + 7] << 24);
    final chunkData = offset + 8;
    if (chunkId == 'fmt ' && chunkData + 16 <= bytes.length) {
      // fmt chunk layout: audioFormat(2) numChannels(2) sampleRate(4)
      // byteRate(4) blockAlign(2) bitsPerSample(2).
      audioFormat = bytes[chunkData] | (bytes[chunkData + 1] << 8);
      channels = bytes[chunkData + 2] | (bytes[chunkData + 3] << 8);
      final base = chunkData + 8;
      byteRate =
          bytes[base] |
          (bytes[base + 1] << 8) |
          (bytes[base + 2] << 16) |
          (bytes[base + 3] << 24);
    } else if (chunkId == 'data') {
      dataBytes = chunkSize;
    }
    offset = chunkData + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }

  if (audioFormat == null ||
      channels == null ||
      byteRate == null ||
      byteRate <= 0 ||
      dataBytes == null) {
    throw FormatException('missing or invalid fmt/data chunk');
  }
  return (
    audioFormat: audioFormat,
    channels: channels,
    durationMs: (dataBytes / byteRate * 1000).ceil(),
  );
}

void main() {
  test(
    'the four pre-existing stingers exist and are explicitly registered',
    () {
      final pubspecLines = File(
        'pubspec.yaml',
      ).readAsLinesSync().map((line) => line.trim());
      for (final name in PlatformGameFeedback.sounds) {
        expect(
          File('assets/audio/$name').existsSync(),
          isTrue,
          reason: 'assets/audio/$name must exist',
        );
        expect(
          pubspecLines,
          contains('- assets/audio/$name'),
          reason:
              'assets/audio/$name must be explicitly listed in pubspec.yaml',
        );
      }
    },
  );

  test('every advertised WAV exists under assets/audio and is explicitly '
      'registered in pubspec.yaml', () {
    final pubspecLines = File(
      'pubspec.yaml',
    ).readAsLinesSync().map((line) => line.trim());
    for (final name in _allAdvertisedWavs) {
      expect(
        File('assets/audio/$name').existsSync(),
        isTrue,
        reason: 'assets/audio/$name must exist',
      );
      expect(
        pubspecLines,
        contains('- assets/audio/$name'),
        reason: 'assets/audio/$name must be explicitly listed in pubspec.yaml',
      );
    }
  }, skip: _hpa385SkipReason);

  test('all 17 combat WAVs satisfy the ≤ 500 ms duration contract', () {
    for (final name in _combatWavs) {
      final bytes = File('assets/audio/$name').readAsBytesSync();
      expect(
        _wavInfo(bytes).durationMs,
        lessThanOrEqualTo(500),
        reason:
            'assets/audio/$name must be ≤ 500 ms (got '
            '${_wavInfo(bytes).durationMs} ms)',
      );
    }
  }, skip: _hpa385SkipReason);

  test(
    'four HPA-168 music WAVs are mono PCM, 15–25 s, registered, and ≤5 MB',
    () {
      final pubspecLines = File(
        'pubspec.yaml',
      ).readAsLinesSync().map((line) => line.trim());
      var totalBytes = 0;
      for (final name in _musicWavs) {
        final file = File('assets/audio/$name');
        expect(
          file.existsSync(),
          isTrue,
          reason: 'assets/audio/$name must exist',
        );
        final bytes = file.readAsBytesSync();
        totalBytes += bytes.length;
        expect(
          pubspecLines,
          contains('- assets/audio/$name'),
          reason:
              'assets/audio/$name must be explicitly listed in pubspec.yaml',
        );
        final wav = _wavInfo(bytes);
        expect(
          wav.audioFormat,
          1,
          reason: 'assets/audio/$name must use PCM WAV encoding',
        );
        expect(wav.channels, 1, reason: 'assets/audio/$name must be mono');
        expect(
          wav.durationMs,
          inInclusiveRange(15000, 25000),
          reason: 'assets/audio/$name must be 15–25 seconds long',
        );
      }
      expect(
        totalBytes,
        lessThanOrEqualTo(5000000),
        reason: 'the four HPA-168 music WAVs must total no more than 5 MB',
      );
    },
    skip: _hpa168SkipReason,
  );
}
