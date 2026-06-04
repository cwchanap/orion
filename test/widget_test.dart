import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/game_session.dart';
import 'package:orion/main.dart';

void main() {
  testWidgets('boots into the Orion tower defense shell', (tester) async {
    await tester.pumpWidget(const OrionApp());
    await tester.pump();

    expect(find.text('Orion'), findsOneWidget);
    expect(find.text('Gold 150'), findsOneWidget);
    expect(find.text('Base 20'), findsOneWidget);
    expect(find.text('Wave 1/8'), findsOneWidget);
    expect(find.text('Start Wave'), findsOneWidget);
  });

  test('snapshot exposes the current tower unlocks', () {
    final session = GameSession.initial();

    expect(session.snapshot().unlockedTowerTypes, [
      TowerType.laser,
      TowerType.rocket,
      TowerType.cryo,
    ]);

    expect(session.startWave(), isTrue);
    session.finishActiveWave();

    expect(session.snapshot().unlockedTowerTypes, [
      TowerType.laser,
      TowerType.rocket,
      TowerType.cryo,
      TowerType.railgun,
    ]);
  });
}
