import 'package:flutter/material.dart';

import '../models/game_models.dart';

/// Flutter-dependent icon mapping for tower types. Kept out of the pure model
/// layer (which must not import Flutter) and shared by the game page and codex.
IconData towerIcon(TowerType type) {
  return switch (type) {
    TowerType.laser => Icons.bolt,
    TowerType.rocket => Icons.rocket_launch,
    TowerType.cryo => Icons.ac_unit,
    TowerType.railgun => Icons.linear_scale,
    TowerType.ionChain => Icons.electrical_services,
    TowerType.nanite => Icons.bubble_chart,
    TowerType.gravityWell => Icons.blur_circular,
    TowerType.droneBay => Icons.hub,
  };
}
