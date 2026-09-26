import 'dart:ui';

/// Combat colors shared across enemy rendering and feedback cues so the
/// destroyed burst keeps the enemy body red and the core impact keeps the
/// shield blue.
abstract final class CombatColors {
  static const Color enemyBody = Color(0xFFE35D6A);
  static const Color shield = Color(0xFF6EC6FF);
}
