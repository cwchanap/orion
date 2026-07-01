import 'dart:async';

import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/rules/game_session.dart';
import 'package:orion/game/ui/orion_game_page.dart';
import 'package:orion/game/ui/world_map_view.dart';
import 'package:orion/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('boots into the Orion world map first', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const OrionApp());
    await tester.pumpAndSettle();

    expect(find.text('Orion Sector Map'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Start Wave'), findsNothing);
  });

  testWidgets('starts an unlocked stage from the world map', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const OrionApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(find.text('Outpost Alpha'), findsOneWidget);
    expect(find.text('Gold 150'), findsOneWidget);
    expect(find.text('Base 20'), findsOneWidget);
    expect(find.text('Wave 1/8'), findsOneWidget);
    expect(find.text('Next Wave 1/8'), findsOneWidget);
    expect(find.text('8 Drones'), findsOneWidget);
    expect(find.text('Clear bonus 30'), findsOneWidget);
    expect(find.text('Start Wave'), findsOneWidget);
  });

  testWidgets('mission screen exposes pause speed and auto-start controls', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const OrionApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.text('2x'), findsOneWidget);
    expect(find.text('3x'), findsOneWidget);
    expect(find.byTooltip('Auto-start waves'), findsOneWidget);
    expect(find.text('Start Wave'), findsOneWidget);
  });

  testWidgets(
    'next wave panel stays visible while planning and hides in wave',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      OrionDefenseGame? game;

      await tester.pumpWidget(
        MaterialApp(
          home: OrionGamePage(onGameCreated: (created) => game = created),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(find.text('Next Wave 1/8'), findsOneWidget);
      expect(find.text('8 Drones'), findsOneWidget);
      expect(
        _activeIgnorePointerAncestorsOf(find.text('Next Wave 1/8')),
        findsOneWidget,
      );
      expect(
        _activeIgnorePointerAncestorsOf(find.text('8 Drones')),
        findsOneWidget,
      );
      expect(
        _activeIgnorePointerAncestorsOf(find.text('Start Wave')),
        findsNothing,
      );

      final createdGame = game!;
      createdGame.onTapDown(
        TapDownEvent(
          1,
          createdGame,
          TapDownDetails(globalPosition: const Offset(225, 275)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Build Tower'), findsOneWidget);
      expect(find.text('Next Wave 1/8'), findsOneWidget);
      expect(find.text('8 Drones'), findsOneWidget);

      createdGame.startWave();
      await tester.pump();

      expect(find.text('Next Wave 1/8'), findsNothing);
      expect(find.text('8 Drones'), findsNothing);
    },
  );

  testWidgets('next wave panel omits zero clear bonus text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    OrionDefenseGame? game;

    await tester.pumpWidget(
      MaterialApp(
        home: OrionGamePage(onGameCreated: (created) => game = created),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    final snapshot = game!.stateNotifier.value;
    game!.stateNotifier.value = GameSnapshot(
      phase: GamePhase.build,
      gold: snapshot.gold,
      baseHealth: snapshot.baseHealth,
      waveNumber: 8,
      waveTotal: snapshot.waveTotal,
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      stageLabel: snapshot.stageLabel,
      unlockedTowerTypes: snapshot.unlockedTowerTypes,
      nextWavePreview: WavePreview(
        waveNumber: 8,
        waveTotal: snapshot.waveTotal,
        groups: [
          WavePreviewGroup(
            enemyCount: 4,
            label: 'Regen Heavy Drones',
            traits: const {EnemyTrait.regen, EnemyTrait.heavy},
          ),
        ],
        traits: const {EnemyTrait.regen, EnemyTrait.heavy},
        clearBonus: 0,
        recommendedTowerTypes: const [TowerType.laser, TowerType.rocket],
      ),
      selectedCell: snapshot.selectedCell,
      selectedTower: snapshot.selectedTower,
      feedback: snapshot.feedback,
      isPaused: snapshot.isPaused,
      speedMultiplier: snapshot.speedMultiplier,
      autoStartEnabled: snapshot.autoStartEnabled,
      autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
    );
    await tester.pump();

    expect(find.text('Next Wave 8/8'), findsOneWidget);
    expect(find.text('4 Regen Heavy Drones'), findsOneWidget);
    expect(find.text('Clear bonus 0'), findsNothing);
    expect(find.text('Recommended: Laser, Rocket'), findsOneWidget);
  });

  testWidgets('locked stage tap shows feedback and stays on map', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const OrionApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Core'));
    await tester.pumpAndSettle();

    expect(find.text('Singularity Core is locked.'), findsOneWidget);
    expect(find.text('Start Wave'), findsNothing);
  });

  testWidgets('reset confirmation clears campaign progress', (tester) async {
    SharedPreferences.setMockInitialValues({
      'orion.campaign.progress': CampaignProgressCodec.encode(
        _progressWithResults({
          'outpost-alpha',
          'nebula-relay',
          'asteroid-foundry',
          'aurora-gate',
        }),
      ),
    });

    await tester.pumpWidget(const OrionApp());
    await tester.pumpAndSettle();

    expect(find.text('Core'), findsOneWidget);
    expect(find.text('Open'), findsWidgets);

    await tester.tap(find.byTooltip('Reset Campaign'));
    await tester.pumpAndSettle();

    expect(find.text('Reset Campaign'), findsOneWidget);
    expect(find.text('Clear all campaign progress?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Campaign reset.'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Core'), findsOneWidget);
    expect(find.text('Locked'), findsWidgets);
    expect(find.text('Start Wave'), findsNothing);
  });

  testWidgets('falls back to empty world map when progress load fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OrionGamePage(
          progressStore: _TestCampaignProgressStore(
            loadError: StateError('no'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Orion Sector Map'), findsOneWidget);
    expect(find.text('Could not load campaign progress.'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Start Wave'), findsNothing);
  });

  testWidgets(
    'stage clear save failure keeps prior progress and shows feedback',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({'outpost-alpha'}),
        saveError: StateError('save failed'),
      );
      OrionDefenseGame? game;

      await tester.pumpWidget(
        MaterialApp(
          home: OrionGamePage(
            progressStore: store,
            onGameCreated: (created) => game = created,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      game!.onStageWon?.call(
        StageCompletion(
          stage: OrionCampaign.stageById('nebula-relay'),
          result: const StageResult(
            medal: StageMedal.silver,
            bestBaseHealth: 14,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not save campaign progress.'), findsOneWidget);
      expect(find.text('Next Wave 1/8'), findsOneWidget);
      expect(store.progress.bestResultsByStageId.keys, {'outpost-alpha'});
      expect(store.progress.resultFor('nebula-relay'), isNull);
    },
  );

  testWidgets('serializes sibling stage clear saves without losing progress', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha', 'nebula-relay'}),
      delaySaves: true,
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      MaterialApp(
        home: OrionGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    game!.onStageWon?.call(
      StageCompletion(
        stage: OrionCampaign.stageById('salvage-rift'),
        result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      ),
    );
    game!.onStageWon?.call(
      StageCompletion(
        stage: OrionCampaign.stageById('asteroid-foundry'),
        result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      ),
    );

    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
    if (store.saveCompletions.length > 1) {
      store.saveCompletions[1].complete();
      await tester.pump();
      store.saveCompletions[0].complete();
    } else {
      store.saveCompletions[0].complete();
      await _pumpUntil(tester, () => store.saveCompletions.length > 1);
      store.saveCompletions[1].complete();
    }
    await tester.pumpAndSettle();

    expect(store.progress.bestResultsByStageId.keys, {
      'outpost-alpha',
      'nebula-relay',
      'salvage-rift',
      'asteroid-foundry',
    });
    expect(
      store.progress.resultFor('salvage-rift'),
      const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
    );
    expect(
      store.progress.resultFor('asteroid-foundry'),
      const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
  });

  testWidgets('stage replay save does not downgrade an existing medal', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: CampaignProgress(
        bestResultsByStageId: {
          'outpost-alpha': const StageResult(
            medal: StageMedal.gold,
            bestBaseHealth: 20,
          ),
        },
      ),
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      MaterialApp(
        home: OrionGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    game!.onStageWon?.call(
      StageCompletion(
        stage: OrionCampaign.stageById('outpost-alpha'),
        result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      store.progress.resultFor('outpost-alpha'),
      const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
  });

  testWidgets('failed reset does not let pending clear save reset progress', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha', 'nebula-relay'}),
      delaySaves: true,
      resetResults: [StateError('reset failed'), null],
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      MaterialApp(
        home: OrionGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    game!.onStageWon?.call(
      StageCompletion(
        stage: OrionCampaign.stageById('salvage-rift'),
        result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      ),
    );
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

    game!.returnToMap();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Reset Campaign'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Could not reset campaign progress.'), findsOneWidget);

    store.saveCompletions.single.complete();
    await tester.pumpAndSettle();

    expect(store.resetCalls, 1);
    expect(store.progress.bestResultsByStageId.keys, {
      'outpost-alpha',
      'nebula-relay',
      'salvage-rift',
    });
    expect(
      store.progress.resultFor('salvage-rift'),
      const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
    );
  });

  testWidgets('reset reports failure when no progress store is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OrionGamePage(
          progressStoreLoader: () async => throw StateError('no store'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Reset Campaign'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Could not reset campaign progress.'), findsOneWidget);
    expect(find.text('Campaign reset.'), findsNothing);
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

  test('snapshot exposes stage identity and wave total', () {
    final snapshot = GameSession.initial().snapshot();

    expect(snapshot.stageId, 'outpost-alpha');
    expect(snapshot.stageName, 'Outpost Alpha');
    expect(snapshot.stageLabel, 'Alpha');
    expect(snapshot.waveTotal, 8);
  });

  test('snapshot tower unlocks cannot be mutated after capture', () {
    final snapshot = GameSession.initial().snapshot();

    expect(
      () => snapshot.unlockedTowerTypes[0] = TowerType.droneBay,
      throwsUnsupportedError,
    );
    expect(snapshot.unlockedTowerTypes, [
      TowerType.laser,
      TowerType.rocket,
      TowerType.cryo,
    ]);
  });

  testWidgets('world map shows locked, unlocked, and cleared stages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: OrionCampaign.stages,
            progress: _progressWithResults({'outpost-alpha'}),
            feedback: null,
            onStageSelected: (_) {},
            onLockedStageSelected: (_) {},
            onResetCampaign: () {},
          ),
        ),
      ),
    );

    expect(find.text('Orion Sector Map'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Relay'), findsOneWidget);
    expect(find.text('Core'), findsOneWidget);
    expect(find.text('Cleared'), findsWidgets);
    expect(find.text('Open'), findsWidgets);
    expect(find.text('Locked'), findsWidgets);
  });

  testWidgets('locked stage tap uses locked callback only when locked', (
    tester,
  ) async {
    final selected = <String>[];
    final locked = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: OrionCampaign.stages,
            progress: CampaignProgress(),
            feedback: null,
            onStageSelected: (stage) => selected.add(stage.id),
            onLockedStageSelected: (stage) => locked.add(stage.id),
            onResetCampaign: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Core'));
    expect(selected, isEmpty);
    expect(locked, ['singularity-core']);

    await tester.tap(find.text('Alpha'));
    expect(selected, ['outpost-alpha']);
    expect(locked, ['singularity-core']);
  });

  testWidgets('locked stage node is disabled without locked callback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: OrionCampaign.stages,
            progress: CampaignProgress(),
            feedback: null,
            onStageSelected: (_) {},
            onResetCampaign: () {},
          ),
        ),
      ),
    );

    final coreInkWell = tester.widget<InkWell>(
      find.ancestor(of: find.text('Core'), matching: find.byType(InkWell)),
    );
    final alphaInkWell = tester.widget<InkWell>(
      find.ancestor(of: find.text('Alpha'), matching: find.byType(InkWell)),
    );

    expect(coreInkWell.onTap, isNull);
    expect(alphaInkWell.onTap, isNotNull);
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    if (condition()) {
      return;
    }
    await tester.pump();
  }

  fail('Condition was not met before pump limit.');
}

Finder _activeIgnorePointerAncestorsOf(Finder finder) {
  return find.ancestor(
    of: finder,
    matching: find.byWidgetPredicate(
      (widget) => widget is IgnorePointer && widget.ignoring,
      description: 'active IgnorePointer',
    ),
  );
}

CampaignProgress _progressWithResults(Iterable<String> stageIds) {
  return CampaignProgress(
    bestResultsByStageId: {
      for (final stageId in stageIds)
        stageId: const StageResult(medal: StageMedal.clear, bestBaseHealth: 1),
    },
  );
}

class _TestCampaignProgressStore implements CampaignProgressStore {
  _TestCampaignProgressStore({
    this.loadError,
    this.saveError,
    this.delaySaves = false,
    this.resetResults = const [],
    CampaignProgress? progress,
  }) : progress = progress ?? CampaignProgress();

  final Object? loadError;
  final Object? saveError;
  final bool delaySaves;
  final List<Object?> resetResults;
  final List<Completer<void>> saveCompletions = [];
  CampaignProgress progress;
  int resetCalls = 0;

  @override
  Future<CampaignProgress> load() async {
    final error = loadError;
    if (error != null) {
      throw error;
    }
    return progress;
  }

  @override
  Future<void> save(CampaignProgress progress) async {
    if (delaySaves) {
      final completer = Completer<void>();
      saveCompletions.add(completer);
      await completer.future;
    }

    final error = saveError;
    if (error != null) {
      throw error;
    }

    this.progress = progress;
  }

  @override
  Future<void> reset() async {
    final result = resetCalls < resetResults.length
        ? resetResults[resetCalls]
        : null;
    resetCalls += 1;

    if (result != null) {
      throw result;
    }

    progress = CampaignProgress();
  }
}
