import '../models/game_models.dart';
import 'board_layout.dart';

class GameSession {
  GameSession.initial({int? gold, int? baseHealth})
    : _gold = gold ?? GameBalance.startingGold,
      _baseHealth = baseHealth ?? GameBalance.initialBaseHealth;

  final Map<GridPosition, PlacedTower> _towersByPosition = {};
  int _nextTowerId = 1;
  int _gold;
  int _baseHealth;
  int _waveIndex = 0;
  GamePhase _phase = GamePhase.build;

  int get gold => _gold;
  int get baseHealth => _baseHealth;
  int get waveIndex => _waveIndex;
  GamePhase get phase => _phase;
  List<PlacedTower> get towers => List.unmodifiable(_towersByPosition.values);
  WaveDefinition? get activeWave {
    if (_waveIndex >= GameBalance.waves.length) {
      return null;
    }
    return GameBalance.waves[_waveIndex];
  }

  GameSnapshot snapshot({
    GridPosition? selectedCell,
    PlacedTower? selectedTower,
    String? feedback,
  }) {
    return GameSnapshot(
      phase: _phase,
      gold: _gold,
      baseHealth: _baseHealth,
      waveNumber: (_waveIndex + 1).clamp(1, GameBalance.waves.length).toInt(),
      selectedCell: selectedCell,
      selectedTower: selectedTower,
      feedback: feedback,
    );
  }

  PlacementResult validatePlacement(GridPosition position, TowerType type) {
    if (_phase != GamePhase.build) {
      return const PlacementResult.denied(PlacementFailure.invalidPhase);
    }
    if (!BoardLayout.isInBounds(position)) {
      return const PlacementResult.denied(PlacementFailure.offBoard);
    }
    if (BoardLayout.isPathCell(position)) {
      return const PlacementResult.denied(PlacementFailure.pathBlocked);
    }
    if (_towersByPosition.containsKey(position)) {
      return const PlacementResult.denied(PlacementFailure.occupied);
    }
    final cost = GameBalance.towerStats(type, level: 1).cost;
    if (_gold < cost) {
      return const PlacementResult.denied(PlacementFailure.insufficientGold);
    }
    return const PlacementResult.allowed();
  }

  PlacementResult placeTower(GridPosition position, TowerType type) {
    final result = validatePlacement(position, type);
    if (!result.isAllowed) {
      return result;
    }

    final stats = GameBalance.towerStats(type, level: 1);
    _gold -= stats.cost;
    _towersByPosition[position] = PlacedTower(
      id: _nextTowerId,
      type: type,
      position: position,
    );
    _nextTowerId += 1;
    return result;
  }

  bool upgradeTower(int towerId) {
    if (_phase != GamePhase.build) {
      return false;
    }

    final entry = _findTowerEntry(towerId);
    if (entry == null) {
      return false;
    }

    final tower = entry.value;
    if (tower.level >= 2) {
      return false;
    }

    final stats = GameBalance.towerStats(tower.type, level: tower.level);
    if (_gold < stats.upgradeCost) {
      return false;
    }

    _gold -= stats.upgradeCost;
    _towersByPosition[entry.key] = tower.upgraded();
    return true;
  }

  bool startWave() {
    if (_phase != GamePhase.build || _waveIndex >= GameBalance.waves.length) {
      return false;
    }
    _phase = GamePhase.wave;
    return true;
  }

  void finishActiveWave() {
    if (_phase != GamePhase.wave) {
      return;
    }

    _waveIndex += 1;
    _phase = _waveIndex >= GameBalance.waves.length
        ? GamePhase.won
        : GamePhase.build;
  }

  void rewardKill(int goldReward) {
    if (_phase != GamePhase.wave || goldReward <= 0) {
      return;
    }
    _gold += goldReward;
  }

  void damageBase(int amount) {
    if (_phase != GamePhase.wave || amount <= 0) {
      return;
    }
    _baseHealth = (_baseHealth - amount)
        .clamp(0, GameBalance.initialBaseHealth)
        .toInt();
    if (_baseHealth == 0) {
      _phase = GamePhase.lost;
    }
  }

  PlacedTower? towerAt(GridPosition position) => _towersByPosition[position];

  void restart() {
    _towersByPosition.clear();
    _nextTowerId = 1;
    _gold = GameBalance.startingGold;
    _baseHealth = GameBalance.initialBaseHealth;
    _waveIndex = 0;
    _phase = GamePhase.build;
  }

  MapEntry<GridPosition, PlacedTower>? _findTowerEntry(int towerId) {
    for (final entry in _towersByPosition.entries) {
      if (entry.value.id == towerId) {
        return entry;
      }
    }
    return null;
  }
}
