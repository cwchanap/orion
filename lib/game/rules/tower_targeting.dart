class TargetPoint {
  const TargetPoint({required this.x, required this.y});

  final double x;
  final double y;
}

class TargetCandidate {
  const TargetCandidate({
    required this.id,
    required this.x,
    required this.y,
    required this.pathProgress,
    required this.isAlive,
  });

  final int id;
  final double x;
  final double y;
  final double pathProgress;
  final bool isAlive;
}

class TowerTargeting {
  static TargetCandidate? selectTarget({
    required TargetPoint tower,
    required double range,
    required Iterable<TargetCandidate> candidates,
  }) {
    final rangeSquared = range * range;
    TargetCandidate? selected;

    for (final candidate in candidates) {
      if (!candidate.isAlive) {
        continue;
      }

      final dx = candidate.x - tower.x;
      final dy = candidate.y - tower.y;
      final distanceSquared = (dx * dx) + (dy * dy);
      if (distanceSquared > rangeSquared) {
        continue;
      }

      if (selected == null || candidate.pathProgress > selected.pathProgress) {
        selected = candidate;
      }
    }

    return selected;
  }
}
