import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/feedback/feedback_preferences.dart';
import 'package:orion/game/feedback/game_feedback.dart';
import 'package:orion/game/feedback/game_music.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/onboarding/first_mission_guide_store.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/ui/orion_game_page.dart';
import 'package:orion/game/ui/feedback_settings_sheet.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widget_test.dart' as harness;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('waits for preferences and follows every app lifecycle state', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    addTearDown(() {
      final state = tester.binding.lifecycleState;
      if (state != AppLifecycleState.inactive &&
          state != AppLifecycleState.detached) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    final player = _RecordingMusicPlayer();
    final store = _RecordingPreferencesStore(loadGate: Completer());
    await _mountPage(tester, player: player, preferencesStore: store);

    expect(player.calls, isEmpty);
    store.loadGate!.complete(const FeedbackPreferences());
    await tester.pumpAndSettle();
    expect(player.calls, isEmpty, reason: 'the app was already paused');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(player.calls, ['play:music_map.wav']);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    expect(player.calls, ['play:music_map.wav', 'stop']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(player.calls, ['play:music_map.wav', 'stop', 'play:music_map.wav']);
    await _unmountPage(tester);
  });

  testWidgets('falls back to default music after preference load failure', (
    tester,
  ) async {
    final player = _RecordingMusicPlayer();
    await _mountPage(
      tester,
      player: player,
      preferencesStore: _RecordingPreferencesStore(
        loadError: StateError('preferences unavailable'),
      ),
    );

    expect(player.calls, ['play:music_map.wav']);
    await _unmountPage(tester);
  });

  testWidgets(
    'cancel and failed saves keep music; toggles persist independently',
    (tester) async {
      final player = _RecordingMusicPlayer();
      final store = _RecordingPreferencesStore();
      await _mountPage(tester, player: player, preferencesStore: store);

      await _openSettings(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Music'));
      await tester.pump();
      Navigator.of(tester.element(find.byType(FeedbackSettingsSheet))).pop();
      await tester.pumpAndSettle();
      expect(store.saveCalls, 0);
      expect(player.calls, ['play:music_map.wav']);

      store.saveError = StateError('save failed');
      await _openSettings(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Music'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(store.value.musicEnabled, isTrue);
      expect(player.calls, ['play:music_map.wav']);

      await _openSettings(tester);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Music'),
            )
            .value,
        isTrue,
      );
      store.saveError = null;
      await tester.tap(find.widgetWithText(SwitchListTile, 'Music'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(store.value, const FeedbackPreferences(musicEnabled: false));
      expect(player.calls, ['play:music_map.wav', 'stop']);

      await _openSettings(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Sound Effects'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        store.value,
        const FeedbackPreferences(
          soundEffectsEnabled: false,
          musicEnabled: false,
        ),
      );

      await _openSettings(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Haptics'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        store.value,
        const FeedbackPreferences(
          soundEffectsEnabled: false,
          hapticsEnabled: false,
          musicEnabled: false,
        ),
      );
      await _unmountPage(tester);
    },
  );

  testWidgets(
    'stage, pause, terminal, retry, return, reset and stale events sync',
    (tester) async {
      final player = _RecordingMusicPlayer();
      final controller = GameMusicController(player: player);
      final games = <OrionDefenseGame>[];
      await _mountPage(
        tester,
        controller: controller,
        onGameCreated: games.add,
      );

      await harness.startStageFromBriefing(tester);
      await tester.pump();
      final firstGame = games.single;
      expect(player.calls, [
        'play:music_map.wav',
        'stop',
        'play:music_build.wav',
      ]);

      firstGame.startWave();
      await tester.pump();
      expect(player.calls.last, 'play:music_wave.wav');
      firstGame.togglePause();
      await tester.pump();
      expect(player.calls.last, 'stop');
      firstGame.togglePause();
      await tester.pump();
      expect(player.calls.last, 'play:music_wave.wav');

      firstGame.stateNotifier.value = _snapshotLike(
        firstGame.snapshot,
        phase: GamePhase.won,
      );
      await tester.pump();
      expect(player.calls.last, 'stop');
      firstGame.restart();
      await tester.pump();
      expect(player.calls.last, 'play:music_build.wav');

      firstGame.stateNotifier.value = _snapshotLike(
        firstGame.snapshot,
        phase: GamePhase.lost,
      );
      await tester.pump();
      expect(player.calls.last, 'stop');
      await tester.tap(find.byTooltip('Retry'));
      await tester.pump();
      expect(player.calls.last, 'play:music_build.wav');

      firstGame.returnToMap();
      firstGame.stateNotifier.value = _snapshotLike(
        firstGame.snapshot,
        phase: GamePhase.wave,
      );
      await tester.pump();
      expect(player.calls.last, 'play:music_map.wav');
      await harness.startStageFromBriefing(tester);
      await tester.pump();
      final secondGame = games.last;
      expect(secondGame, isNot(same(firstGame)));
      expect(player.calls.last, 'play:music_build.wav');

      secondGame.returnToMap();
      await tester.pump();
      expect(player.calls.last, 'play:music_map.wav');
      await tester.tap(find.byTooltip('Reset Campaign'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(player.calls.last, 'play:music_map.wav');

      await _unmountPage(tester);
      expect(player.calls, isNot(contains('dispose')));
    },
  );

  testWidgets('default production page tolerates throwing audio stubs', (
    tester,
  ) async {
    final inheritedLifecycleState = tester.binding.lifecycleState;
    _resumeApp(tester);
    final previousDebugPrint = debugPrint;
    final messages = <String>[];
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };
    final preferencesStore = _RecordingPreferencesStore();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: orionThemeData,
          home: OrionGamePage(
            progressStore: InMemoryCampaignProgressStore(
              knownStages: OrionCampaign.stages,
            ),
            feedbackPreferencesStore: preferencesStore,
            firstMissionGuideStore: InMemoryFirstMissionGuideStore(
              completed: true,
            ),
            gameFeedback: const NoOpGameFeedback(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(preferencesStore.loadCalls, 1);
      expect(preferencesStore.loadCompleted, isTrue);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(
        messages.any(
          (message) =>
              message.contains('GameMusicController: failed to') &&
              message.contains('audioplayers unavailable'),
        ),
        isTrue,
        reason:
            'the default lazy Bgm error should be contained and logged; '
            'inherited lifecycle was $inheritedLifecycleState: $messages',
      );
    } finally {
      debugPrint = previousDebugPrint;
    }
  });
}

Future<void> _mountPage(
  WidgetTester tester, {
  MusicPlayer? player,
  GameMusicController? controller,
  FeedbackPreferencesStore? preferencesStore,
  ValueChanged<OrionDefenseGame>? onGameCreated,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => _unmountPage(tester));
  await tester.pumpWidget(
    MaterialApp(
      theme: orionThemeData,
      home: OrionGamePage(
        progressStore: InMemoryCampaignProgressStore(
          knownStages: OrionCampaign.stages,
        ),
        feedbackPreferencesStore:
            preferencesStore ?? _RecordingPreferencesStore(),
        firstMissionGuideStore: InMemoryFirstMissionGuideStore(completed: true),
        gameFeedback: const NoOpGameFeedback(),
        gameMusicController:
            controller ??
            (player == null ? null : GameMusicController(player: player)),
        onGameCreated: onGameCreated,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _unmountPage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
}

void _resumeApp(WidgetTester tester) {
  switch (tester.binding.lifecycleState) {
    case null:
    case AppLifecycleState.inactive:
    case AppLifecycleState.detached:
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    case AppLifecycleState.hidden:
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    case AppLifecycleState.paused:
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    case AppLifecycleState.resumed:
      break;
  }
}

GameSnapshot _snapshotLike(
  GameSnapshot source, {
  GamePhase? phase,
  bool? isPaused,
}) => GameSnapshot(
  phase: phase ?? source.phase,
  gold: source.gold,
  baseHealth: source.baseHealth,
  startingBaseHealth: source.startingBaseHealth,
  waveNumber: source.waveNumber,
  waveTotal: source.waveTotal,
  stageId: source.stageId,
  stageName: source.stageName,
  stageLabel: source.stageLabel,
  unlockedTowerTypes: source.unlockedTowerTypes,
  stageModifiers: source.stageModifiers,
  nextWavePreview: source.nextWavePreview,
  selectedCell: source.selectedCell,
  selectedTower: source.selectedTower,
  selectedCellBuildable: source.selectedCellBuildable,
  feedback: source.feedback,
  isPaused: isPaused ?? source.isPaused,
  bossActive: source.bossActive,
  speedMultiplier: source.speedMultiplier,
  autoStartEnabled: source.autoStartEnabled,
  autoStartCountdownRemaining: source.autoStartCountdownRemaining,
  pendingRunModuleOffer: source.pendingRunModuleOffer,
  acquiredRunModules: source.acquiredRunModules,
  placedTowers: source.placedTowers,
  selectedTowerStats: source.selectedTowerStats,
  selectedTowerUpgradeStats: source.selectedTowerUpgradeStats,
  selectedTowerSpecializationStats: source.selectedTowerSpecializationStats,
  pendingRunModuleBeneficiaries: source.pendingRunModuleBeneficiaries,
);

class _RecordingPreferencesStore implements FeedbackPreferencesStore {
  _RecordingPreferencesStore({this.loadGate, this.loadError})
    : value = const FeedbackPreferences();

  FeedbackPreferences value;
  final Completer<FeedbackPreferences>? loadGate;
  final Object? loadError;
  Object? saveError;
  int saveCalls = 0;
  int loadCalls = 0;
  bool loadCompleted = false;

  @override
  Future<FeedbackPreferences> load() async {
    loadCalls++;
    final error = loadError;
    if (error != null) throw error;
    final loaded = await (loadGate?.future ?? Future.value(value));
    loadCompleted = true;
    return loaded;
  }

  @override
  Future<void> save(FeedbackPreferences preferences) async {
    saveCalls++;
    final error = saveError;
    if (error != null) throw error;
    value = preferences;
  }
}

class _RecordingMusicPlayer implements MusicPlayer {
  final calls = <String>[];

  @override
  Future<void> play(String filename) async => calls.add('play:$filename');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> dispose() async => calls.add('dispose');
}
