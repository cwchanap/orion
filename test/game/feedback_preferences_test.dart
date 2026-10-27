import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/feedback/feedback_preferences.dart';

void main() {
  group('FeedbackPreferences', () {
    test('preferences compare by value', () {
      const a = FeedbackPreferences(
        soundEffectsEnabled: false,
        hapticsEnabled: true,
        musicEnabled: false,
      );
      const b = FeedbackPreferences(
        soundEffectsEnabled: false,
        hapticsEnabled: true,
        musicEnabled: false,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          const FeedbackPreferences(
            soundEffectsEnabled: false,
            hapticsEnabled: true,
          ),
        ),
      );
    });

    test('copyWith can restore a changed draft', () {
      const original = FeedbackPreferences(
        soundEffectsEnabled: false,
        hapticsEnabled: true,
        musicEnabled: false,
      );
      final changed = original.copyWith(
        hapticsEnabled: false,
        musicEnabled: true,
      );
      final restored = changed.copyWith(
        hapticsEnabled: true,
        musicEnabled: false,
      );

      expect(changed, isNot(original));
      expect(restored, original);
    });

    test('music is enabled by default', () {
      expect(const FeedbackPreferences().musicEnabled, isTrue);
    });
  });
}
