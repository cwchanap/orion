import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/components/enemy_component.dart';
import 'package:orion/game/components/projectile_component.dart';
import 'package:orion/game/feedback/game_feedback.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/rules/board_layout.dart';
import 'package:orion/game/rules/module_offer_picker.dart';
import 'package:orion/game/rules/run_module_unlocks.dart';

/// Headless real-game proofs for HPA-922 Task 4:
///
/// 1. The two fresh-profile starters (Haruto + Mio at level 1) clear the
///    actual `OrionCampaign.stageOne`.
/// 2. A moderate-progression six-member E–C squad at persistent level 20
///    clears every `OrionCampaign.mainStages` entry.
///
/// Each proof runs the real game loop — all scripted waves, real spawns,
/// real combat through `game.update(1/30)`, real module drafts, the real
/// wave-8 boss — with no force-completion, no elevated gold/health and no
/// stage overrides. The `deploy: false` variant proves a squad that never
/// fights measurably loses. Baseline wave-by-wave measurements live in
/// `task-4-baseline-report.md`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Haruto and Mio starters clear real Stage 1 through the wave-8 boss',
    () {
      _expectStageVictory(_playStage(_starterStageOneScript()));
    },
  );

  test(
    'an empty deployment loses Stage 1 — the harness measures real combat',
    () {
      final run = _playStage(_starterStageOneScript(deploy: false));
      expect(run.game.snapshot.phase, GamePhase.lost);
      expect(run.game.snapshot.wavesCleared, lessThan(8));
      expect(run.evidence.spawned, greaterThan(0));
      expect(run.feedback.kills, 0);
      expect(run.feedback.leaks, greaterThan(0));
      expect(run.completions, isEmpty);
    },
  );

  group('main path — level-20 E–C squad', () {
    for (final stage in OrionCampaign.mainStages) {
      test('clears ${stage.name} (${stage.id}) through the wave-8 boss', () {
        _expectStageVictory(_playStage(_mainPathScript(stage)));
      });
    }
  });
}

/// Shared victory evidence: real spawns and combat, a real boss killed,
/// three squad-compatible drafts, no duplicate deployment, the stage
/// callback with a medal matching final base health, and a real restart
/// that accepts deployments and spawns again.
void _expectStageVictory(_RunResult run) {
  final squadStyles = run.script.squad.keys
      .map((member) => member.style)
      .toSet();
  expect(run.evidence.duplicatePlacementRejected, isTrue);
  expect(run.evidence.spawned, greaterThan(0));
  expect(run.evidence.projectilesSeen, isTrue);
  expect(run.feedback.kills, greaterThan(0));
  expect(run.evidence.drafts, hasLength(GameBalance.moduleDraftWaves.length));
  for (final draft in run.evidence.drafts) {
    expect(draft.offered, hasLength(3));
    expect(draft.offered, contains(draft.picked));
    for (final id in draft.offered) {
      final affinity = runModuleDefinition(id).tower;
      expect(
        affinity == null || squadStyles.contains(affinity),
        isTrue,
        reason:
            'off-squad module $id was offered to squad '
            '${run.script.squad.keys}',
      );
    }
  }
  expect(run.evidence.bossSeen, isTrue);
  expect(run.feedback.bossDefeatedCalls, greaterThan(0));
  expect(run.completions, hasLength(1));
  expect(run.completions.single.stage.id, run.script.stage.id);
  // Medal rule restated from the spec rather than reusing the production
  // factory: full health is gold, at least the silver threshold is
  // silver, anything less is a plain clear — so a miscalculated medal
  // fails even when a future strategy wins at reduced health.
  final expectedMedal =
      run.game.snapshot.baseHealth >= run.game.snapshot.startingBaseHealth
      ? StageMedal.gold
      : run.game.snapshot.baseHealth >= GameBalance.silverMedalThreshold
      ? StageMedal.silver
      : StageMedal.clear;
  expect(run.completions.single.result.medal, expectedMedal);
  expect(
    run.completions.single.result.bestBaseHealth,
    run.game.snapshot.baseHealth,
  );
  expect(run.game.snapshot.phase, GamePhase.won);
  expect(run.game.snapshot.wavesCleared, run.script.stage.waves.length);
  expect(
    run.game.snapshot.placedTowers,
    hasLength(run.script.deployments.length),
    reason: 'every scripted deployment must have landed',
  );
  expect(
    run.game.snapshot.placedTowers.map((tower) => tower.character).toSet(),
    hasLength(run.game.snapshot.placedTowers.length),
    reason: 'no character may be deployed twice',
  );

  run.game.restart();
  final restarted = run.game.snapshot;
  expect(restarted.phase, GamePhase.build);
  expect(restarted.gold, GameBalance.startingGold);
  expect(restarted.baseHealth, restarted.startingBaseHealth);
  expect(restarted.placedTowers, isEmpty);
  expect(restarted.wavesCleared, 0);
  final (character, cell) = run.script.deployments.first;
  _selectCell(run.game, cell);
  run.game.placeTower(character);
  expect(run.game.snapshot.placedTowers, hasLength(1));
  run.game.startWave();
  expect(run.game.snapshot.phase, GamePhase.wave);
  var sawSpawn = false;
  for (var tick = 0; tick < 300 && !sawSpawn; tick += 1) {
    run.game.update(_tickSeconds);
    sawSpawn = run.game.children.whereType<EnemyComponent>().isNotEmpty;
  }
  expect(sawSpawn, isTrue);
}

const double _tickSeconds = 1.0 / 30.0;

/// Hard bound on ticks per wave (200 game-seconds at 1/30): real waves
/// finish in ~20–60s, so exceeding this means the loop is stuck.
const int _maxWaveTicks = 6000;

/// A deterministic battle script for one stage: which squad member
/// deploys to which cell (attempted in list order each build phase while
/// gold covers the style's tier-1 cost), the fixed tier-purchase order
/// (one step per entry when the member is exactly one tier below it and
/// gold covers), the Salvage Module preference order, and the draft pool.
class _RunScript {
  const _RunScript({
    required this.stage,
    required this.squad,
    required this.deployments,
    required this.upgradePlan,
    required this.modulePriority,
    this.availableRunModules,
    this.deploy = true,
  });

  final StageDefinition stage;
  final Map<Character, int> squad;
  final List<(Character, GridPosition)> deployments;
  final List<(Character, int)> upgradePlan;
  final List<RunModuleId> modulePriority;
  final Iterable<RunModuleId>? availableRunModules;

  /// Whether the scripted deployments happen at all. The `deploy: false`
  /// variant is the no-combat negative control.
  final bool deploy;
}

/// Fresh-profile starter script: Haruto + Mio at persistent level 1.
/// Haruto on (5,5) covers the double S-bend; Mio on (4,8) back-stops the
/// exit stretch. Splash tier first for mid-game swarms; net-DPS modules
/// before raw gold.
_RunScript _starterStageOneScript({bool deploy = true}) {
  return _RunScript(
    stage: OrionCampaign.stageOne,
    squad: const {Character.haruto: 1, Character.mio: 1},
    deploy: deploy,
    deployments: const [
      (Character.haruto, GridPosition(5, 5)),
      (Character.mio, GridPosition(4, 8)),
    ],
    upgradePlan: const [
      (Character.mio, 2),
      (Character.haruto, 2),
      (Character.mio, 3),
      (Character.haruto, 3),
    ],
    modulePriority: const [
      RunModuleId.heavyCaliber,
      RunModuleId.overclockRelay,
      RunModuleId.longSight,
      RunModuleId.rocketFusing,
      RunModuleId.emergencySalvage,
    ],
  );
}

/// The moderate-progression fixture: the six lowest-rank roster members
/// (ranks E–C) at persistent level 20.
const Map<Character, int> _mainPathSquad = {
  Character.haruto: 20,
  Character.mio: 20,
  Character.sayo: 20,
  Character.tetsuo: 20,
  Character.rin: 20,
  Character.kaito: 20,
};

/// Carries' tier 2s first, then their signatures, then the supports.
const _mainPathUpgradePlan = <(Character, int)>[
  (Character.tetsuo, 2),
  (Character.sayo, 2),
  (Character.kaito, 2),
  (Character.mio, 2),
  (Character.tetsuo, 3),
  (Character.sayo, 3),
  (Character.kaito, 3),
  (Character.mio, 3),
  (Character.rin, 2),
  (Character.haruto, 2),
  (Character.rin, 3),
  (Character.haruto, 3),
];

/// Net-squad DPS first, coverage second, per-style boosts next, raw gold,
/// then the entries this squad can never use (nanite, gravity).
const _mainPathModulePriority = <RunModuleId>[
  RunModuleId.heavyCaliber,
  RunModuleId.relayCalibration,
  RunModuleId.overclockRelay,
  RunModuleId.longSight,
  RunModuleId.relayArc,
  RunModuleId.salvagedDrones,
  RunModuleId.auroraFocus,
  RunModuleId.rocketFusing,
  RunModuleId.siegeRounds,
  RunModuleId.cryoReservoir,
  RunModuleId.emergencySalvage,
  RunModuleId.foundryNanites,
  RunModuleId.gravityEcho,
];

/// The draft pool a main-path player reaching [stage] has legally earned:
/// the base pool plus the blueprint of every earlier main stage.
Iterable<RunModuleId> _modulesAvailableFor(StageDefinition stage) {
  final order = stage.mainPathOrder ?? 0;
  final earned = OrionCampaign.mainStages
      .where((s) => (s.mainPathOrder ?? 0) < order)
      .map((s) => s.blueprint)
      .whereType<RunModuleId>();
  return {...RunModuleUnlocks.baseModules, ...earned};
}

/// Per-stage deterministic deployment scripts for [_mainPathSquad]. Each
/// cell was chosen from the stage's actual path: the drone bay and
/// railgun take the prime multi-pass cells, ion chain and rocket anchor
/// bends and exits, cryo slows feed the carries, laser covers the entry.
_RunScript _mainPathScript(StageDefinition stage) {
  final deployments = switch (stage.id) {
    OrionCampaign.stageOneId => const <(Character, GridPosition)>[
      (Character.tetsuo, GridPosition(4, 3)),
      (Character.sayo, GridPosition(1, 8)),
      (Character.kaito, GridPosition(4, 7)),
      (Character.mio, GridPosition(4, 8)),
      (Character.rin, GridPosition(6, 7)),
      (Character.haruto, GridPosition(5, 5)),
    ],
    'nebula-relay' => const <(Character, GridPosition)>[
      (Character.tetsuo, GridPosition(5, 5)),
      (Character.sayo, GridPosition(5, 7)),
      (Character.kaito, GridPosition(4, 9)),
      (Character.mio, GridPosition(3, 5)),
      (Character.haruto, GridPosition(3, 3)),
      (Character.rin, GridPosition(1, 3)),
    ],
    'asteroid-foundry' => const <(Character, GridPosition)>[
      (Character.tetsuo, GridPosition(2, 3)),
      (Character.sayo, GridPosition(2, 5)),
      (Character.kaito, GridPosition(6, 7)),
      (Character.mio, GridPosition(3, 5)),
      (Character.rin, GridPosition(4, 5)),
      (Character.haruto, GridPosition(0, 1)),
    ],
    'aurora-gate' => const <(Character, GridPosition)>[
      (Character.tetsuo, GridPosition(3, 4)),
      (Character.sayo, GridPosition(4, 6)),
      (Character.kaito, GridPosition(5, 8)),
      (Character.mio, GridPosition(1, 4)),
      (Character.rin, GridPosition(3, 6)),
      (Character.haruto, GridPosition(6, 6)),
    ],
    'singularity-core' => const <(Character, GridPosition)>[
      (Character.tetsuo, GridPosition(5, 3)),
      (Character.sayo, GridPosition(6, 6)),
      (Character.kaito, GridPosition(3, 6)),
      (Character.mio, GridPosition(6, 8)),
      (Character.rin, GridPosition(4, 6)),
      (Character.haruto, GridPosition(1, 3)),
    ],
    _ => throw ArgumentError.value(stage.id, 'stage', 'no main-path script'),
  };
  return _RunScript(
    stage: stage,
    squad: _mainPathSquad,
    deployments: deployments,
    upgradePlan: _mainPathUpgradePlan,
    modulePriority: _mainPathModulePriority,
    availableRunModules: _modulesAvailableFor(stage),
  );
}

/// Deterministic offer picker: returns the first [count] session-provided
/// candidates in the order [GameSession] presents them.
final class _TakeFirstModulePicker implements ModuleOfferPicker {
  @override
  List<RunModuleId> pick(List<RunModuleId> candidates, {required int count}) {
    return List.unmodifiable(candidates.take(count));
  }
}

/// Combat evidence observed while driving the real game loop.
final class _RunEvidence {
  var spawned = 0;
  var projectilesSeen = false;
  var bossSeen = false;
  var duplicatePlacementRejected = false;
  final drafts = <({List<RunModuleId> offered, RunModuleId picked})>[];
}

final class _RunResult {
  _RunResult(
    this.game,
    this.evidence,
    this.completions,
    this.feedback,
    this.script,
  );

  final OrionDefenseGame game;
  final _RunEvidence evidence;
  final List<StageCompletion> completions;
  final _CountingFeedback feedback;
  final _RunScript script;
}

/// Turns combat feedback into evidence: kills (enemyDestroyed +
/// bossDefeated), leaks (coreHit + baseDefeated), boss lifecycle.
final class _CountingFeedback implements GameFeedback {
  var enemyDestroyedCalls = 0;
  var bossArrivedCalls = 0;
  var bossDefeatedCalls = 0;
  var coreHitCalls = 0;
  var baseDefeatedCalls = 0;

  int get kills => enemyDestroyedCalls + bossDefeatedCalls;
  int get leaks => coreHitCalls + baseDefeatedCalls;

  @override
  void enemyDestroyed() => enemyDestroyedCalls += 1;
  @override
  void bossArrived() => bossArrivedCalls += 1;
  @override
  void bossDefeated() => bossDefeatedCalls += 1;
  @override
  void coreHit() => coreHitCalls += 1;
  @override
  void baseDefeated() => baseDefeatedCalls += 1;
  @override
  void towerConfirmed() {}
  @override
  void waveCleared() {}
  @override
  void moduleSelected() {}
  @override
  void towerFired(TowerType type) {}
  @override
  void splashImpact() {}
  @override
  void chainImpact() {}
  @override
  void pierceImpact() {}
  @override
  void waveStarted() {}
  @override
  void towerSold() {}
  @override
  void missionVictory() {}
}

/// Taps a board cell through the real canvas-tap path — selecting an
/// empty cell for placement or the deployed member for upgrading.
void _selectCell(OrionDefenseGame game, GridPosition cell) {
  game.handleBoardTap(game.boardCellCenter(cell));
}

void _resolvePendingOffer(
  OrionDefenseGame game,
  _RunEvidence evidence,
  _RunScript script,
) {
  final offer = game.snapshot.pendingRunModuleOffer;
  if (offer == null) return;
  final picked = script.modulePriority.firstWhere(
    offer.moduleIds.contains,
    orElse: () => offer.moduleIds.first,
  );
  evidence.drafts.add((offered: offer.moduleIds, picked: picked));
  game.selectRunModule(offer.offerId, picked);
  expect(game.snapshot.pendingRunModuleOffer, isNull);
}

/// Buys scripted deployments in list order, then scripted tier steps in
/// priority order, each while the session's own legality and gold checks
/// allow them. Deterministic: identical state always buys the same plan.
void _applyBuildPlan(OrionDefenseGame game, _RunScript script) {
  for (final (character, cell) in script.deployments) {
    if (game.snapshot.placedTowers.any((t) => t.character == character)) {
      continue;
    }
    final cost = GameBalance.towerStats(character.style, level: 1).cost;
    if (game.snapshot.gold < cost) continue;
    _selectCell(game, cell);
    game.placeTower(character);
    expect(
      game.snapshot.placedTowers.any((t) => t.character == character),
      isTrue,
      reason:
          'scripted deployment ${character.name}@$cell must be legal '
          '(feedback: ${game.snapshot.feedback})',
    );
  }
  for (final (character, targetTier) in script.upgradePlan) {
    final tower = game.snapshot.placedTowers
        .where((t) => t.character == character)
        .firstOrNull;
    if (tower == null || tower.level != targetTier - 1) continue;
    final cost = GameBalance.towerStats(
      tower.type,
      level: tower.level,
    ).nextUpgradeCost;
    if (cost == null || game.snapshot.gold < cost) continue;
    _selectCell(game, tower.position);
    game.upgradeSelectedTower();
    final upgraded = game.snapshot.placedTowers
        .where((t) => t.character == character)
        .firstOrNull;
    expect(upgraded?.level, targetTier);
  }
}

/// First buildable, unoccupied cell on this stage's board — used for the
/// duplicate-deployment probe.
GridPosition? _freeBuildableCell(OrionDefenseGame game) {
  for (var row = 0; row < BoardLayout.rows; row++) {
    for (var column = 0; column < BoardLayout.columns; column++) {
      final cell = GridPosition(column, row);
      if (!BoardLayout.isBuildableCell(cell, pathCells: game.stage.pathCells)) {
        continue;
      }
      if (game.snapshot.placedTowers.any((t) => t.position == cell)) {
        continue;
      }
      return cell;
    }
  }
  return null;
}

/// Invariant probe: re-deploying an already-deployed member on a free
/// cell must be rejected by the session, not just by UI state. Returns
/// false until the first scripted member is deployed so the probe can be
/// retried on a later build phase.
bool _probeDuplicatePlacement(
  OrionDefenseGame game,
  _RunEvidence evidence,
  _RunScript script,
) {
  final character = script.deployments.first.$1;
  if (!game.snapshot.placedTowers.any((t) => t.character == character)) {
    return false;
  }
  final cell = _freeBuildableCell(game);
  expect(cell, isNotNull, reason: 'need a free buildable cell to probe');
  _selectCell(game, cell!);
  final placedBefore = game.snapshot.placedTowers.length;
  game.placeTower(character);
  evidence.duplicatePlacementRejected =
      game.snapshot.placedTowers.length == placedBefore &&
      game.snapshot.feedback == 'That member is already deployed.';
  return true;
}

/// Plays the real [script.stage] end to end: scripted build-phase
/// deployments and tier purchases, real `game.update(1/30)` waves,
/// deterministic drafts. Never calls force-completion APIs.
_RunResult _playStage(_RunScript script) {
  final feedback = _CountingFeedback();
  final completions = <StageCompletion>[];
  final game = OrionDefenseGame(
    stage: script.stage,
    squad: script.squad,
    availableRunModules: script.availableRunModules,
    moduleOfferPicker: _TakeFirstModulePicker(),
    onStageWon: completions.add,
    gameFeedback: feedback,
  );
  game.onGameResize(Vector2(360, 640));
  // Mounted roots enqueue component adds like production; unattached roots
  // mutate children during updateTree and throw ConcurrentModificationError.
  // ignore: invalid_use_of_internal_member
  game.setMounted();
  game.processLifecycleEvents();

  final evidence = _RunEvidence();
  var duplicateProbed = false;

  for (var guard = 0; guard < 12; guard += 1) {
    if (game.snapshot.phase != GamePhase.build) break;
    _resolvePendingOffer(game, evidence, script);
    if (script.deploy) {
      _applyBuildPlan(game, script);
      if (!duplicateProbed) {
        duplicateProbed = _probeDuplicatePlacement(game, evidence, script);
      }
    }

    final waveNumber = game.snapshot.wavesCleared + 1;
    if (waveNumber > script.stage.waves.length) break;
    game.startWave();
    expect(
      game.snapshot.phase,
      GamePhase.wave,
      reason: 'wave $waveNumber must actually start',
    );

    final seenIds = <int>{};
    var ticks = 0;
    while (game.snapshot.phase == GamePhase.wave) {
      game.update(_tickSeconds);
      ticks += 1;
      expect(
        ticks <= _maxWaveTicks,
        isTrue,
        reason:
            'wave $waveNumber exceeded $_maxWaveTicks ticks — the loop '
            'would hang',
      );
      for (final enemy in game.children.whereType<EnemyComponent>()) {
        seenIds.add(enemy.enemyId);
        if (enemy.stats is BossDefinition) evidence.bossSeen = true;
      }
      evidence.projectilesSeen |= game.children
          .whereType<ProjectileComponent>()
          .isNotEmpty;
    }
    evidence.spawned += seenIds.length;
  }

  return _RunResult(game, evidence, completions, feedback, script);
}
