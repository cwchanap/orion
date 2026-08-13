import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/feedback/game_feedback.dart';

void main() {
  group('NoOpGameFeedback', () {
    test('every method is a safe no-op', () {
      const feedback = NoOpGameFeedback();
      feedback.towerConfirmed();
      feedback.moduleSelected();
      feedback.waveCleared();
      feedback.bossDefeated();
      feedback.missionVictory();
      feedback.baseDefeated();
    });
  });
}
