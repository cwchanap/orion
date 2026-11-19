import 'dart:math' as math;

import '../models/game_models.dart';

/// One ordered draw inside a [FlareBatch]: the recruited character, whether
/// it was new to the committed roster at draw time, and the Scrip refund
/// declared for a duplicate. The refund is stored as data (not derived) so
/// `CampaignSave.withFlareBatch` can re-check every declared outcome.
class FlareDraw {
  const FlareDraw({
    required this.character,
    required this.isNew,
    required this.scripRefund,
  });

  final Character character;

  /// True when this draw first added [character] to the roster — characters
  /// recruited earlier in the same batch already count as owned.
  final bool isNew;

  /// Scrip paid back for a duplicate draw; zero for new recruits.
  final int scripRefund;

  CharacterRank get rank => character.rank;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FlareDraw &&
            character == other.character &&
            isNew == other.isNew &&
            scripRefund == other.scripRefund;
  }

  @override
  int get hashCode => Object.hash(character, isNew, scripRefund);

  @override
  String toString() {
    return 'FlareDraw(character: $character, isNew: $isNew, '
        'scripRefund: $scripRefund)';
  }
}

/// The ordered result of one flare pack: every draw in pull order plus the
/// pack's upfront cost and aggregate duplicate refund.
class FlareBatch {
  FlareBatch(List<FlareDraw> draws) : draws = List.unmodifiable(draws);

  /// Draws in pull order.
  final List<FlareDraw> draws;

  /// Scrip charged upfront for the whole pack
  /// (`draws × GameBalance.flareCost`, no ten-pull discount).
  int get cost => draws.length * GameBalance.flareCost;

  /// Total Scrip refunded by duplicate draws in this batch.
  int get totalScripRefund {
    return draws.fold(0, (sum, draw) => sum + draw.scripRefund);
  }
}

/// Pure signal-flare recruitment rolls (HPA-923). Each draw rolls a rank on
/// [GameBalance.flareRankWeights] basis points, then picks uniformly among
/// the roster characters of that rank. The rule never mutates a wallet or
/// save — [FlareBatch] outcomes are replayed and re-validated by
/// `CampaignSave.withFlareBatch` before any state changes.
abstract final class FlareRules {
  /// The only pack sizes [roll] accepts — a single pull or a ten-pull.
  static const List<int> allowedPackCounts = [1, 10];

  static const int _rankWeightTotal = 10000;

  /// Draws [count] flares against [owned] (the committed roster) using the
  /// injected [random] seam. Draws are classified in pull order: the first
  /// copy of a character is new; later copies in the same batch are
  /// duplicates paying the rank's refund. [owned] is not mutated.
  static FlareBatch roll(
    Iterable<Character> owned,
    int count,
    math.Random random,
  ) {
    if (!allowedPackCounts.contains(count)) {
      throw ArgumentError.value(
        count,
        'count',
        'Flare pack size must be one of $allowedPackCounts',
      );
    }
    final ownedCharacters = Set<Character>.of(owned);
    return FlareBatch([
      for (var index = 0; index < count; index += 1)
        _drawOnce(ownedCharacters, random),
    ]);
  }

  static FlareDraw _drawOnce(Set<Character> owned, math.Random random) {
    final rank = _rollRank(random);
    final candidates = [
      for (final character in Character.values)
        if (character.rank == rank) character,
    ];
    final character = candidates[random.nextInt(candidates.length)];
    // Set.add returns false when the character was already owned or was
    // recruited earlier in this batch — that copy is a duplicate.
    final isNew = owned.add(character);
    return FlareDraw(
      character: character,
      isNew: isNew,
      scripRefund: isNew ? 0 : GameBalance.flareDuplicateScripRefund[rank]!,
    );
  }

  static CharacterRank _rollRank(math.Random random) {
    var roll = random.nextInt(_rankWeightTotal);
    for (final rank in CharacterRank.values) {
      final weight = GameBalance.flareRankWeights[rank]!;
      if (roll < weight) {
        return rank;
      }
      roll -= weight;
    }
    throw StateError(
      'Flare rank weights must total $_rankWeightTotal basis points.',
    );
  }
}
