import 'dart:async';

import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/tech_tree.dart';
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

  testWidgets('victory panel shows earned medal and base health', (
    tester,
  ) async {
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
      phase: GamePhase.won,
      gold: snapshot.gold,
      baseHealth: 14,
      startingBaseHealth: snapshot.startingBaseHealth,
      waveNumber: snapshot.waveTotal,
      waveTotal: snapshot.waveTotal,
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      stageLabel: snapshot.stageLabel,
      unlockedTowerTypes: snapshot.unlockedTowerTypes,
      nextWavePreview: null,
      selectedCell: snapshot.selectedCell,
      selectedTower: snapshot.selectedTower,
      feedback: snapshot.feedback,
      isPaused: snapshot.isPaused,
      speedMultiplier: snapshot.speedMultiplier,
      autoStartEnabled: snapshot.autoStartEnabled,
      autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
    );
    await tester.pump();

    expect(find.text('Victory'), findsOneWidget);
    expect(find.text('Silver medal - Base 14/20'), findsOneWidget);
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
      startingBaseHealth: snapshot.startingBaseHealth,
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
        CampaignSave(
          progress: _progressWithResults({
            'outpost-alpha',
            'nebula-relay',
            'asteroid-foundry',
            'aurora-gate',
          }),
          techTree: CampaignTechTree(),
        ),
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

  testWidgets(
    'optimistic stage clear is visible on map before save fails, then reverts',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({'outpost-alpha'}),
        delaySaves: true,
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
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

      game!.returnToMap();
      await tester.pumpAndSettle();

      // Optimistic: Relay shows as cleared with Silver medal before save
      // completes.
      expect(find.text('Relay'), findsOneWidget);
      expect(find.text('Silver'), findsOneWidget);

      // Complete the save → throws → rollback to prior progress.
      store.saveCompletions.single.complete();
      await tester.pumpAndSettle();

      expect(find.text('Relay'), findsOneWidget);
      expect(find.text('Silver'), findsNothing);
      expect(find.text('Open'), findsWidgets);
      expect(find.text('Could not save campaign progress.'), findsOneWidget);
    },
  );

  testWidgets(
    'blocks stage launch while a stage-completion save is in flight',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({'outpost-alpha', 'nebula-relay'}),
        delaySaves: true,
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

      // Start a stage, then fire onStageWon for salvage-rift (bonus gold).
      await tester.tap(find.text('Foundry'));
      await tester.pumpAndSettle();

      game!.onStageWon?.call(
        StageCompletion(
          stage: OrionCampaign.stageById('salvage-rift'),
          result: const StageResult(
            medal: StageMedal.silver,
            bestBaseHealth: 14,
          ),
        ),
      );
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

      // Return to map while the save is still pending.
      game!.returnToMap();
      await tester.pumpAndSettle();

      // Tapping another stage must not launch it while the save is in flight.
      await tester.tap(find.text('Relay'));
      await tester.pumpAndSettle();

      expect(find.text('Orion Sector Map'), findsOneWidget);
      expect(find.text('Start Wave'), findsNothing);

      // Complete the save → it throws → progress rolls back.
      store.saveCompletions.single.complete();
      await tester.pumpAndSettle();

      // Now the stage can be started, and it must NOT carry the bonus gold
      // from the reverted salvage-rift clear.
      await tester.tap(find.text('Relay'));
      await tester.pumpAndSettle();

      expect(find.text('Start Wave'), findsOneWidget);
      expect(find.text('Gold 150'), findsOneWidget);
      expect(find.text('Gold 180'), findsNothing);
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

  testWidgets(
    'persists queued stage save even if page is disposed before it runs',
    (tester) async {
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

      // Queue two saves; the first is delayed so the second waits in _saveQueue.
      game!.onStageWon?.call(
        StageCompletion(
          stage: OrionCampaign.stageById('salvage-rift'),
          result: const StageResult(
            medal: StageMedal.silver,
            bestBaseHealth: 14,
          ),
        ),
      );
      game!.onStageWon?.call(
        StageCompletion(
          stage: OrionCampaign.stageById('asteroid-foundry'),
          result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
        ),
      );

      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

      // Dispose OrionGamePage while the first save is still pending, so the
      // second _saveStageCompletion will run on an unmounted widget.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      // Complete the first save; the second _saveStageCompletion now runs.
      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();

      // The second save is also delayed; complete it.
      await _pumpUntil(tester, () => store.saveCompletions.length > 1);
      store.saveCompletions[1].complete();
      await tester.pumpAndSettle();

      expect(store.saveCalls, 2);
      expect(
        store.progress.bestResultsByStageId.keys,
        contains('asteroid-foundry'),
      );
      expect(
        store.progress.resultFor('asteroid-foundry'),
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );
    },
  );

  testWidgets(
    'queued save after disposal keeps earlier queued result in store',
    (tester) async {
      // Regression: when a save's _saveStageCompletion runs after the page is
      // disposed, _progress must still advance so a later queued save derives
      // from the latest in-memory state instead of overwriting the store with
      // stale progress that drops the earlier result.
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

      // Prior save keeps _saveQueue pending so the next two saves queue behind
      // it and only run after disposal.
      game!.onStageWon?.call(
        StageCompletion(
          stage: OrionCampaign.stageById('salvage-rift'),
          result: const StageResult(
            medal: StageMedal.silver,
            bestBaseHealth: 14,
          ),
        ),
      );
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

      // Queue two more saves; neither runs until the prior save completes.
      game!.onStageWon?.call(
        StageCompletion(
          stage: OrionCampaign.stageById('asteroid-foundry'),
          result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
        ),
      );
      game!.onStageWon?.call(
        StageCompletion(
          stage: OrionCampaign.stageById('aurora-gate'),
          result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 18),
        ),
      );

      // Dispose before the queued saves run, so both _saveStageCompletion calls
      // execute on an unmounted widget.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      // Complete the prior save; the first queued save now runs unmounted.
      store.saveCompletions[0].complete();
      await _pumpUntil(tester, () => store.saveCompletions.length > 1);
      store.saveCompletions[1].complete();
      await _pumpUntil(tester, () => store.saveCompletions.length > 2);
      store.saveCompletions[2].complete();
      await tester.pumpAndSettle();

      expect(store.saveCalls, 3);
      // The asteroid-foundry result from the first queued save must survive the
      // second queued save's overwrite of the store snapshot.
      expect(
        store.progress.bestResultsByStageId.keys,
        contains('asteroid-foundry'),
      );
      expect(
        store.progress.resultFor('asteroid-foundry'),
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );
      expect(
        store.progress.resultFor('aurora-gate'),
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 18),
      );
    },
  );

  testWidgets('stage replay save does not downgrade an existing medal', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      saveError: StateError('save failed'),
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
    expect(store.saveCalls, 0);
    expect(find.text('Could not save campaign progress.'), findsNothing);
  });

  testWidgets(
    'failed reset retains progress after a pending save drains (serialized)',
    (tester) async {
      // Round-3 review P1/P2: the reset is serialized behind the save queue.
      // The pending save completes first (persisting its result), then the
      // reset runs and fails. Progress — including the just-saved result —
      // is retained. The generation bump is monotonic and never rolled back.
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({'outpost-alpha', 'nebula-relay'}),
        delaySaves: true,
        resetResults: [StateError('reset failed')],
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
          result: const StageResult(
            medal: StageMedal.silver,
            bestBaseHealth: 14,
          ),
        ),
      );
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

      game!.returnToMap();
      await tester.pumpAndSettle();

      // The Reset button is disabled while the save is in flight. Drain the
      // pending save first, then trigger the reset.
      store.saveCompletions.single.complete();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Reset Campaign'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await tester.pumpAndSettle();

      expect(find.text('Could not reset campaign progress.'), findsOneWidget);
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
    },
  );

  testWidgets('successful reset after a pending save drains wipes the store', (
    tester,
  ) async {
    // Round-3 review P1/P2: the reset is serialized behind the save queue.
    // The pending save completes first (writing its data), then the reset
    // runs and wipes the store. No post-stale-save cleanup is needed
    // because the reset runs after — not racing with — the save.
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

    // Queue a stage-completion save (delayed).
    game!.onStageWon?.call(
      StageCompletion(
        stage: OrionCampaign.stageById('salvage-rift'),
        result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      ),
    );
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

    game!.returnToMap();
    await tester.pumpAndSettle();

    // Drain the pending save first; the Reset button is disabled while
    // the save is in flight.
    store.saveCompletions.single.complete();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Reset Campaign'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Campaign reset.'), findsOneWidget);
    expect(store.resetCalls, 1);
    expect(store.progress.bestResultsByStageId, isEmpty);
    expect(store.techTree.purchased, isEmpty);
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

  testWidgets('reset is single-flight: a second reset is blocked', (
    tester,
  ) async {
    // Round-3 review P1: concurrent resets could move the generation
    // backwards and resurrect stale progress. The reset is now
    // single-flight — the Reset button is disabled while a reset is in
    // flight, and a second programmatic call is a no-op.
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha', 'nebula-relay'}),
      delayResets: true,
    );

    await tester.pumpWidget(
      MaterialApp(home: OrionGamePage(progressStore: store)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Reset Campaign'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    // The reset is now in flight (delayed). The Reset button must be
    // disabled, so tapping it does nothing.
    expect(store.resetCalls, 1);
    expect(store.resetCompletions, isNotEmpty);

    final resetButton = find.byTooltip('Reset Campaign');
    await tester.tap(resetButton);
    await tester.pumpAndSettle();

    // No second reset was triggered.
    expect(store.resetCalls, 1);

    // Complete the in-flight reset.
    store.resetCompletions.single.complete();
    await tester.pumpAndSettle();

    expect(find.text('Campaign reset.'), findsOneWidget);
    expect(store.resetCalls, 1);
  });

  testWidgets(
    'failed first queued save does not clobber a later queued save (P2b)',
    (tester) async {
      // Round-3 review P2b: _saveQueue previously covered only store.save,
      // so a failed first save's full-snapshot rollback could overwrite a
      // later save's optimistic update. With targeted rollback, the first
      // save's failure removes only its own stage result; the second save's
      // result survives and is persisted.
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({'outpost-alpha', 'nebula-relay'}),
        delaySaves: true,
        failOnSaveIndices: {0},
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

      // Queue two stage-completion saves. The first (salvage-rift) will
      // fail; the second (asteroid-foundry) should succeed.
      game!.onStageWon?.call(
        StageCompletion(
          stage: OrionCampaign.stageById('salvage-rift'),
          result: const StageResult(
            medal: StageMedal.silver,
            bestBaseHealth: 14,
          ),
        ),
      );
      game!.onStageWon?.call(
        StageCompletion(
          stage: OrionCampaign.stageById('asteroid-foundry'),
          result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
        ),
      );

      // Complete the first save — it throws and rolls back salvage-rift only.
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
      store.saveCompletions[0].complete();
      await _pumpUntil(tester, () => store.saveCompletions.length > 1);

      // Complete the second save — it persists asteroid-foundry.
      store.saveCompletions[1].complete();
      await tester.pumpAndSettle();

      expect(store.saveCalls, 2);
      // salvage-rift was rolled back; asteroid-foundry survives.
      expect(
        store.progress.bestResultsByStageId.keys,
        contains('asteroid-foundry'),
      );
      expect(
        store.progress.bestResultsByStageId.keys,
        isNot(contains('salvage-rift')),
      );
      expect(
        store.progress.resultFor('asteroid-foundry'),
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );
    },
  );

  testWidgets(
    'failed stage save rolls back only progress, not a later tech purchase',
    (tester) async {
      // Field-scoped rollback (HPA-100): a failed stage-completion save must
      // restore _progress to its prior value without clobbering the tech tree
      // a subsequent purchase writes. The stage save (first) fails; the
      // purchase save (second) succeeds and its techTree value survives.
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({
          'outpost-alpha',
          'nebula-relay',
          'asteroid-foundry',
        }),
        failOnSaveIndices: const {0},
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

      // Queue a stage-completion save (save 0) — it fails on persistence.
      game!.onStageWon?.call(
        StageCompletion(
          stage: OrionCampaign.stageById('salvage-rift'),
          result: const StageResult(
            medal: StageMedal.silver,
            bestBaseHealth: 14,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Field-scoped rollback: _progress restored to prior (no salvage-rift).
      expect(store.progress.bestResultsByStageId.keys, {
        'outpost-alpha',
        'nebula-relay',
        'asteroid-foundry',
      });
      expect(store.progress.resultFor('salvage-rift'), isNull);

      // Return to the map and open the tech tree to queue a purchase save.
      game!.returnToMap();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Tech Tree'));
      await tester.pumpAndSettle();

      // With 3 clear medals only Solar Capacitors (cost 3) is affordable, so
      // exactly one "Purchase" button is present.
      await tester.tap(find.text('Purchase'));
      await tester.pumpAndSettle();

      // The purchase save (save 1) succeeded; the techTree retains the new
      // value despite the earlier stage save's failure path having run.
      expect(store.saveCalls, 2);
      expect(
        store.techTree.isPurchased(CampaignTechUpgrade.solarCapacitors),
        isTrue,
      );
    },
  );

  testWidgets(
    'failed purchase save sets feedback on both tech tree and map views',
    (tester) async {
      // Dual-targeting feedback routing (HPA-100): a purchase save that fails
      // while on the tech tree view must set _techTreeFeedback (visible now)
      // AND _mapFeedback (breadcrumb for when the player returns to the map).
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({
          'outpost-alpha',
          'nebula-relay',
          'asteroid-foundry',
        }),
        saveError: StateError('save failed'),
      );

      await tester.pumpWidget(
        MaterialApp(home: OrionGamePage(progressStore: store)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Tech Tree'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Purchase'));
      await tester.pumpAndSettle();

      // _techTreeFeedback: the tech tree view shows the failure inline.
      expect(find.text('Could not save campaign progress.'), findsOneWidget);
      // Rollback: Solar Capacitors is still purchasable (not "Purchased").
      expect(find.text('Purchase'), findsOneWidget);

      // _mapFeedback: return to the map and confirm the breadcrumb survives.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Could not save campaign progress.'), findsOneWidget);
      expect(find.text('Orion Sector Map'), findsOneWidget);
    },
  );

  testWidgets(
    'successful purchase clears stale tech tree feedback from prior failure',
    (tester) async {
      // tech-tree-design.md:395 — _techTreeFeedback clears on the next
      // successful purchase. A prior failure's error must not persist on
      // screen after the retry succeeds.
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({
          'outpost-alpha',
          'nebula-relay',
          'asteroid-foundry',
        }),
        failOnSaveIndices: {0},
      );

      await tester.pumpWidget(
        MaterialApp(home: OrionGamePage(progressStore: store)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Tech Tree'));
      await tester.pumpAndSettle();

      // First purchase attempt fails (save index 0).
      await tester.tap(find.text('Purchase'));
      await tester.pumpAndSettle();

      expect(find.text('Could not save campaign progress.'), findsOneWidget);
      // Rollback: still purchasable.
      expect(find.text('Purchase'), findsOneWidget);

      // Second purchase attempt succeeds (save index 1).
      await tester.tap(find.text('Purchase'));
      await tester.pumpAndSettle();

      // Stale feedback must be cleared.
      expect(find.text('Could not save campaign progress.'), findsNothing);
      // The upgrade is now purchased.
      expect(find.text('Purchase'), findsNothing);
      expect(
        store.techTree.isPurchased(CampaignTechUpgrade.solarCapacitors),
        isTrue,
      );
    },
  );

  testWidgets(
    'null store shows persistence failure and does not throw on stage save',
    (tester) async {
      // Null-store guard (HPA-100): when _store is null, _persistSave must
      // surface the persistence-failure feedback and return without throwing.
      OrionDefenseGame? game;

      await tester.pumpWidget(
        MaterialApp(
          home: OrionGamePage(
            progressStoreLoader: () async => throw StateError('no store'),
            onGameCreated: (created) => game = created,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Load failed → _store is null. Alpha is still unlocked and launchable.
      expect(find.text('Could not load campaign progress.'), findsOneWidget);

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      // Fire onStageWon → _persistSave hits the null-store guard. No throw;
      // the failure feedback is routed to the active game's HUD.
      game!.onStageWon?.call(
        StageCompletion(
          stage: OrionCampaign.stageById('salvage-rift'),
          result: const StageResult(
            medal: StageMedal.silver,
            bestBaseHealth: 14,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not save campaign progress.'), findsOneWidget);
    },
  );

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

  testWidgets('Tech Tree button fires onOpenTechTree', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: const [],
            progress: CampaignProgress(),
            feedback: null,
            onStageSelected: (_) {},
            onResetCampaign: () {},
            onOpenTechTree: () => tapped++,
          ),
        ),
      ),
    );

    // Wired callback → button is visible and tappable.
    await tester.tap(find.byTooltip('Tech Tree'));
    expect(tapped, 1);
  });

  testWidgets('Tech Tree button is hidden when onOpenTechTree is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: const [],
            progress: CampaignProgress(),
            feedback: null,
            onStageSelected: (_) {},
            onResetCampaign: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Tech Tree'), findsNothing);
  });

  testWidgets(
    'tapping Tech Tree button opens TechTreeView and back returns to map',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const OrionApp());
      await tester.pumpAndSettle();

      // Sanity: button is present on the world map header.
      expect(find.byTooltip('Tech Tree'), findsOneWidget);

      await tester.tap(find.byTooltip('Tech Tree'));
      await tester.pumpAndSettle();

      // TechTreeView is now rendered (T12): its header appears and the
      // world-map header is replaced.
      expect(find.text('Campaign Tech Tree'), findsOneWidget);
      expect(find.text('Orion Sector Map'), findsNothing);

      // The back arrow returns the player to the world map.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Orion Sector Map'), findsOneWidget);
      expect(find.text('Campaign Tech Tree'), findsNothing);
    },
  );

  testWidgets('world map shows locked, unlocked, and cleared stages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: OrionCampaign.stages,
            progress: CampaignProgress(
              bestResultsByStageId: {
                'outpost-alpha': const StageResult(
                  medal: StageMedal.gold,
                  bestBaseHealth: 20,
                ),
              },
            ),
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
    expect(find.text('Gold'), findsOneWidget);
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

  testWidgets(
    'selected tower panel shows targeting chips reflecting the current mode',
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

      final snapshot = game!.stateNotifier.value;
      const selectedTower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
        targetingMode: TowerTargetingMode.strongest,
      );
      game!.stateNotifier.value = GameSnapshot(
        phase: GamePhase.build,
        gold: snapshot.gold,
        baseHealth: snapshot.baseHealth,
        startingBaseHealth: snapshot.startingBaseHealth,
        waveNumber: snapshot.waveNumber,
        waveTotal: snapshot.waveTotal,
        stageId: snapshot.stageId,
        stageName: snapshot.stageName,
        stageLabel: snapshot.stageLabel,
        unlockedTowerTypes: snapshot.unlockedTowerTypes,
        nextWavePreview: snapshot.nextWavePreview,
        selectedCell: snapshot.selectedCell,
        selectedTower: selectedTower,
        feedback: snapshot.feedback,
        isPaused: snapshot.isPaused,
        speedMultiplier: snapshot.speedMultiplier,
        autoStartEnabled: snapshot.autoStartEnabled,
        autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
      );
      await tester.pump();

      for (final mode in TowerTargetingMode.values) {
        expect(find.text(mode.label), findsOneWidget);
      }
      final strongestChip = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('Strongest'),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(strongestChip.selected, isTrue);
    },
  );

  testWidgets('targeting chips are disabled during wave phase', (tester) async {
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
    const selectedTower = PlacedTower(
      id: 1,
      type: TowerType.laser,
      position: GridPosition(0, 0),
    );
    game!.stateNotifier.value = GameSnapshot(
      phase: GamePhase.wave,
      gold: snapshot.gold,
      baseHealth: snapshot.baseHealth,
      startingBaseHealth: snapshot.startingBaseHealth,
      waveNumber: snapshot.waveNumber,
      waveTotal: snapshot.waveTotal,
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      stageLabel: snapshot.stageLabel,
      unlockedTowerTypes: snapshot.unlockedTowerTypes,
      nextWavePreview: snapshot.nextWavePreview,
      selectedCell: snapshot.selectedCell,
      selectedTower: selectedTower,
      feedback: snapshot.feedback,
      isPaused: snapshot.isPaused,
      speedMultiplier: snapshot.speedMultiplier,
      autoStartEnabled: snapshot.autoStartEnabled,
      autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
    );
    await tester.pump();

    final firstChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('First'), matching: find.byType(ChoiceChip)),
    );
    expect(firstChip.onSelected, isNull);
  });

  testWidgets('tapping a targeting chip invokes game.setTargetingMode', (
    tester,
  ) async {
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
    const selectedTower = PlacedTower(
      id: 1,
      type: TowerType.laser,
      position: GridPosition(0, 0),
      targetingMode: TowerTargetingMode.first,
    );
    game!.stateNotifier.value = GameSnapshot(
      phase: GamePhase.build,
      gold: snapshot.gold,
      baseHealth: snapshot.baseHealth,
      startingBaseHealth: snapshot.startingBaseHealth,
      waveNumber: snapshot.waveNumber,
      waveTotal: snapshot.waveTotal,
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      stageLabel: snapshot.stageLabel,
      unlockedTowerTypes: snapshot.unlockedTowerTypes,
      nextWavePreview: snapshot.nextWavePreview,
      selectedCell: snapshot.selectedCell,
      selectedTower: selectedTower,
      feedback: snapshot.feedback,
      isPaused: snapshot.isPaused,
      speedMultiplier: snapshot.speedMultiplier,
      autoStartEnabled: snapshot.autoStartEnabled,
      autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
    );
    await tester.pump();

    // The game session has no real selected tower, so retargeting reports the
    // "select a tower first" feedback — proving the chip callback ran.
    await tester.tap(find.text('Weakest'));
    await tester.pump();

    expect(find.text('Select a tower first.'), findsOneWidget);
  });

  testWidgets('selected tower panel stacks summary and actions when narrow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    OrionDefenseGame? game;

    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: OrionGamePage(onGameCreated: (created) => game = created),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    final snapshot = game!.stateNotifier.value;
    const selectedTower = PlacedTower(
      id: 1,
      type: TowerType.laser,
      position: GridPosition(0, 0),
    );
    game!.stateNotifier.value = GameSnapshot(
      phase: GamePhase.build,
      gold: snapshot.gold,
      baseHealth: snapshot.baseHealth,
      startingBaseHealth: snapshot.startingBaseHealth,
      waveNumber: snapshot.waveNumber,
      waveTotal: snapshot.waveTotal,
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      stageLabel: snapshot.stageLabel,
      unlockedTowerTypes: snapshot.unlockedTowerTypes,
      nextWavePreview: snapshot.nextWavePreview,
      selectedCell: snapshot.selectedCell,
      selectedTower: selectedTower,
      feedback: snapshot.feedback,
      isPaused: snapshot.isPaused,
      speedMultiplier: snapshot.speedMultiplier,
      autoStartEnabled: snapshot.autoStartEnabled,
      autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
    );
    await tester.pump();

    // The narrow-width branch renders the targeting picker; the "Targeting"
    // label confirms the panel built via the stacked Column layout.
    expect(find.text('Targeting'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
  });

  testWidgets(
    'starting a stage after clearing salvage rift applies bonus gold',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = InMemoryCampaignProgressStore(
        knownStages: OrionCampaign.stages,
      );
      await store.save(
        CampaignSave(
          progress: CampaignProgress(
            bestResultsByStageId: {
              'outpost-alpha': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
              'nebula-relay': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
              'salvage-rift': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
            },
          ),
          techTree: CampaignTechTree(),
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

      // Tap the salvage-rift stage node (it should be unlocked).
      await tester.tap(find.text('Rift'));
      await tester.pumpAndSettle();

      expect(game, isNotNull);
      expect(
        game!.snapshot.gold,
        GameBalance.startingGold + GameBalance.salvageRiftGoldBonus,
      );
    },
  );

  testWidgets('world map shows reward teaser on uncleared side stage', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = InMemoryCampaignProgressStore(
      knownStages: OrionCampaign.stages,
    );

    await tester.pumpWidget(
      MaterialApp(home: OrionGamePage(progressStore: store)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reward: +30 Gold'), findsOneWidget);
    expect(find.text('Reward: +5 HP'), findsOneWidget);
  });

  testWidgets('world map shows earned reward label on cleared side stage', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = InMemoryCampaignProgressStore(
      knownStages: OrionCampaign.stages,
    );
    await store.save(
      CampaignSave(
        progress: CampaignProgress(
          bestResultsByStageId: {
            'outpost-alpha': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'nebula-relay': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'salvage-rift': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
          },
        ),
        techTree: CampaignTechTree(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: OrionGamePage(progressStore: store)),
    );
    await tester.pumpAndSettle();

    expect(find.text('+30 Gold'), findsOneWidget);
  });

  testWidgets(
    'world map shows challenge badge when both side stages are cleared',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = InMemoryCampaignProgressStore(
        knownStages: OrionCampaign.stages,
      );
      await store.save(
        CampaignSave(
          progress: CampaignProgress(
            bestResultsByStageId: {
              'outpost-alpha': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
              'nebula-relay': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
              'asteroid-foundry': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
              'aurora-gate': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
              'salvage-rift': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
              'void-bastion': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
            },
          ),
          techTree: CampaignTechTree(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: OrionGamePage(progressStore: store)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Challenge Badge Earned - All side stages cleared'),
        findsOneWidget,
      );
    },
  );
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
    this.delayResets = false,
    this.failOnSaveIndices = const {},
    this.resetResults = const [],
    CampaignProgress? progress,
    CampaignTechTree? techTree,
  }) : progress = progress ?? CampaignProgress(),
       techTree = techTree ?? CampaignTechTree();

  final Object? loadError;
  final Object? saveError;
  final bool delaySaves;
  final bool delayResets;
  final Set<int> failOnSaveIndices;
  final List<Object?> resetResults;
  final List<Completer<void>> saveCompletions = [];
  final List<Completer<void>> resetCompletions = [];
  CampaignProgress progress;
  CampaignTechTree techTree;
  int saveCalls = 0;
  int resetCalls = 0;

  @override
  Future<CampaignSave> load() async {
    final error = loadError;
    if (error != null) {
      throw error;
    }
    return CampaignSave(progress: progress, techTree: techTree);
  }

  @override
  Future<void> save(CampaignSave save) async {
    saveCalls += 1;

    if (delaySaves) {
      final completer = Completer<void>();
      saveCompletions.add(completer);
      await completer.future;
    }

    if (failOnSaveIndices.contains(saveCalls - 1)) {
      throw StateError('save ${saveCalls - 1} failed');
    }
    final error = saveError;
    if (error != null) {
      throw error;
    }

    progress = save.progress;
    techTree = save.techTree;
  }

  @override
  Future<void> reset() async {
    resetCalls += 1;

    if (delayResets) {
      final completer = Completer<void>();
      resetCompletions.add(completer);
      await completer.future;
    }

    final result = resetCalls - 1 < resetResults.length
        ? resetResults[resetCalls - 1]
        : null;
    if (result != null) {
      throw result;
    }

    progress = CampaignProgress();
    techTree = CampaignTechTree();
  }
}
