import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/flare_rules.dart';

void main() {
  group('FlareRules.roll', () {
    test('accepts only pack counts of 1 or 10', () {
      expect(FlareRules.allowedPackCounts, [1, 10]);
      for (final count in [-1, 0, 2, 9, 11, 100]) {
        expect(
          () => FlareRules.roll(const {}, count, math.Random(0)),
          throwsArgumentError,
          reason: 'count $count must be rejected',
        );
      }
    });

    test('rank weights sum to ten thousand basis points', () {
      expect(GameBalance.flareRankWeights.keys.toSet(), {
        ...CharacterRank.values,
      });
      expect(
        GameBalance.flareRankWeights.values.fold<int>(
          0,
          (sum, weight) => sum + weight,
        ),
        10000,
      );
    });

    test('rolls each rank inside its approved basis-point bucket', () {
      const boundaries = <(int, CharacterRank)>[
        (0, CharacterRank.e),
        (6739, CharacterRank.e),
        (6740, CharacterRank.d),
        (8739, CharacterRank.d),
        (8740, CharacterRank.c),
        (9739, CharacterRank.c),
        (9740, CharacterRank.b),
        (9939, CharacterRank.b),
        (9940, CharacterRank.a),
        (9989, CharacterRank.a),
        (9990, CharacterRank.s),
        (9999, CharacterRank.s),
      ];

      for (final (rankRoll, expectedRank) in boundaries) {
        final batch = FlareRules.roll(
          const {},
          1,
          _ScriptedRandom([rankRoll, 0]),
        );
        expect(
          batch.draws.single.character.rank,
          expectedRank,
          reason: 'rank roll $rankRoll',
        );
      }
    });

    test('picks uniformly among the characters of the rolled rank', () {
      final firstPick = FlareRules.roll(
        const {},
        1,
        _ScriptedRandom([9990, 0]),
      );
      final secondPick = FlareRules.roll(
        const {},
        1,
        _ScriptedRandom([9990, 1]),
      );

      expect(firstPick.draws.single.character, Character.hikari);
      expect(secondPick.draws.single.character, Character.jin);
    });

    test(
      'a fully owned roster classifies every draw as a refunded duplicate',
      () {
        final batch = FlareRules.roll(
          Character.values,
          10,
          _ScriptedRandom(const [
            0,
            0,
            6740,
            0,
            8740,
            0,
            9740,
            0,
            9940,
            0,
            9990,
            0,
            0,
            0,
            6740,
            0,
            8740,
            0,
            9740,
            0,
          ]),
        );

        expect(batch.draws, hasLength(10));
        const expectedRefunds = <(CharacterRank, int)>[
          (CharacterRank.e, 10),
          (CharacterRank.d, 25),
          (CharacterRank.c, 60),
          (CharacterRank.b, 200),
          (CharacterRank.a, 600),
          (CharacterRank.s, 2000),
          (CharacterRank.e, 10),
          (CharacterRank.d, 25),
          (CharacterRank.c, 60),
          (CharacterRank.b, 200),
        ];
        for (final (index, expected) in expectedRefunds.indexed) {
          final draw = batch.draws[index];
          expect(draw.isNew, isFalse, reason: 'draw $index');
          expect(draw.rank, expected.$1, reason: 'draw $index');
          expect(
            draw.scripRefund,
            expected.$2,
            reason: 'draw $index ${draw.character.name}',
          );
        }
        expect(batch.totalScripRefund, 3190);
      },
    );

    test('classifies earlier in-batch recruits as owned for later draws', () {
      final batch = FlareRules.roll(
        const {Character.haruto},
        10,
        _ScriptedRandom(const [
          0,
          0, // haruto — already owned duplicate
          0,
          1, // mio — first copy, new
          0,
          1, // mio — second copy in the same batch, duplicate
          9990,
          0, // hikari — new
          9990,
          1, // jin — new
          6740,
          0, // sayo — new
          6740,
          1, // tetsuo — new
          8740,
          0, // rin — new
          8740,
          1, // kaito — new
          9940,
          0, // akane — new
        ]),
      );

      expect(batch.draws, hasLength(10));
      expect(batch.draws[0].character, Character.haruto);
      expect(batch.draws[0].isNew, isFalse);
      expect(batch.draws[0].scripRefund, 10);
      expect(batch.draws[1].character, Character.mio);
      expect(batch.draws[1].isNew, isTrue);
      expect(batch.draws[1].scripRefund, 0);
      expect(batch.draws[2].character, Character.mio);
      expect(batch.draws[2].isNew, isFalse);
      expect(batch.draws[2].scripRefund, 10);
      expect(batch.draws[3].character, Character.hikari);
      expect(batch.draws[3].isNew, isTrue);
      expect(batch.draws[4].character, Character.jin);
      expect(batch.draws[4].isNew, isTrue);
      for (final index in [5, 6, 7, 8, 9]) {
        expect(batch.draws[index].isNew, isTrue, reason: 'draw $index');
      }
      expect(batch.totalScripRefund, 20);
    });

    test('fixed seeds produce identical ordered batches', () {
      const owned = {Character.haruto, Character.mio};

      final first = FlareRules.roll(owned, 10, math.Random(42));
      final second = FlareRules.roll(owned, 10, math.Random(42));

      expect(first.draws, second.draws);
      expect(first.draws, hasLength(10));
      expect(first.totalScripRefund, second.totalScripRefund);
    });

    test('a single pull costs one flare and a ten-pull costs ten', () {
      expect(
        FlareRules.roll(const {}, 1, math.Random(0)).cost,
        GameBalance.flareCost,
      );
      expect(
        FlareRules.roll(const {}, 10, math.Random(0)).cost,
        10 * GameBalance.flareCost,
      );
    });

    test('does not mutate the owned roster and exposes unmodifiable draws', () {
      final owned = {Character.haruto};

      final batch = FlareRules.roll(owned, 10, math.Random(1));

      expect(owned, {Character.haruto});
      expect(() => batch.draws.add(batch.draws.first), throwsUnsupportedError);
    });
  });
}

/// Deterministic `Random` seam: each `nextInt` call returns the next scripted
/// value (which must satisfy the requested bound), letting tests target exact
/// rank buckets and same-rank picks without seed hunting.
class _ScriptedRandom implements math.Random {
  _ScriptedRandom(List<int> values) : _values = List.of(values);

  final List<int> _values;
  var _nextIndex = 0;

  @override
  int nextInt(int max) {
    if (_nextIndex >= _values.length) {
      throw StateError('ScriptedRandom ran out of values.');
    }
    final value = _values[_nextIndex++];
    if (value < 0 || value >= max) {
      throw ArgumentError('Scripted value $value outside [0, $max).');
    }
    return value;
  }

  @override
  double nextDouble() => throw UnimplementedError('nextDouble is unused');

  @override
  bool nextBool() => throw UnimplementedError('nextBool is unused');
}
