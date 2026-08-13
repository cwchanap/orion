import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/feedback/feedback_preferences.dart';

void main() {
  group('FeedbackPreferences', () {
    test('preferences compare by value', () {
      const a = FeedbackPreferences(
        soundEffectsEnabled: false,
        hapticsEnabled: true,
      );
      const b = FeedbackPreferences(
        soundEffectsEnabled: false,
        hapticsEnabled: true,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith can restore a changed draft', () {
      const original = FeedbackPreferences(
        soundEffectsEnabled: false,
        hapticsEnabled: true,
      );
      final changed = original.copyWith(hapticsEnabled: false);
      final restored = changed.copyWith(hapticsEnabled: true);

      expect(changed, isNot(original));
      expect(restored, original);
    });
  });
}
