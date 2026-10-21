import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/feedback/game_feedback.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('NoOpGameFeedback', () {
    test('every method is a safe no-op', () {
      const feedback = NoOpGameFeedback();
      feedback.towerConfirmed();
      feedback.moduleSelected();
      feedback.waveCleared();
      feedback.towerFired(TowerType.laser);
      feedback.towerFired(TowerType.droneBay);
      feedback.splashImpact();
      feedback.chainImpact();
      feedback.pierceImpact();
      feedback.enemyDestroyed();
      feedback.coreHit();
      feedback.waveStarted();
      feedback.bossArrived();
      feedback.bossDefeated();
      feedback.towerSold();
      feedback.missionVictory();
      feedback.baseDefeated();
    });
  });
}
