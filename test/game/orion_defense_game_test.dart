import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/components/drone_component.dart';
import 'package:orion/game/components/enemy_component.dart';
import 'package:orion/game/components/gravity_field_component.dart';
import 'package:orion/game/components/projectile_component.dart';
import 'package:orion/game/components/tower_component.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/rules/board_layout.dart';
import 'package:orion/game/rules/enemy_overlay_state.dart';
import 'package:orion/game/rules/module_offer_picker.dart';

import 'game_test_fixtures.dart';

final class _FixedModuleOfferPicker implements ModuleOfferPicker {
  _FixedModuleOfferPicker(this.offers);

  final List<List<RunModuleId>> offers;
  int _index = 0;

  @override
  List<RunModuleId> pick(List<RunModuleId> candidates, {required int count}) {
    final requested = offers[_index++];
    expect(requested, hasLength(count));
    expect(requested.every(candidates.contains), isTrue);
    return List.unmodifiable(requested);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OrionDefenseGame', () {
    test('defaults to campaign stage one', () {
      final game = OrionDefenseGame();

      expect(game.stage, OrionCampaign.stageOne);
      expect(game.snapshot.stageName, 'Outpost Alpha');
    });

    test('onLoad loads all sprite sheets including the boss sheet', () async {
      final game = OrionDefenseGame();
      game.onGameResize(Vector2(800, 1200));
      await game.onLoad();

      expect(game.snapshot.phase, GamePhase.build);
      expect(game.hasLayout, isTrue);
    });

    test('can be constructed for another stage', () {
      final stage = OrionCampaign.stageById('nebula-relay');
      final game = OrionDefenseGame(stage: stage);

      expect(game.stage, stage);
      expect(game.snapshot.stageName, 'Nebula Relay');
      expect(game.snapshot.waveTotal, 8);
    });

    test('overrideFeedback republishes the active stage modifiers', () {
      final stage = OrionCampaign.stageById('singularity-core');
      final game = OrionDefenseGame(stage: stage);

      game.overrideFeedback('Modifier check');

      expect(game.snapshot.feedback, 'Modifier check');
      expect(game.snapshot.stageModifiers, stage.modifiers);
    });

    test('defaults to unpaused 1x pacing with auto-start disabled', () {
      final game = OrionDefenseGame();

      expect(game.snapshot.isPaused, isFalse);
      expect(game.snapshot.speedMultiplier, 1);
      expect(game.snapshot.autoStartEnabled, isFalse);
      expect(game.snapshot.autoStartCountdownRemaining, isNull);
      expect(game.timeScale, 1);
    });

    test('sets supported speed multipliers and ignores unsupported values', () {
      final game = OrionDefenseGame();

      game.setSpeedMultiplier(2);
      expect(game.snapshot.speedMultiplier, 2);
      expect(game.timeScale, 2);

      game.setSpeedMultiplier(3);
      expect(game.snapshot.speedMultiplier, 3);
      expect(game.timeScale, 3);

      game.setSpeedMultiplier(4);
      expect(game.snapshot.speedMultiplier, 3);
      expect(game.timeScale, 3);
    });

    test('pause freezes time scale and resume restores selected speed', () {
      final game = OrionDefenseGame();

      game.setSpeedMultiplier(3);
      game.startWave();
      game.togglePause();

      expect(game.snapshot.isPaused, isTrue);
      expect(game.timeScale, 0);

      game.togglePause();

      expect(game.snapshot.isPaused, isFalse);
      expect(game.timeScale, 3);
    });

    test(
      'toggleAutoStart updates snapshot and clears countdown when disabled',
      () {
        final game = OrionDefenseGame();

        game.toggleAutoStart();
        expect(game.snapshot.autoStartEnabled, isTrue);

        game.toggleAutoStart();
        expect(game.snapshot.autoStartEnabled, isFalse);
        expect(game.snapshot.autoStartCountdownRemaining, isNull);
      },
    );

    test('auto-start enabled before first wave does not start countdown', () {
      final game = OrionDefenseGame();

      game.toggleAutoStart();
      game.update(OrionDefenseGame.autoStartCountdownSeconds + 1);

      expect(game.snapshot.autoStartEnabled, isTrue);
      expect(game.snapshot.autoStartCountdownRemaining, isNull);
      expect(game.snapshot.phase, GamePhase.build);
      expect(game.snapshot.waveNumber, 1);
    });

    test('returnToMap fires callback during build phase', () {
      var callCount = 0;
      final game = OrionDefenseGame(onReturnToMap: () => callCount += 1);

      game.returnToMap();

      expect(callCount, 1);
    });

    test('returnToMap is blocked during an active wave', () {
      var callCount = 0;
      final game = OrionDefenseGame(onReturnToMap: () => callCount += 1);

      game.startWave();
      game.returnToMap();

      expect(callCount, 0);
      expect(
        game.snapshot.feedback,
        'Finish the active wave before returning.',
      );
    });

    test('calls onStageWon with a completion result after won snapshot', () {
      final stage = StageDefinition(
        id: 'one-wave-stage',
        name: 'One Wave Stage',
        mapLabel: 'One',
        description: 'Stage with one empty wave',
        pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
        waves: const [WaveDefinition(groups: [], clearBonus: 0)],
        unlockDependencies: const [],
        isMainPath: true,
        mainPathOrder: 1,
        mapColumn: 0,
        mapRow: 0,
      );
      final completions = <StageCompletion>[];
      final game = OrionDefenseGame(stage: stage, onStageWon: completions.add);

      game.startWave();
      game.onGameResize(Vector2(800, 1200));
      game.update(0);

      expect(game.snapshot.phase, GamePhase.won);
      expect(completions, hasLength(1));
      expect(completions.single.stage, stage);
      expect(
        completions.single.result,
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );
    });

    test(
      'wave clear starts auto-start countdown when another wave remains',
      () {
        final game = OrionDefenseGame(stage: stageWithWaveCount(2));

        game.toggleAutoStart();
        game.startWave();
        game.onGameResize(Vector2(800, 1200));
        game.update(0);

        expect(game.snapshot.phase, GamePhase.build);
        expect(game.snapshot.waveNumber, 2);
        expect(game.snapshot.autoStartEnabled, isTrue);
        expect(game.snapshot.autoStartCountdownRemaining, 3);
      },
    );

    test('auto-start toggled on after a cleared wave starts countdown', () {
      final game = OrionDefenseGame(stage: stageWithWaveCount(2));

      game.startWave();
      game.onGameResize(Vector2(800, 1200));
      game.update(0);

      expect(game.snapshot.phase, GamePhase.build);
      expect(game.snapshot.waveNumber, 2);
      expect(game.snapshot.autoStartCountdownRemaining, isNull);

      game.toggleAutoStart();

      expect(game.snapshot.autoStartEnabled, isTrue);
      expect(game.snapshot.autoStartCountdownRemaining, 3);
      expect(game.snapshot.phase, GamePhase.build);
      expect(game.snapshot.waveNumber, 2);
    });

    test('auto-start countdown can be canceled by turning auto-start off', () {
      final game = OrionDefenseGame(stage: stageWithWaveCount(2));

      game.toggleAutoStart();
      game.startWave();
      game.onGameResize(Vector2(800, 1200));
      game.update(0);
      game.toggleAutoStart();

      expect(game.snapshot.autoStartEnabled, isFalse);
      expect(game.snapshot.autoStartCountdownRemaining, isNull);
      expect(game.snapshot.phase, GamePhase.build);
    });

    test(
      'auto-start countdown starts next wave after scaled unpaused time',
      () {
        final game = OrionDefenseGame(stage: stageWithWaveCount(2));

        game.toggleAutoStart();
        game.setSpeedMultiplier(3);
        game.startWave();
        game.onGameResize(Vector2(800, 1200));
        game.update(0);

        game.update(1);

        expect(game.snapshot.phase, GamePhase.wave);
        expect(game.snapshot.waveNumber, 2);
        expect(game.snapshot.autoStartCountdownRemaining, isNull);
      },
    );

    test('paused auto-start countdown does not advance', () {
      final game = OrionDefenseGame(stage: stageWithWaveCount(2));

      game.toggleAutoStart();
      game.startWave();
      game.onGameResize(Vector2(800, 1200));
      game.update(0);
      game.togglePause();

      game.update(10);

      expect(game.snapshot.phase, GamePhase.build);
      expect(game.snapshot.isPaused, isTrue);
      expect(game.snapshot.autoStartCountdownRemaining, 3);
    });

    test('wave 2 opens a module offer and suspends auto-start pacing', () {
      final picker = _FixedModuleOfferPicker([
        const [
          RunModuleId.heavyCaliber,
          RunModuleId.overclockRelay,
          RunModuleId.longSight,
        ],
      ]);
      final game = OrionDefenseGame(
        stage: stageWithWaveCount(8),
        moduleOfferPicker: picker,
      );
      game.toggleAutoStart();
      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0);
      expect(game.snapshot.autoStartCountdownRemaining, 3);

      game.update(3); // auto-start wave 2
      expect(game.snapshot.phase, GamePhase.wave);
      game.update(0); // complete empty wave 2

      expect(game.snapshot.pendingRunModuleOffer, isNotNull);
      expect(game.snapshot.pendingRunModuleOffer!.draftNumber, 1);
      expect(game.snapshot.autoStartCountdownRemaining, isNull);
    });

    test(
      'selecting a valid module starts a fresh full auto-start countdown',
      () {
        final picker = _FixedModuleOfferPicker([
          const [
            RunModuleId.heavyCaliber,
            RunModuleId.overclockRelay,
            RunModuleId.longSight,
          ],
        ]);
        final game = OrionDefenseGame(
          stage: stageWithWaveCount(8),
          moduleOfferPicker: picker,
        );
        game.toggleAutoStart();
        game.onGameResize(Vector2(800, 1200));
        game.startWave();
        game.update(0);
        game.update(3);
        game.update(0);
        final offer = game.snapshot.pendingRunModuleOffer!;

        game.selectRunModule(offer.offerId, offer.moduleIds.first);

        expect(game.snapshot.pendingRunModuleOffer, isNull);
        expect(
          game.snapshot.autoStartCountdownRemaining,
          OrionDefenseGame.autoStartCountdownSeconds,
        );
      },
    );

    test(
      'pending module draft blocks actions and board selection feedback',
      () {
        final picker = _FixedModuleOfferPicker([
          const [
            RunModuleId.heavyCaliber,
            RunModuleId.overclockRelay,
            RunModuleId.longSight,
          ],
        ]);
        final game = OrionDefenseGame(
          stage: stageWithWaveCount(8),
          moduleOfferPicker: picker,
        );
        game.onGameResize(Vector2(800, 1200));
        _tapCell(game, const GridPosition(2, 1));
        game.placeTower(TowerType.laser);
        game.processLifecycleEvents();
        _tapCell(game, const GridPosition(2, 1));
        game.upgradeSelectedTower();

        game.startWave();
        game.update(0);
        game.startWave();
        // Tap a buildable cell during wave 2 (before it completes and opens the
        // draft) so a cell — not the tower — is selected when the draft opens.
        // Taps are blocked once the draft is pending, and startWave clears
        // selection, so this is the slot that survives into the pending draft.
        // Selecting a cell deselects the tower (selection is mutually
        // exclusive), which is required for placeTower below to reach the
        // placement-denial path rather than the no-cell early return.
        _tapCell(game, const GridPosition(3, 1));
        game.update(0);

        expect(game.snapshot.pendingRunModuleOffer, isNotNull);
        expect(game.snapshot.selectedCell, const GridPosition(3, 1));

        // placeTower while pending reaches the placement path and is denied
        // with the pendingModuleDraft placement message.
        game.placeTower(TowerType.laser);
        expect(game.snapshot.feedback, 'Choose a Salvage Module first.');

        game.startWave();
        expect(game.snapshot.feedback, 'Choose a Salvage Module first.');

        game.setTargetingMode(TowerTargetingMode.strongest);
        expect(game.snapshot.feedback, 'Choose a Salvage Module first.');

        // Tapping while pending does not change the selection: the buildable
        // cell stays selected and no tower is selected.
        _tapCell(game, const GridPosition(4, 1));
        expect(game.snapshot.selectedCell, const GridPosition(3, 1));
        expect(game.snapshot.selectedTower, isNull);
      },
    );

    test('placeTower without a selected cell reports feedback', () {
      final game = OrionDefenseGame();

      game.placeTower(TowerType.laser);

      expect(game.snapshot.feedback, 'Select a buildable cell first.');
    });

    test('upgradeSelectedTower without a selected tower reports feedback', () {
      final game = OrionDefenseGame();

      game.upgradeSelectedTower();

      expect(game.snapshot.feedback, 'Select a tower first.');
    });

    test('upgradeSelectedTower reports feedback when tower is maxed', () {
      final game = OrionDefenseGame();
      game.onGameResize(Vector2(800, 1200));
      _tapCell(game, const GridPosition(0, 0));
      game.placeTower(TowerType.laser);
      game.processLifecycleEvents();
      _tapCell(game, const GridPosition(0, 0));
      game.upgradeSelectedTower();

      game.upgradeSelectedTower();

      expect(
        game.snapshot.feedback,
        'Choose a specialization or use a maxed tower.',
      );
    });

    test(
      'specializeSelectedTower without a selected tower reports feedback',
      () {
        final game = OrionDefenseGame();

        game.specializeSelectedTower(TowerSpecialization.prismLaser);

        expect(game.snapshot.feedback, 'Select a tower first.');
      },
    );

    test(
      'specializeSelectedTower reports feedback when tower is not upgraded',
      () {
        final game = OrionDefenseGame();
        game.onGameResize(Vector2(800, 1200));
        _tapCell(game, const GridPosition(0, 0));
        game.placeTower(TowerType.laser);
        game.processLifecycleEvents();
        _tapCell(game, const GridPosition(0, 0));

        game.specializeSelectedTower(TowerSpecialization.prismLaser);

        expect(
          game.snapshot.feedback,
          'Upgrade this tower before specializing.',
        );
      },
    );

    test(
      'update during a pending draft clears any stale auto-start countdown',
      () {
        final picker = _FixedModuleOfferPicker([
          const [
            RunModuleId.heavyCaliber,
            RunModuleId.overclockRelay,
            RunModuleId.longSight,
          ],
        ]);
        final game = OrionDefenseGame(
          stage: stageWithWaveCount(8),
          moduleOfferPicker: picker,
        );
        game.onGameResize(Vector2(800, 1200));
        game.startWave();
        game.update(0); // wave 1
        game.startWave();
        game.update(0); // wave 2 opens draft
        expect(game.snapshot.pendingRunModuleOffer, isNotNull);

        game.update(0.1);

        expect(game.snapshot.pendingRunModuleOffer, isNotNull);
      },
    );

    test(
      'module selection refreshes existing and newly placed tower stats',
      () {
        final picker = _FixedModuleOfferPicker([
          const [
            RunModuleId.heavyCaliber,
            RunModuleId.overclockRelay,
            RunModuleId.longSight,
          ],
        ]);
        final game = OrionDefenseGame(
          stage: stageWithWaveCount(8),
          moduleOfferPicker: picker,
        );
        game.onGameResize(Vector2(800, 1200));
        _tapCell(game, const GridPosition(0, 1));
        game.placeTower(TowerType.laser);
        game.processLifecycleEvents();
        final initialComponent = game.children
            .whereType<TowerComponent>()
            .single;
        final base = GameBalance.towerStats(TowerType.laser, level: 1);
        expect(initialComponent.stats.damage, base.damage);

        game.startWave();
        game.update(0); // wave 1
        game.startWave();
        game.update(0); // wave 2 opens draft 1
        final offer = game.snapshot.pendingRunModuleOffer!;
        game.selectRunModule(offer.offerId, RunModuleId.heavyCaliber);

        final heavy = runModuleDefinition(RunModuleId.heavyCaliber);
        expect(
          initialComponent.stats.damage,
          closeTo(base.damage * heavy.damageMultiplier, 1e-9),
        );
        expect(
          initialComponent.stats.fireInterval,
          closeTo(base.fireInterval * heavy.fireIntervalMultiplier, 1e-9),
        );

        _tapCell(game, const GridPosition(2, 1));
        game.placeTower(TowerType.laser);
        game.processLifecycleEvents();
        final components = game.children.whereType<TowerComponent>().toList();
        expect(components, hasLength(2));
        expect(components[1].stats.damage, initialComponent.stats.damage);
        expect(
          components[1].stats.fireInterval,
          initialComponent.stats.fireInterval,
        );
      },
    );

    test('Drone Bay applies Heavy Caliber and Overclock to drone channels', () {
      final picker = _FixedModuleOfferPicker([
        const [
          RunModuleId.heavyCaliber,
          RunModuleId.overclockRelay,
          RunModuleId.longSight,
        ],
        const [
          RunModuleId.overclockRelay,
          RunModuleId.longSight,
          RunModuleId.emergencySalvage,
        ],
      ]);
      final game = OrionDefenseGame(
        stage: stageWithWaveCount(8),
        moduleOfferPicker: picker,
      );
      game.onGameResize(Vector2(800, 1200));

      game.startWave();
      game.update(0); // wave 1
      game.startWave();
      game.update(0); // wave 2, draft 1
      var offer = game.snapshot.pendingRunModuleOffer!;
      game.selectRunModule(offer.offerId, RunModuleId.heavyCaliber);
      game.startWave();
      game.update(0); // wave 3
      game.startWave();
      game.update(0); // wave 4, draft 2
      offer = game.snapshot.pendingRunModuleOffer!;
      game.selectRunModule(offer.offerId, RunModuleId.overclockRelay);
      game.startWave();
      game.update(0); // wave 5 unlocks Drone Bay for the next build phase

      _tapCell(game, const GridPosition(2, 1));
      game.placeTower(TowerType.droneBay);
      game.processLifecycleEvents();
      final component = game.children.whereType<TowerComponent>().single;
      final base = GameBalance.towerStats(TowerType.droneBay, level: 1);
      final heavy = runModuleDefinition(RunModuleId.heavyCaliber);
      final overclock = runModuleDefinition(RunModuleId.overclockRelay);
      expect(
        component.stats.droneDamage,
        closeTo(
          base.droneDamage *
              heavy.damageMultiplier *
              overclock.damageMultiplier,
          1e-9,
        ),
      );
      expect(
        component.stats.fireInterval,
        closeTo(
          base.fireInterval *
              heavy.fireIntervalMultiplier *
              overclock.fireIntervalMultiplier,
          1e-9,
        ),
      );
      expect(component.stats.damage, 0);
    });

    test(
      'module selection refreshes a surviving drone without resetting its state',
      () {
        final picker = _FixedModuleOfferPicker([
          const [
            RunModuleId.heavyCaliber,
            RunModuleId.overclockRelay,
            RunModuleId.longSight,
          ],
          const [
            RunModuleId.heavyCaliber,
            RunModuleId.overclockRelay,
            RunModuleId.emergencySalvage,
          ],
          const [
            RunModuleId.heavyCaliber,
            RunModuleId.overclockRelay,
            RunModuleId.cryoReservoir,
          ],
        ]);
        final game = OrionDefenseGame(
          stage: _droneBayModuleRefreshStage(),
          moduleOfferPicker: picker,
        );
        game.onGameResize(Vector2(800, 1200));

        // Clear waves 1-2 and choose Long Sight from draft 1.
        game.startWave();
        game.update(0);
        game.startWave();
        game.update(0);
        var offer = game.snapshot.pendingRunModuleOffer!;
        game.selectRunModule(offer.offerId, RunModuleId.longSight);

        // Clear waves 3-4 and choose Emergency Salvage from draft 2.
        game.startWave();
        game.update(0);
        game.startWave();
        game.update(0);
        offer = game.snapshot.pendingRunModuleOffer!;
        game.selectRunModule(offer.offerId, RunModuleId.emergencySalvage);

        // Drone Bay unlocks for wave 6 after wave 5 is cleared.
        game.startWave();
        game.update(0);
        _tapCell(game, const GridPosition(0, 1));
        game.placeTower(TowerType.droneBay);
        game.processLifecycleEvents();

        game.startWave();
        game.update(0.01); // spawn wave 6's durable enemy
        game.processLifecycleEvents();
        game.children.whereType<TowerComponent>().single.update(0.01);
        game.processLifecycleEvents();
        final drone = game.children.whereType<DroneComponent>().first;

        // Put the drone on a live attack cooldown and consume some lifetime
        // before wave 6 is cleared.
        drone.update(0.5);

        game.children.whereType<EnemyComponent>().single.applyDamage(1000000);
        game.update(0.01); // clear wave 6 and open draft 3
        game.processLifecycleEvents();
        offer = game.snapshot.pendingRunModuleOffer!;

        game.selectRunModule(offer.offerId, RunModuleId.heavyCaliber);
        final heavy = runModuleDefinition(RunModuleId.heavyCaliber);
        final base = GameBalance.towerStats(TowerType.droneBay, level: 1);
        expect(drone.parent, same(game));
        expect(
          drone.stats.droneDamage,
          closeTo(base.droneDamage * heavy.damageMultiplier, 1e-9),
        );

        // The same drone survives into wave 7 and applies its refreshed
        // damage only after the pre-selection cooldown has elapsed.
        game.startWave();
        game.update(0.01);
        game.processLifecycleEvents();
        final enemy = game.children.whereType<EnemyComponent>().single;
        final healthBeforeAttack = enemy.health;
        // The pre-selection cooldown is still active: a refresh that resets
        // it would damage the new wave's enemy immediately.
        drone.update(0.1);
        expect(enemy.health, healthBeforeAttack);
        drone.update(base.droneAttackInterval);
        expect(
          enemy.health,
          closeTo(
            healthBeforeAttack - base.droneDamage * heavy.damageMultiplier,
            1e-9,
          ),
        );

        // The elapsed pre-selection lifetime is preserved too: this duration
        // is longer than the remaining lifetime but shorter than a reset one.
        drone.update(base.droneLifetime * 0.8);
        expect(drone.parent, isNull);
      },
    );

    test(
      'module selection refreshes a lingering gravity field without resetting its state',
      () {
        final picker = _FixedModuleOfferPicker([
          const [
            RunModuleId.heavyCaliber,
            RunModuleId.overclockRelay,
            RunModuleId.longSight,
          ],
          const [
            RunModuleId.heavyCaliber,
            RunModuleId.overclockRelay,
            RunModuleId.emergencySalvage,
          ],
          const [
            RunModuleId.heavyCaliber,
            RunModuleId.overclockRelay,
            RunModuleId.cryoReservoir,
          ],
        ]);
        final game = OrionDefenseGame(
          stage: _gravityWellModuleRefreshStage(),
          moduleOfferPicker: picker,
        );
        game.onGameResize(Vector2(800, 1200));

        // Clear waves 1-2 and choose Long Sight from draft 1.
        game.startWave();
        game.update(0);
        game.startWave();
        game.update(0);
        var offer = game.snapshot.pendingRunModuleOffer!;
        game.selectRunModule(offer.offerId, RunModuleId.longSight);

        // Clear waves 3-4 and choose Emergency Salvage from draft 2.
        game.startWave();
        game.update(0);
        game.startWave();
        game.update(0);
        offer = game.snapshot.pendingRunModuleOffer!;
        game.selectRunModule(offer.offerId, RunModuleId.emergencySalvage);

        // Gravity Well unlocks at wave 5. Place it, then clear the empty
        // wave 5 so wave 6 (which opens draft 3 on clear) is next.
        expect(
          game.snapshot.unlockedTowerTypes,
          contains(TowerType.gravityWell),
        );
        _tapCell(game, const GridPosition(0, 1));
        game.placeTower(TowerType.gravityWell);
        game.processLifecycleEvents();
        game.startWave(); // wave 5: empty
        game.update(0);
        game.processLifecycleEvents();

        // Wave 6: spawn the durable enemy and fire the gravity well so a
        // field is created. Firing via the tower's own update() avoids a
        // concurrent-modification error in unmounted unit tests.
        game.startWave();
        game.update(0.01);
        game.processLifecycleEvents();
        game.children.whereType<TowerComponent>().single.update(0.01);
        game.processLifecycleEvents();
        final field = game.children.whereType<GravityFieldComponent>().single;
        expect(field.parent, same(game));

        // Consume some field duration and establish a live tick cooldown
        // before wave 6 is cleared. The first update ticks immediately
        // (tickRemaining starts at 0); 0.5s leaves ~0.0s of the next tick
        // interval and ~1.5s of remaining duration.
        field.update(0.5);

        // Clear wave 6 by resolving the enemy; the field lingers because
        // its fieldDuration (2.0s) has not elapsed. Draft 3 opens.
        game.children.whereType<EnemyComponent>().single.applyDamage(1000000);
        game.update(0.01);
        game.processLifecycleEvents();
        expect(game.snapshot.phase, GamePhase.build);
        offer = game.snapshot.pendingRunModuleOffer!;
        expect(field.parent, same(game)); // lingers into the draft

        // Select Heavy Caliber, which raises damage by 20%. The lingering
        // field must pick up the refreshed stats; without a refresh it would
        // keep dealing the pre-module base damage.
        game.selectRunModule(offer.offerId, RunModuleId.heavyCaliber);
        game.processLifecycleEvents();
        final heavy = runModuleDefinition(RunModuleId.heavyCaliber);
        final base = GameBalance.towerStats(TowerType.gravityWell, level: 1);
        expect(
          field.stats.damage,
          closeTo(base.damage * heavy.damageMultiplier, 1e-9),
        );

        // Start wave 7 and spawn its enemy at the same path start the field
        // is centered on. The preserved tick cooldown means a short update
        // does not damage the new enemy yet.
        game.startWave();
        game.update(0.01);
        game.processLifecycleEvents();
        final wave7Enemy = game.children.whereType<EnemyComponent>().single;
        final healthBeforeTick = wave7Enemy.health;
        field.update(0.1);
        expect(wave7Enemy.health, healthBeforeTick); // cooldown preserved

        // After the remaining tick cooldown elapses, the field deals the
        // refreshed (Heavy Caliber) damage.
        field.update(base.fieldTickInterval);
        expect(
          wave7Enemy.health,
          closeTo(
            healthBeforeTick - base.damage * heavy.damageMultiplier,
            1e-9,
          ),
        );

        // The pre-selection duration is preserved too: this duration is
        // longer than the remaining lifetime but shorter than a reset one.
        field.update(base.fieldDuration);
        expect(field.parent, isNull);
      },
    );

    test(
      'TowerComponent.updateTower resolves through its provider callback',
      () {
        var resolveCalls = 0;
        TowerStats resolve(PlacedTower tower) {
          resolveCalls += 1;
          return GameBalance.towerStats(tower.type, level: tower.level);
        }

        final tower = PlacedTower(
          id: 1,
          type: TowerType.laser,
          position: const GridPosition(0, 0),
        );
        final component = TowerComponent(
          tower: tower,
          center: Vector2.zero(),
          resolveStats: resolve,
          acquireTarget: (_) => null,
          launchProjectile: (_, _) {},
        );
        expect(resolveCalls, 1);
        expect(component.stats.level, 1);

        component.updateTower(tower.upgraded());

        expect(resolveCalls, 2);
        expect(component.stats.level, 2);
      },
    );

    test('paused active-wave update does not run combat components', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());

      game.onGameResize(Vector2(800, 1200));
      _tapCell(game, const GridPosition(0, 1));
      game.placeTower(TowerType.laser);
      game.processLifecycleEvents();
      game.startWave();
      game.update(0.01);
      game.processLifecycleEvents();

      expect(game.children.whereType<ProjectileComponent>(), isEmpty);
      game.togglePause();

      expect(() {
        game.update(1);
        game.update(1);
        game.update(1);
        game.processLifecycleEvents();
      }, returnsNormally);

      expect(game.snapshot.phase, GamePhase.wave);
      expect(game.snapshot.isPaused, isTrue);
      expect(game.children.whereType<ProjectileComponent>(), isEmpty);
    });

    test('paused wave freezes enemy movement and spawn timer', () {
      final game = OrionDefenseGame(stage: _twoEnemyDelayedSpawnStage());

      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.01);
      game.processLifecycleEvents();

      final enemy = game.children.whereType<EnemyComponent>().single;
      final position = enemy.position.clone();
      final pathProgress = enemy.pathProgress;

      game.togglePause();
      game.update(10);
      game.processLifecycleEvents();

      expect(game.children.whereType<EnemyComponent>(), hasLength(1));
      expect(enemy.position, position);
      expect(enemy.pathProgress, pathProgress);
      expect(game.snapshot.phase, GamePhase.wave);
      expect(game.snapshot.isPaused, isTrue);
    });

    test('tapping an active enemy marks it inspected', () {
      final game = OrionDefenseGame(stage: _twoEnemyImmediateSpawnStage());

      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.05);
      game.processLifecycleEvents();

      final enemies = game.children.whereType<EnemyComponent>().toList();
      expect(enemies, hasLength(2));
      enemies[0].position = Vector2(120, 200);
      enemies[1].position = Vector2(420, 200);

      _tapPoint(game, enemies[0].position);

      expect(game.inspectedEnemyId, enemies[0].enemyId);
      expect(enemies[0].isInspected, isTrue);
      expect(enemies[1].isInspected, isFalse);
      expect(enemies[0].overlayState.isExpanded, isTrue);
    });

    test('tapping another active enemy switches inspection', () {
      final game = OrionDefenseGame(stage: _twoEnemyImmediateSpawnStage());

      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.05);
      game.processLifecycleEvents();

      final enemies = game.children.whereType<EnemyComponent>().toList();
      enemies[0].position = Vector2(120, 200);
      enemies[1].position = Vector2(420, 200);

      _tapPoint(game, enemies[0].position);
      _tapPoint(game, enemies[1].position);

      expect(game.inspectedEnemyId, enemies[1].enemyId);
      expect(enemies[0].isInspected, isFalse);
      expect(enemies[1].isInspected, isTrue);
    });

    test('tapping away from enemies clears inspection', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());

      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.01);
      game.processLifecycleEvents();

      final enemy = game.children.whereType<EnemyComponent>().single;
      enemy.position = Vector2(120, 200);

      _tapPoint(game, enemy.position);
      _tapPoint(game, Vector2(700, 1100));

      expect(game.inspectedEnemyId, isNull);
      expect(enemy.isInspected, isFalse);
    });

    test('resolving the inspected enemy clears inspection', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());

      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.01);
      game.processLifecycleEvents();

      final enemy = game.children.whereType<EnemyComponent>().single;
      enemy.position = Vector2(120, 200);
      _tapPoint(game, enemy.position);

      enemy.applyDamage(1000);
      game.processLifecycleEvents();

      expect(game.inspectedEnemyId, isNull);
      expect(enemy.isResolved, isTrue);
    });

    test('inspected enemy reaching the base clears inspection', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());

      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.01);
      game.processLifecycleEvents();

      final enemy = game.children.whereType<EnemyComponent>().single;
      _tapPoint(game, enemy.position);

      expect(game.inspectedEnemyId, enemy.enemyId);

      game.update(100);
      game.processLifecycleEvents();

      expect(game.inspectedEnemyId, isNull);
      expect(enemy.isResolved, isTrue);
    });

    test('3x speed accelerates real enemy progress compared with 1x', () {
      final oneXGame = OrionDefenseGame(stage: _singleEnemyStage());
      final threeXGame = OrionDefenseGame(stage: _singleEnemyStage());

      oneXGame.setSpeedMultiplier(1);
      threeXGame.setSpeedMultiplier(3);
      oneXGame.onGameResize(Vector2(800, 1200));
      threeXGame.onGameResize(Vector2(800, 1200));
      oneXGame.startWave();
      threeXGame.startWave();
      oneXGame.update(0.01);
      threeXGame.update(0.01);
      oneXGame.processLifecycleEvents();
      threeXGame.processLifecycleEvents();

      oneXGame.update(0.5);
      threeXGame.update(0.5);

      final oneXProgress = oneXGame.children
          .whereType<EnemyComponent>()
          .single
          .pathProgress;
      final threeXProgress = threeXGame.children
          .whereType<EnemyComponent>()
          .single
          .pathProgress;

      expect(threeXProgress, greaterThan(oneXProgress));
      expect(threeXProgress, closeTo(oneXProgress * 3, 0.001));
    });

    test('normal enemy receives selected stage profile', () {
      final game = OrionDefenseGame(
        stage: _modifierStage(
          modifiers: const [StageModifier.enemySpeedSurge],
          enemyStats: const EnemyStats(
            health: 100,
            speed: 10,
            baseDamage: 1,
            goldReward: 1,
          ),
        ),
      );
      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(double.minPositive);

      final enemy = game.children.whereType<EnemyComponent>().single;
      expect(enemy.logic.modifierProfile.speedMultiplier, 1.15);
    });

    test('enemy speed surge composes with the player 3x time scale', () {
      final game = OrionDefenseGame(
        stage: _modifierStage(
          modifiers: const [StageModifier.enemySpeedSurge],
          enemyStats: const EnemyStats(
            health: 100,
            speed: 10,
            baseDamage: 1,
            goldReward: 1,
          ),
        ),
      );
      game.onGameResize(Vector2(800, 1200));
      game.setSpeedMultiplier(3);
      game.startWave();
      game.update(double.minPositive);
      game.update(1);

      final enemy = game.children.whereType<EnemyComponent>().single;
      expect(enemy.pathProgress, closeTo(34.5, 0.001));
    });

    test('swarm kill callback awards rounded stage bounty', () {
      final game = OrionDefenseGame(
        stage: _modifierStage(
          modifiers: const [StageModifier.swarmBounty],
          enemyStats: const EnemyStats(
            health: 10,
            speed: 1,
            baseDamage: 1,
            goldReward: 5,
            traits: {EnemyTrait.swarm},
          ),
        ),
      );
      final startingGold = game.snapshot.gold;
      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(double.minPositive);
      game.children.whereType<EnemyComponent>().single.applyDamage(999);

      expect(game.snapshot.gold, startingGold + 8);
    });

    test('regen pressure pulses spawn at the accepted six-enemy cadence', () {
      const regen = EnemyStats(
        health: 1000,
        speed: 0,
        baseDamage: 1,
        goldReward: 1,
        traits: {EnemyTrait.regen},
      );
      final game = OrionDefenseGame(
        stage: _modifierStage(
          modifiers: const [StageModifier.regenPressurePulses],
          enemyStats: regen,
          enemyCount: 6,
        ),
      );
      game.onGameResize(Vector2(800, 1200));
      game.startWave();

      game.update(double.minPositive);
      expect(game.children.whereType<EnemyComponent>(), hasLength(1));
      game.update(0.201);
      expect(game.children.whereType<EnemyComponent>(), hasLength(2));
      game.update(0.201);
      expect(game.children.whereType<EnemyComponent>(), hasLength(3));
      game.update(1.997);
      expect(game.children.whereType<EnemyComponent>(), hasLength(3));
      game.update(0.002);
      expect(game.children.whereType<EnemyComponent>(), hasLength(4));
      game.update(0.201);
      expect(game.children.whereType<EnemyComponent>(), hasLength(5));
      game.update(0.201);
      expect(game.children.whereType<EnemyComponent>(), hasLength(6));
    });

    test('large dt crosses intra-burst intervals and one pulse gap', () {
      const regen = EnemyStats(
        health: 1000,
        speed: 0,
        baseDamage: 1,
        goldReward: 1,
        traits: {EnemyTrait.regen},
      );
      final game = OrionDefenseGame(
        stage: _modifierStage(
          modifiers: const [StageModifier.regenPressurePulses],
          enemyStats: regen,
          enemyCount: 6,
        ),
      );
      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(double.minPositive);
      game.update(2.601);

      expect(game.children.whereType<EnemyComponent>(), hasLength(5));
    });

    test('non-regen groups retain their base interval', () {
      const normal = EnemyStats(
        health: 1000,
        speed: 0,
        baseDamage: 1,
        goldReward: 1,
      );
      final game = OrionDefenseGame(
        stage: _modifierStage(
          modifiers: const [StageModifier.regenPressurePulses],
          enemyStats: normal,
          enemyCount: 2,
          spawnInterval: 1,
        ),
      );
      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(double.minPositive);
      game.update(0.5);
      expect(game.children.whereType<EnemyComponent>(), hasLength(1));
      game.update(0.501);
      expect(game.children.whereType<EnemyComponent>(), hasLength(2));
    });

    test('summoned minions inherit the synthetic stage profile', () {
      const minion = EnemyStats(
        health: 100,
        speed: 1,
        baseDamage: 1,
        goldReward: 1,
      );
      const boss = BossDefinition(
        health: 1000,
        speed: 0,
        baseDamage: 1,
        goldReward: 1,
        sprite: BossSprite.relayBreaker,
        name: 'Synthetic Summoner',
        summonMechanic: SummonMechanic(
          interval: 100,
          firstDelay: 0.1,
          count: 1,
          maxActive: 1,
          minionStats: minion,
        ),
      );
      final game = OrionDefenseGame(
        stage: _modifierStage(
          modifiers: const [StageModifier.enemySpeedSurge],
          enemyStats: boss,
        ),
      );
      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(double.minPositive);
      game.update(0.101);
      game.update(0);

      final minionComponent = game.children
          .whereType<EnemyComponent>()
          .singleWhere((enemy) => enemy.minionOf != null);
      expect(minionComponent.logic.modifierProfile.speedMultiplier, 1.15);
    });

    test('Outpost Alpha keeps identity enemy profile', () {
      final game = OrionDefenseGame(stage: OrionCampaign.stageOne);
      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(double.minPositive);

      final enemy = game.children.whereType<EnemyComponent>().single;
      expect(enemy.logic.modifierProfile.speedMultiplier, 1);
      expect(enemy.logic.modifierProfile.armorReductionBonus, 0);
      expect(enemy.logic.modifierProfile.shieldRecharge, isNull);
    });

    test(
      'shieldRecharge stage modifier recharges a damaged shield via game.update',
      () {
        // End-to-end coverage for the StageDefinition -> OrionDefenseGame ->
        // EnemyModifierProfile -> EnemyLogic.tick shield-recharge bridge.
        // The pure EnemyLogic tests cover the arithmetic; this test guards the
        // wiring through the game's update loop.
        const enemyStats = EnemyStats(
          health: 100,
          speed: 0, // stationary so the enemy survives past the recharge delay
          baseDamage: 1,
          goldReward: 1,
          shieldHealth: 200,
          traits: {EnemyTrait.shielded},
        );
        final game = OrionDefenseGame(
          stage: _modifierStage(
            modifiers: const [StageModifier.shieldRecharge],
            enemyStats: enemyStats,
          ),
        );
        game.onGameResize(Vector2(800, 1200));
        game.startWave();
        game.update(double.minPositive);

        final enemy = game.children.whereType<EnemyComponent>().single;
        expect(enemy.logic.modifierProfile.shieldRecharge?.delay, 3);
        expect(enemy.logic.modifierProfile.shieldRecharge?.ratePerSecond, 0.10);
        expect(enemy.shield, 200);

        // Damage the shield; the recharge delay restarts from zero.
        enemy.applyDamage(100);
        expect(enemy.shield, 100);

        // Advancing within the delay must not recharge.
        game.update(2.9);
        expect(enemy.shield, 100);

        // Crossing the delay boundary recharges the shield for the overshoot.
        // 200 max * 0.10/s * 1.0s of overshoot = 20.
        game.update(1.1);
        expect(enemy.shield, 120);
      },
    );

    for (final firstGroupCount in [1, 3]) {
      test(
        'next-group initialDelay wins after $firstGroupCount regen enemies',
        () {
          const regen = EnemyStats(
            health: 1000,
            speed: 0,
            baseDamage: 1,
            goldReward: 1,
            traits: {EnemyTrait.regen},
          );
          const normal = EnemyStats(
            health: 1000,
            speed: 0,
            baseDamage: 1,
            goldReward: 1,
          );
          final stage = StageDefinition(
            id: 'group-transition',
            name: 'Group Transition',
            mapLabel: 'Transition',
            description: 'Synthetic group transition stage',
            pathCells: const [
              GridPosition(0, 0),
              GridPosition(1, 0),
              GridPosition(2, 0),
            ],
            waves: [
              WaveDefinition(
                groups: [
                  WaveGroup(
                    enemyCount: firstGroupCount,
                    enemyStats: regen,
                    spawnInterval: 1,
                  ),
                  const WaveGroup(
                    enemyCount: 1,
                    enemyStats: normal,
                    initialDelay: 5,
                  ),
                ],
                clearBonus: 0,
              ),
            ],
            modifiers: const [StageModifier.regenPressurePulses],
            mapColumn: 0,
            mapRow: 0,
          );
          final game = OrionDefenseGame(stage: stage);
          game.onGameResize(Vector2(800, 1200));
          game.startWave();
          game.update(double.minPositive);
          if (firstGroupCount == 3) {
            game.update(0.201);
            game.update(0.201);
          }

          expect(
            game.children.whereType<EnemyComponent>(),
            hasLength(firstGroupCount),
          );
          game.update(4.996);
          expect(
            game.children.whereType<EnemyComponent>(),
            hasLength(firstGroupCount),
          );
          game.update(0.005);
          expect(
            game.children.whereType<EnemyComponent>(),
            hasLength(firstGroupCount + 1),
          );
        },
      );
    }

    test('restart resets pacing state', () {
      final game = OrionDefenseGame(stage: stageWithWaveCount(2));

      game.toggleAutoStart();
      game.setSpeedMultiplier(3);
      game.startWave();
      game.togglePause();

      game.restart();

      expect(game.snapshot.phase, GamePhase.build);
      expect(game.snapshot.isPaused, isFalse);
      expect(game.snapshot.speedMultiplier, 1);
      expect(game.snapshot.autoStartEnabled, isFalse);
      expect(game.snapshot.autoStartCountdownRemaining, isNull);
      expect(game.timeScale, 1);
    });

    test('won state resets pacing state', () {
      final game = OrionDefenseGame(stage: stageWithWaveCount(1));

      game.toggleAutoStart();
      game.setSpeedMultiplier(3);
      game.startWave();
      game.onGameResize(Vector2(800, 1200));
      game.update(0);

      expect(game.snapshot.phase, GamePhase.won);
      expect(game.snapshot.isPaused, isFalse);
      expect(game.snapshot.speedMultiplier, 1);
      expect(game.snapshot.autoStartEnabled, isFalse);
      expect(game.snapshot.autoStartCountdownRemaining, isNull);
      expect(game.timeScale, 1);
    });

    test('lost state resets pacing state', () {
      final game = OrionDefenseGame(stage: _lethalSingleEnemyStage());

      game.toggleAutoStart();
      game.setSpeedMultiplier(3);
      game.startWave();
      game.onGameResize(Vector2(800, 1200));
      game.update(0.01);

      game.update(1);
      game.processLifecycleEvents();

      expect(game.snapshot.phase, GamePhase.lost);
      expect(game.snapshot.isPaused, isFalse);
      expect(game.snapshot.speedMultiplier, 1);
      expect(game.snapshot.autoStartEnabled, isFalse);
      expect(game.snapshot.autoStartCountdownRemaining, isNull);
      expect(game.timeScale, 1);
    });

    test('setTargetingMode without a selected tower reports feedback', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());
      game.onGameResize(Vector2(800, 1200));

      game.setTargetingMode(TowerTargetingMode.strongest);

      expect(game.snapshot.feedback, 'Select a tower first.');
      expect(game.snapshot.selectedTower, isNull);
    });

    test('setTargetingMode updates the selected tower during build phase', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());
      game.onGameResize(Vector2(800, 1200));
      _tapCell(game, const GridPosition(0, 1));
      game.placeTower(TowerType.laser);
      game.processLifecycleEvents();

      // Re-tap the placed tower's cell to select it.
      _tapCell(game, const GridPosition(0, 1));
      game.processLifecycleEvents();

      final tower = game.snapshot.selectedTower;
      expect(tower, isNotNull);
      expect(tower!.targetingMode, TowerTargetingMode.first);

      game.setTargetingMode(TowerTargetingMode.strongest);

      expect(
        game.snapshot.selectedTower!.targetingMode,
        TowerTargetingMode.strongest,
      );
      expect(game.snapshot.feedback, isNull);
    });

    test('setTargetingMode is denied during an active wave', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());
      game.onGameResize(Vector2(800, 1200));
      _tapCell(game, const GridPosition(0, 1));
      game.placeTower(TowerType.laser);
      game.processLifecycleEvents();
      game.startWave();

      // startWave clears the selection; re-select the tower during the wave.
      _tapCell(game, const GridPosition(0, 1));
      game.processLifecycleEvents();
      expect(game.snapshot.selectedTower, isNotNull);

      game.setTargetingMode(TowerTargetingMode.strongest);

      expect(game.snapshot.phase, GamePhase.wave);
      expect(
        game.snapshot.feedback,
        'Targeting can only change during build phase.',
      );
      // Mode is unchanged.
      expect(
        game.snapshot.selectedTower!.targetingMode,
        TowerTargetingMode.first,
      );
    });

    test(
      'sellSelectedTower removes the component, clears selection, refunds',
      () {
        final game = OrionDefenseGame(stage: _singleEnemyStage());
        game.onGameResize(Vector2(800, 1200));
        _tapCell(game, const GridPosition(0, 1));
        game.placeTower(TowerType.laser);
        game.processLifecycleEvents();
        _tapCell(game, const GridPosition(0, 1)); // select the placed tower
        game.processLifecycleEvents();
        expect(game.snapshot.selectedTower, isNotNull);
        expect(game.children.whereType<TowerComponent>(), hasLength(1));

        game.sellSelectedTower();
        game.processLifecycleEvents();

        expect(game.children.whereType<TowerComponent>(), isEmpty);
        expect(game.snapshot.selectedTower, isNull);
        expect(game.snapshot.feedback, 'Sold for 35 gold.');
        expect(game.snapshot.gold, GameBalance.startingGold - 50 + 35);
      },
    );

    test('sellSelectedTower with no selection reports feedback', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());
      game.onGameResize(Vector2(800, 1200));

      game.sellSelectedTower();

      expect(game.snapshot.feedback, 'Select a tower first.');
    });

    test('sellSelectedTower is denied during an active wave', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());
      game.onGameResize(Vector2(800, 1200));
      _tapCell(game, const GridPosition(0, 1));
      game.placeTower(TowerType.laser);
      game.processLifecycleEvents();
      game.startWave();
      _tapCell(game, const GridPosition(0, 1)); // re-select during wave
      game.processLifecycleEvents();
      expect(game.snapshot.selectedTower, isNotNull);

      game.sellSelectedTower();
      game.processLifecycleEvents();

      expect(game.snapshot.feedback, 'Sell towers between waves.');
      expect(game.children.whereType<TowerComponent>(), hasLength(1));
    });

    test('sellSelectedTower despawns a sold drone bay live drones', () {
      final game = OrionDefenseGame(stage: _droneBayUnlockStage());
      game.onGameResize(Vector2(800, 1200));

      // Advance 5 empty waves so the drone bay (unlocks at wave 6) is available.
      for (var wave = 0; wave < 5; wave += 1) {
        game.startWave();
        game.update(0);
        game.processLifecycleEvents();
        _selectPendingModuleIfNeeded(game);
      }
      expect(game.snapshot.phase, GamePhase.build);
      expect(game.snapshot.unlockedTowerTypes, contains(TowerType.droneBay));

      // Place the drone bay adjacent to the wave-6 path and run that wave.
      _tapCell(game, const GridPosition(0, 1));
      game.placeTower(TowerType.droneBay);
      game.processLifecycleEvents();
      expect(game.children.whereType<TowerComponent>(), hasLength(1));

      game.startWave(); // wave 6: one durable enemy
      game.update(0.01); // spawn the enemy
      game.processLifecycleEvents();
      // The game is not mounted in unit tests, so add() during updateTree
      // iteration modifies the children set directly instead of queueing,
      // which throws a concurrent-modification error when the drone bay fires
      // inside game.update(). Firing the tower via its own update() (outside
      // the iteration) launches the drones safely; the end state matches the
      // real mounted-game behavior.
      game.children.whereType<TowerComponent>().single.update(0.01);
      game.processLifecycleEvents();

      final dronesBefore = game.children.whereType<DroneComponent>().toList();
      expect(dronesBefore, isNotEmpty); // guards against a vacuous pass

      // End the wave (sell is build-phase only) by resolving the enemy.
      final enemy = game.children.whereType<EnemyComponent>().single;
      enemy.applyDamage(10000);
      game.update(0.01);
      game.processLifecycleEvents();
      expect(game.snapshot.phase, GamePhase.build);
      _selectPendingModuleIfNeeded(game);

      final droneBayId = game.snapshot.selectedTower?.id;
      expect(droneBayId, isNull); // not selected yet

      _tapCell(game, const GridPosition(0, 1)); // select the drone bay
      game.processLifecycleEvents();
      final ownerTowerId = game.snapshot.selectedTower!.id;

      game.sellSelectedTower();
      game.processLifecycleEvents();

      expect(
        game.children.whereType<DroneComponent>().where(
          (d) => d.ownerTowerId == ownerTowerId,
        ),
        isEmpty,
      );
      expect(game.children.whereType<TowerComponent>(), isEmpty);
    });

    test('sellSelectedTower despawns a sold gravity well lingering fields', () {
      final game = OrionDefenseGame(stage: _gravityWellUnlockStage());
      game.onGameResize(Vector2(800, 1200));

      // Advance 4 empty waves so the gravity well (unlocks at wave 5) is
      // available.
      for (var wave = 0; wave < 4; wave += 1) {
        game.startWave();
        game.update(0);
        game.processLifecycleEvents();
        _selectPendingModuleIfNeeded(game);
      }
      expect(game.snapshot.phase, GamePhase.build);
      expect(game.snapshot.unlockedTowerTypes, contains(TowerType.gravityWell));

      // Place the gravity well adjacent to the wave-5 path and run that wave.
      _tapCell(game, const GridPosition(0, 1));
      game.placeTower(TowerType.gravityWell);
      game.processLifecycleEvents();
      expect(game.children.whereType<TowerComponent>(), hasLength(1));

      game.startWave(); // wave 5: one durable enemy
      game.update(0.01); // spawn the enemy
      game.processLifecycleEvents();
      // See the drone bay test: firing the tower via its own update() avoids
      // a concurrent-modification error in unmounted unit tests.
      game.children.whereType<TowerComponent>().single.update(0.01);
      game.processLifecycleEvents();

      final fieldsBefore = game.children
          .whereType<GravityFieldComponent>()
          .toList();
      expect(fieldsBefore, isNotEmpty); // guards against a vacuous pass

      // End the wave (sell is build-phase only) by resolving the enemy. The
      // field's fieldDuration (2.0s) has NOT elapsed, so it would otherwise
      // linger into the next wave.
      final enemy = game.children.whereType<EnemyComponent>().single;
      enemy.applyDamage(10000);
      game.update(0.01);
      game.processLifecycleEvents();
      expect(game.snapshot.phase, GamePhase.build);

      // The lingering field is still on screen before the sell.
      final ownerTowerId = game.children
          .whereType<TowerComponent>()
          .single
          .placedTower
          .id;
      expect(
        game.children.whereType<GravityFieldComponent>().where(
          (f) => f.ownerTowerId == ownerTowerId,
        ),
        isNotEmpty,
      );

      _tapCell(game, const GridPosition(0, 1)); // select the gravity well
      game.processLifecycleEvents();
      game.sellSelectedTower();
      game.processLifecycleEvents();

      expect(
        game.children.whereType<GravityFieldComponent>().where(
          (f) => f.ownerTowerId == ownerTowerId,
        ),
        isEmpty,
      );
      expect(game.children.whereType<TowerComponent>(), isEmpty);
    });

    test(
      'gravity field safely resolves multiple enemies in one tick',
      () async {
        final game = OrionDefenseGame(stage: _lethalGravityFieldStage());
        game.onGameResize(Vector2(800, 1200));
        await game.onLoad();
        // ignore: invalid_use_of_internal_member
        game.setMounted();

        for (var wave = 0; wave < 4; wave += 1) {
          game.startWave();
          game.update(0);
          game.processLifecycleEvents();
          _selectPendingModuleIfNeeded(game);
        }
        _tapCell(game, const GridPosition(0, 1));
        game.placeTower(TowerType.gravityWell);
        game.processLifecycleEvents();

        game.startWave();
        game.update(0.01);
        game.processLifecycleEvents();
        expect(game.children.whereType<EnemyComponent>(), hasLength(2));

        // Fire directly so both targets are still co-located when the field
        // receives its first tick.
        game.children.whereType<TowerComponent>().single.update(0.01);
        game.processLifecycleEvents();
        expect(game.children.whereType<GravityFieldComponent>(), isNotEmpty);

        // Both enemies are inside the same lethal field. Resolving the first
        // removes it from the provider's backing map, so the field must iterate
        // a stable snapshot before continuing to the second.
        game.update(0.01);
        game.processLifecycleEvents();

        expect(game.children.whereType<EnemyComponent>(), isEmpty);
        expect(game.snapshot.phase, GamePhase.build);
      },
    );

    test('applies campaign modifiers to session starting values', () {
      final game = OrionDefenseGame(
        stage: stageWithWaveCount(2),
        campaignModifiers: const CampaignModifiers(
          bonusGold: 30,
          bonusHealth: 5,
        ),
      );

      expect(game.snapshot.gold, GameBalance.startingGold + 30);
      expect(game.snapshot.baseHealth, GameBalance.initialBaseHealth + 5);
      expect(
        game.snapshot.startingBaseHealth,
        GameBalance.initialBaseHealth + 5,
      );
    });

    test('defaults to no campaign modifiers and baseline economy', () {
      final game = OrionDefenseGame(stage: stageWithWaveCount(2));

      expect(game.snapshot.gold, GameBalance.startingGold);
      expect(game.snapshot.baseHealth, GameBalance.initialBaseHealth);
    });

    test('clearBonusFraction amplifies the wave-clear gold bonus when set', () {
      // Wave-clear bonus resolution lives in GameSession.finishActiveWave,
      // which reads session.campaignModifiers.clearBonusFraction. If
      // OrionDefenseGame fails to forward its campaignModifiers to
      // GameSession.initial, the fraction
      // stays 0 and the bonus is unscaled.
      final game = OrionDefenseGame(
        stage: _clearBonusStage(clearBonus: 100),
        campaignModifiers: const CampaignModifiers(clearBonusFraction: 0.5),
      );
      game.onGameResize(Vector2(800, 1200));

      final goldBefore = game.snapshot.gold;
      game.startWave();
      game.update(0);

      expect(game.snapshot.phase, GamePhase.build);
      // 100 * (1 + 0.5) = 150 added on top of the starting gold.
      expect(game.snapshot.gold, goldBefore + 150);
    });

    test(
      'wave-clear gold bonus is unscaled when campaign modifiers are absent',
      () {
        final game = OrionDefenseGame(stage: _clearBonusStage(clearBonus: 100));
        game.onGameResize(Vector2(800, 1200));

        final goldBefore = game.snapshot.gold;
        game.startWave();
        game.update(0);

        expect(game.snapshot.phase, GamePhase.build);
        expect(game.snapshot.gold, goldBefore + 100);
      },
    );

    test(
      'laser tower stats reflect laserDamageFraction from campaign modifiers',
      () {
        // TowerComponent resolves its stats through TowerStatsResolver.resolve,
        // which reads its campaignModifiers field. If OrionDefenseGame fails to
        // forward campaignModifiers to _addTowerComponent, the placed tower uses
        // CampaignModifiers.empty and the damage is unscaled.
        const mods = CampaignModifiers(laserDamageFraction: 0.10);
        final game = OrionDefenseGame(
          stage: _singleEnemyStage(),
          campaignModifiers: mods,
        );
        game.onGameResize(Vector2(800, 1200));
        _tapCell(game, const GridPosition(0, 1));
        game.placeTower(TowerType.laser);
        game.processLifecycleEvents();

        final component = game.children.whereType<TowerComponent>().single;
        final base = GameBalance.towerStats(TowerType.laser, level: 1);
        expect(component.stats.damage, closeTo(base.damage * 1.10, 1e-9));
      },
    );

    test(
      'upgrading a laser tower re-applies laserDamageFraction via updateTower',
      () {
        // Exercises the updateTower call site in upgradeSelectedTower.
        // If updateTower fails to re-resolve stats through
        // TowerStatsResolver.resolve, the upgraded tower uses the unmodified
        // level-2 base damage (18) instead of the scaled value (19.8).
        const mods = CampaignModifiers(laserDamageFraction: 0.10);
        final game = OrionDefenseGame(
          stage: _singleEnemyStage(),
          campaignModifiers: mods,
        );
        game.onGameResize(Vector2(800, 1200));
        _tapCell(game, const GridPosition(0, 1));
        game.placeTower(TowerType.laser);
        game.processLifecycleEvents();
        _tapCell(game, const GridPosition(0, 1)); // select the placed tower
        game.processLifecycleEvents();

        game.upgradeSelectedTower();
        game.processLifecycleEvents();

        final component = game.children.whereType<TowerComponent>().single;
        final base = GameBalance.towerStats(TowerType.laser, level: 2);
        expect(component.stats.damage, closeTo(base.damage * 1.10, 1e-9));
      },
    );

    test(
      'specializing a laser tower re-applies laserDamageFraction via updateTower',
      () {
        // Exercises the updateTower call site in specializeSelectedTower.
        // bonusGold covers place(50) + upgrade(70) + specialize(120) = 240.
        const mods = CampaignModifiers(
          laserDamageFraction: 0.10,
          bonusGold: 100,
        );
        final game = OrionDefenseGame(
          stage: _singleEnemyStage(),
          campaignModifiers: mods,
        );
        game.onGameResize(Vector2(800, 1200));
        _tapCell(game, const GridPosition(0, 1));
        game.placeTower(TowerType.laser);
        game.processLifecycleEvents();
        _tapCell(game, const GridPosition(0, 1)); // select the placed tower
        game.processLifecycleEvents();

        game.upgradeSelectedTower();
        game.processLifecycleEvents();

        game.specializeSelectedTower(TowerSpecialization.pulseLaser);
        game.processLifecycleEvents();

        final component = game.children.whereType<TowerComponent>().single;
        final base = GameBalance.towerStats(
          TowerType.laser,
          level: 3,
          specialization: TowerSpecialization.pulseLaser,
        );
        expect(component.stats.damage, closeTo(base.damage * 1.10, 1e-9));
      },
    );

    test(
      'retargeting a laser tower preserves laserDamageFraction via updateTower',
      () {
        // Exercises the updateTower call site in setTargetingMode
        // (orion_defense_game.dart:282). If updateTower fails to re-resolve
        // stats, the targeting-mode change drops the damage multiplier.
        const mods = CampaignModifiers(laserDamageFraction: 0.10);
        final game = OrionDefenseGame(
          stage: _singleEnemyStage(),
          campaignModifiers: mods,
        );
        game.onGameResize(Vector2(800, 1200));
        _tapCell(game, const GridPosition(0, 1));
        game.placeTower(TowerType.laser);
        game.processLifecycleEvents();
        _tapCell(game, const GridPosition(0, 1)); // select the placed tower
        game.processLifecycleEvents();

        game.setTargetingMode(TowerTargetingMode.strongest);
        game.processLifecycleEvents();

        final component = game.children.whereType<TowerComponent>().single;
        final base = GameBalance.towerStats(TowerType.laser, level: 1);
        expect(component.stats.damage, closeTo(base.damage * 1.10, 1e-9));
        expect(
          component.placedTower.targetingMode,
          TowerTargetingMode.strongest,
        );
      },
    );

    for (final specialization in [
      TowerSpecialization.singularityWell,
      TowerSpecialization.crushWell,
    ]) {
      test(
        'tower component retains amplified stats through ${specialization.label}',
        () {
          final game = OrionDefenseGame(
            stage: _gravityWellUnlockStage(
              modifiers: const [StageModifier.amplifiedGravityWells],
            ),
            campaignModifiers: const CampaignModifiers(bonusGold: 1000),
          );
          game.onGameResize(Vector2(800, 1200));
          for (var wave = 0; wave < 4; wave += 1) {
            game.startWave();
            game.update(0);
            _selectPendingModuleIfNeeded(game);
          }
          _tapCell(game, const GridPosition(0, 1));
          game.placeTower(TowerType.gravityWell);
          game.processLifecycleEvents();

          var component = game.children.whereType<TowerComponent>().single;
          var base = GameBalance.towerStats(TowerType.gravityWell, level: 1);
          expect(
            component.stats.fieldRadius,
            closeTo(base.fieldRadius * 1.20, 0.001),
          );

          _tapCell(game, const GridPosition(0, 1));
          game.upgradeSelectedTower();
          component = game.children.whereType<TowerComponent>().single;
          base = GameBalance.towerStats(TowerType.gravityWell, level: 2);
          expect(
            component.stats.fieldDuration,
            closeTo(base.fieldDuration * 1.25, 0.001),
          );

          game.specializeSelectedTower(specialization);
          component = game.children.whereType<TowerComponent>().single;
          base = GameBalance.towerStats(
            TowerType.gravityWell,
            level: 3,
            specialization: specialization,
          );
          expect(
            component.stats.fieldRadius,
            closeTo(base.fieldRadius * 1.20, 0.001),
          );
          expect(
            component.stats.fieldDuration,
            closeTo(base.fieldDuration * 1.25, 0.001),
          );
        },
      );
    }

    test(
      'restart resets base health to campaign-modifier-adjusted starting value',
      () {
        // A session created with non-zero campaign modifiers must reset back to the
        // adjusted starting values (not the unmodified baseline, and not the
        // damaged mid-wave value) after restart.
        const bonusHealth = 5;
        const bonusGold = 30;
        const adjustedStartingHealth =
            GameBalance.initialBaseHealth + bonusHealth;
        const adjustedStartingGold = GameBalance.startingGold + bonusGold;
        final game = OrionDefenseGame(
          stage: _lethalSingleEnemyStage(),
          campaignModifiers: const CampaignModifiers(
            bonusGold: bonusGold,
            bonusHealth: bonusHealth,
          ),
        );

        expect(game.snapshot.gold, adjustedStartingGold);
        expect(game.snapshot.baseHealth, adjustedStartingHealth);
        expect(game.snapshot.startingBaseHealth, adjustedStartingHealth);

        // Damage the base: the lethal enemy deals initialBaseHealth damage,
        // which the bonus health absorbs so the base survives but is hurt.
        game.onGameResize(Vector2(800, 1200));
        game.startWave();
        game.update(0.01);
        game.processLifecycleEvents();
        game.update(1);
        game.processLifecycleEvents();

        expect(
          game.snapshot.baseHealth,
          lessThan(adjustedStartingHealth),
          reason: 'base should be damaged before restart',
        );
        expect(game.snapshot.baseHealth, greaterThan(0));

        game.restart();

        expect(game.snapshot.phase, GamePhase.build);
        expect(game.snapshot.baseHealth, adjustedStartingHealth);
        expect(game.snapshot.startingBaseHealth, adjustedStartingHealth);
        expect(game.snapshot.gold, adjustedStartingGold);
      },
    );

    test(
      'boss summons minions that path from its position and block completion',
      () {
        final game = OrionDefenseGame(stage: _bossSummonStage());
        game.onGameResize(Vector2(800, 1200));
        game.startWave();
        // Spawn the boss. firstDelay (0.5s) has not elapsed, so no summon yet
        // and no concurrent-modification risk on this tick.
        game.update(0.01);
        game.processLifecycleEvents();

        final boss = game.children.whereType<EnemyComponent>().single;
        expect(boss.stats, isA<BossDefinition>());

        // Advance the boss directly past firstDelay to trigger the summon.
        game.update(0.5 + 0.01);
        game.processLifecycleEvents();

        final minions = game.children
            .whereType<EnemyComponent>()
            .where((e) => e.minionOf == boss.enemyId)
            .toList();
        // Boss requests count=3 per trigger but maxActive=2 caps the spawn.
        expect(minions, hasLength(2));
        for (final minion in minions) {
          expect(minion.pathProgress, closeTo(boss.pathProgress, 1e-6));
        }

        // Killing the boss leaves minions alive, blocking wave completion.
        boss.applyDamage(boss.maxHealth);
        game.processLifecycleEvents();
        game.update(0.01);
        game.processLifecycleEvents();

        expect(
          game.children.whereType<EnemyComponent>().where(
            (e) => e.minionOf != null,
          ),
          isNotEmpty,
        );
        expect(game.snapshot.phase, GamePhase.wave);

        // Clearing the minions completes the wave.
        for (final minion
            in game.children.whereType<EnemyComponent>().toList()) {
          minion.applyDamage(minion.maxHealth);
        }
        game.processLifecycleEvents();
        game.update(0.01);
        game.processLifecycleEvents();

        expect(game.children.whereType<EnemyComponent>(), isEmpty);
        expect(game.snapshot.phase, GamePhase.build);
      },
    );

    test(
      'corrosion applied by a projectile during super.update ticks lethal same frame',
      () async {
        final game = OrionDefenseGame(stage: _oneEnemyStage());
        game.onGameResize(Vector2(800, 1200));
        await game.onLoad();
        // FlameGame is never mounted in unit tests (no GameWidget drives the
        // lifecycle), so removeFromParent() during super.update modifies the
        // children set immediately instead of enqueueing — causing concurrent
        // modification when the projectile lands and removes itself mid-
        // iteration. setMounted() puts the game into the mounted state so
        // removals enqueue.
        // ignore: invalid_use_of_internal_member
        game.setMounted();
        game.startWave();
        game.update(0.01);
        game.processLifecycleEvents();
        final enemy = game.children.whereType<EnemyComponent>().single;
        // Corrosion is NOT yet active before the projectile lands — this is
        // what makes the test prove the projectile-to-tick ordering: the
        // corrosion must be applied during super.update and then consumed by
        // _tickEnemyLogic later in the SAME frame.
        expect(enemy.isCorroded, isFalse);
        // Mount a real nanite projectile 50 units from the enemy. With
        // projectileSpeed=100 it does NOT land on update(0) (50 > max(0, 11))
        // but DOES land on update(1) (50 <= 100) during super.update, applying
        // corrosion. _tickEnemyLogic then runs in the same frame and ticks 1s
        // of corrosion → lethal. damage=10 is non-lethal so the corrosion tick
        // (not the projectile hit) must be the killer.
        final projectileStats = const TowerStats(
          type: TowerType.nanite,
          level: 1,
          cost: 0,
          upgradeCost: 0,
          specializationCost: 0,
          range: 100,
          damage: 10,
          fireInterval: 1,
          projectileSpeed: 100,
          splashRadius: 0,
          slowMultiplier: 1,
          slowDuration: 0,
          corrosionDamagePerSecond: 1000,
          corrosionDuration: 10,
          armorShred: 0,
        );
        game.add(
          ProjectileComponent(
            stats: projectileStats,
            target: enemy,
            startPosition: enemy.position + Vector2(50, 0),
            enemiesProvider: () => game.children.whereType<EnemyComponent>(),
            priority: 30,
          ),
        );
        // update(0) mounts the projectile without it landing (scaledDt=0,
        // 50 > max(0, radius=11)).
        game.update(0);
        game.processLifecycleEvents();
        expect(
          enemy.isCorroded,
          isFalse,
          reason: 'projectile must not land on the mount frame',
        );
        // dt=1: the projectile lands during super.update applying corrosion;
        // _tickEnemyLogic then ticks 1s of corrosion → lethal. If enemy
        // ticking moved before super.update, or projectile-applied effects
        // were delayed until next frame, the enemy would NOT die this frame.
        game.update(1);
        game.processLifecycleEvents();
        expect(enemy.isResolved, isTrue); // corrosion killed it this frame
        expect(game.children.whereType<EnemyComponent>(), isEmpty);
      },
    );

    test('defeat mid-tick stops ticking remaining enemies', () {
      final game = OrionDefenseGame(stage: _twoEnemyDefeatStage());
      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.01);
      game.processLifecycleEvents();
      // With spawnInterval=0, both enemies are already on the board before the
      // lethal update — the trailing one must NOT be dispatched as killed or
      // reach-base, and no fresh enemy may be spawned after defeat.
      final enemiesBeforeLethal = game.children
          .whereType<EnemyComponent>()
          .toList();
      expect(enemiesBeforeLethal, hasLength(2));
      final goldBefore = game.snapshot.gold;
      // Advance: the lead enemy reaches base and defeats the player.
      // The loop must break so the trailing enemy is NOT dispatched as killed.
      game.update(60);
      game.processLifecycleEvents();
      expect(game.snapshot.phase, GamePhase.lost);
      // reach-base never rewards gold; a spurious onKilled for the trailing
      // enemy would have called rewardKill and increased gold.
      expect(game.snapshot.gold, goldBefore);
      // _handleEnemyReachedBase runs _clearCombatComponents on defeat, and the
      // post-tick phase guard prevents _spawnWaveEnemies from repopulating the
      // board. No remainder enemy may survive or be freshly spawned.
      expect(game.children.whereType<EnemyComponent>(), isEmpty);
    });

    test(
      'onKilled fires exactly once when lethal damage lands on a would-overrun frame',
      () async {
        final game = OrionDefenseGame(stage: _oneEnemyStage());
        game.onGameResize(Vector2(800, 1200));
        await game.onLoad();
        // FlameGame is never mounted in unit tests (no GameWidget drives the
        // lifecycle), so removeFromParent() during super.update modifies the
        // children set immediately instead of enqueueing — causing concurrent
        // modification when a projectile lands and removes itself mid-iteration.
        // setMounted() puts the game into the mounted state so removals enqueue.
        // ignore: invalid_use_of_internal_member
        game.setMounted();
        game.startWave();
        game.update(0.01);
        game.processLifecycleEvents();
        final enemy = game.children.whereType<EnemyComponent>().single;
        // _oneEnemyStage path is [(50,50),(150,50)] (length 100); speed 10.
        // Advance until the enemy is 1 unit from the base so the next tick
        // would overrun it.
        game.update(9.9);
        game.processLifecycleEvents();
        expect(enemy.isAlive, isTrue);
        expect(enemy.position.x, closeTo(149, 0.5));
        final goldBefore = game.snapshot.gold;
        final baseHealthBefore = game.snapshot.baseHealth;
        // Mount a real lethal projectile 50 units from the enemy so it does NOT
        // land on update(0) (50 > target.radius 11) but DOES land on update(1)
        // (50 <= projectileSpeed*1 = 100). This makes the kill and the would-be
        // overrun compete on the same frame.
        final projectileStats = const TowerStats(
          type: TowerType.laser,
          level: 1,
          cost: 0,
          upgradeCost: 0,
          specializationCost: 0,
          range: 100,
          damage: 100,
          fireInterval: 1,
          projectileSpeed: 100,
          splashRadius: 0,
          slowMultiplier: 1,
          slowDuration: 0,
        );
        game.add(
          ProjectileComponent(
            stats: projectileStats,
            target: enemy,
            startPosition: enemy.position + Vector2(50, 0),
            enemiesProvider: () => game.children.whereType<EnemyComponent>(),
            priority: 30,
          ),
        );
        // update(0) mounts the projectile without it landing (scaledDt=0,
        // 50 > max(0, radius=11)) and without advancing the enemy.
        game.update(0);
        game.processLifecycleEvents();
        expect(
          game.snapshot.gold,
          goldBefore,
          reason: 'projectile must not land on the mount frame',
        );
        // dt=1: the projectile lands (50 <= 100) during super.update, killing
        // the enemy and dispatching onKilled. _tickEnemyLogic then runs but the
        // enemy is already removed from _activeEnemyComponents — the would-be
        // overrun is preempted by the kill.
        game.update(1);
        game.processLifecycleEvents();
        // Only the kill callback path wins: gold awarded exactly once.
        expect(game.snapshot.gold, goldBefore + enemy.stats.goldReward);
        // Base health unchanged — reach-base was preempted by the kill.
        expect(game.snapshot.baseHealth, baseHealthBefore);
        // The enemy is gone; no duplicate resolution is possible.
        expect(game.children.whereType<EnemyComponent>(), isEmpty);
      },
    );

    test(
      'overlay drops slow/corrosion on tick expiry without an external apply',
      () {
        final game = OrionDefenseGame(stage: _oneEnemyStage());
        game.onGameResize(Vector2(800, 1200));
        game.startWave();
        game.update(0.01);
        game.processLifecycleEvents();
        final enemy = game.children.whereType<EnemyComponent>().single;
        enemy.applySlow(multiplier: 0.5, duration: 1);
        enemy.applyCorrosion(damagePerSecond: 1, duration: 1, armorShred: 0);
        expect(enemy.overlayState.badges, contains(EnemyOverlayBadge.slowed));
        game.update(1);
        game.processLifecycleEvents(); // both expire via tick
        expect(enemy.isSlowed, isFalse);
        expect(enemy.isCorroded, isFalse);
        expect(
          enemy.overlayState.badges,
          isNot(contains(EnemyOverlayBadge.slowed)),
        );
      },
    );
  });
}

StageDefinition _modifierStage({
  required List<StageModifier> modifiers,
  required EnemyStats enemyStats,
  int enemyCount = 1,
  double spawnInterval = 1,
}) {
  return StageDefinition(
    id: 'modifier-stage',
    name: 'Modifier Stage',
    mapLabel: 'Modifier',
    description: 'Synthetic modifier integration stage',
    pathCells: const [
      GridPosition(0, 0),
      GridPosition(1, 0),
      GridPosition(2, 0),
      GridPosition(3, 0),
    ],
    waves: [
      WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: enemyCount,
            enemyStats: enemyStats,
            spawnInterval: spawnInterval,
          ),
        ],
        clearBonus: 0,
      ),
    ],
    modifiers: modifiers,
    mapColumn: 0,
    mapRow: 0,
  );
}

StageDefinition _clearBonusStage({required int clearBonus, int waveCount = 2}) {
  return StageDefinition(
    id: 'clear-bonus-stage',
    name: 'Clear Bonus Stage',
    mapLabel: 'Bonus',
    description: 'Stage with non-zero clear bonus for modifier tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: List<WaveDefinition>.generate(
      waveCount,
      (_) => WaveDefinition(groups: const [], clearBonus: clearBonus),
      growable: false,
    ),
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

StageDefinition _singleEnemyStage() {
  return StageDefinition(
    id: 'single-enemy-stage',
    name: 'Single Enemy Stage',
    mapLabel: 'Single',
    description: 'Stage with one enemy for pause timing tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: const [
      WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 1,
            enemyStats: EnemyStats(
              health: 100,
              speed: 1,
              baseDamage: 1,
              goldReward: 0,
            ),
          ),
        ],
        clearBonus: 0,
      ),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

StageDefinition _twoEnemyDelayedSpawnStage() {
  return StageDefinition(
    id: 'two-enemy-delayed-spawn-stage',
    name: 'Two Enemy Delayed Spawn Stage',
    mapLabel: 'Delayed',
    description: 'Stage with delayed second enemy for pause timing tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: const [
      WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 2,
            spawnInterval: 5,
            enemyStats: EnemyStats(
              health: 100,
              speed: 1,
              baseDamage: 1,
              goldReward: 0,
            ),
          ),
        ],
        clearBonus: 0,
      ),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

StageDefinition _twoEnemyImmediateSpawnStage() {
  return StageDefinition(
    id: 'two-enemy-immediate-spawn-stage',
    name: 'Two Enemy Immediate Spawn Stage',
    mapLabel: 'Immediate',
    description: 'Stage with two enemies for inspection tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: const [
      WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 2,
            spawnInterval: 0.01,
            enemyStats: EnemyStats(
              health: 100,
              speed: 0,
              baseDamage: 1,
              goldReward: 0,
            ),
          ),
        ],
        clearBonus: 0,
      ),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

StageDefinition _bossSummonStage() {
  return StageDefinition(
    id: 'boss-summon-stage',
    name: 'Boss Summon Stage',
    mapLabel: 'Boss',
    description: 'Stage with a summoning boss for minion spawn tests',
    pathCells: const [
      GridPosition(0, 0),
      GridPosition(1, 0),
      GridPosition(2, 0),
      GridPosition(3, 0),
      GridPosition(4, 0),
    ],
    waves: const [
      WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 1,
            enemyStats: BossDefinition(
              health: 5000,
              speed: 10,
              baseDamage: 1,
              goldReward: 0,
              sprite: BossSprite.swarmQueen,
              name: 'Swarm Queen',
              summonMechanic: SummonMechanic(
                interval: 100,
                firstDelay: 0.5,
                count: 3,
                maxActive: 2,
                minionStats: EnemyStats(
                  health: 50,
                  speed: 10,
                  baseDamage: 1,
                  goldReward: 0,
                ),
              ),
            ),
          ),
        ],
        clearBonus: 0,
      ),
      // A trailing empty wave so clearing the boss wave lands in build phase.
      WaveDefinition(groups: [], clearBonus: 0),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

StageDefinition _lethalSingleEnemyStage() {
  return StageDefinition(
    id: 'lethal-single-enemy-stage',
    name: 'Lethal Single Enemy Stage',
    mapLabel: 'Lethal',
    description: 'Stage with one lethal enemy for loss reset tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: const [
      WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 1,
            enemyStats: EnemyStats(
              health: 100,
              speed: 1000,
              baseDamage: GameBalance.initialBaseHealth,
              goldReward: 0,
            ),
          ),
        ],
        clearBonus: 0,
      ),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

StageDefinition _oneEnemyStage() {
  return StageDefinition(
    id: 'one-enemy-stage',
    name: 'One Enemy Stage',
    mapLabel: 'One',
    description: 'Stage with one enemy for orchestrator ticking tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: const [
      WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 1,
            enemyStats: EnemyStats(
              health: 100,
              speed: 10,
              baseDamage: 1,
              goldReward: 1,
            ),
          ),
        ],
        clearBonus: 0,
      ),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

StageDefinition _twoEnemyDefeatStage() {
  return StageDefinition(
    id: 'two-enemy-defeat-stage',
    name: 'Two Enemy Defeat Stage',
    mapLabel: 'Defeat',
    description: 'Stage with two lethal enemies for defeat-mid-tick tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: const [
      WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 2,
            // spawnInterval=0 so both enemies are alive in the same tick,
            // exercising the mid-tick defeat break in _tickEnemyLogic.
            spawnInterval: 0,
            enemyStats: EnemyStats(
              health: 100,
              speed: 10,
              baseDamage: GameBalance.initialBaseHealth,
              goldReward: 50,
            ),
          ),
        ],
        clearBonus: 0,
      ),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

/// Stage whose first 5 waves are empty (to unlock the wave-6 drone bay) and
/// whose 6th wave spawns a single durable enemy for drone-launch tests.
StageDefinition _droneBayUnlockStage() {
  return StageDefinition(
    id: 'drone-bay-unlock-stage',
    name: 'Drone Bay Unlock Stage',
    mapLabel: 'Drone',
    description: 'Stage that unlocks the drone bay for sell tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: [
      for (var wave = 0; wave < 5; wave += 1)
        const WaveDefinition(groups: [], clearBonus: 0),
      const WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 1,
            enemyStats: EnemyStats(
              health: 10000,
              speed: 1,
              baseDamage: 1,
              goldReward: 0,
            ),
          ),
        ],
        clearBonus: 0,
      ),
      // A trailing empty wave so clearing wave 6 leaves the game in build
      // phase (not won), allowing the sell-during-build flow to be tested.
      const WaveDefinition(groups: [], clearBonus: 0),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

StageDefinition _droneBayModuleRefreshStage() {
  const durableEnemy = EnemyStats(
    health: 100000,
    speed: 1,
    baseDamage: 1,
    goldReward: 0,
  );
  return StageDefinition(
    id: 'drone-bay-module-refresh-stage',
    name: 'Drone Bay Module Refresh Stage',
    mapLabel: 'Drone',
    description: 'Stage that keeps a drone alive across module selection',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: [
      for (var wave = 0; wave < 5; wave += 1)
        const WaveDefinition(groups: [], clearBonus: 0),
      const WaveDefinition(
        groups: [WaveGroup(enemyCount: 1, enemyStats: durableEnemy)],
        clearBonus: 0,
      ),
      const WaveDefinition(
        groups: [WaveGroup(enemyCount: 1, enemyStats: durableEnemy)],
        clearBonus: 0,
      ),
      const WaveDefinition(groups: [], clearBonus: 0),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

/// Stage that unlocks the gravity well at wave 5 and keeps a lingering field
/// alive across the wave-6 module draft. Waves 1-5 are empty (drafts at 2 and
/// 4 must be dismissed), wave 6 spawns a durable enemy whose gravity field can
/// survive the wave clear into draft 3, and wave 7 spawns another durable
/// enemy to exercise the refreshed field's tick.
StageDefinition _gravityWellModuleRefreshStage() {
  const durableEnemy = EnemyStats(
    health: 100000,
    speed: 1,
    baseDamage: 1,
    goldReward: 0,
  );
  return StageDefinition(
    id: 'gravity-well-module-refresh-stage',
    name: 'Gravity Well Module Refresh Stage',
    mapLabel: 'Gravity',
    description:
        'Stage that keeps a gravity field alive across module selection',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: [
      for (var wave = 0; wave < 5; wave += 1)
        const WaveDefinition(groups: [], clearBonus: 0),
      const WaveDefinition(
        groups: [WaveGroup(enemyCount: 1, enemyStats: durableEnemy)],
        clearBonus: 0,
      ),
      const WaveDefinition(
        groups: [WaveGroup(enemyCount: 1, enemyStats: durableEnemy)],
        clearBonus: 0,
      ),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

/// Stage whose first 4 waves are empty (to unlock the wave-5 gravity well) and
/// whose 5th wave spawns a single durable enemy for gravity-field tests.
StageDefinition _gravityWellUnlockStage({
  List<StageModifier> modifiers = const [],
}) {
  return StageDefinition(
    id: 'gravity-well-unlock-stage',
    name: 'Gravity Well Unlock Stage',
    mapLabel: 'Gravity',
    description: 'Stage that unlocks the gravity well for sell tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: [
      for (var wave = 0; wave < 4; wave += 1)
        const WaveDefinition(groups: [], clearBonus: 0),
      const WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 1,
            enemyStats: EnemyStats(
              health: 10000,
              speed: 1,
              baseDamage: 1,
              goldReward: 0,
            ),
          ),
        ],
        clearBonus: 0,
      ),
      // A trailing empty wave so clearing wave 5 leaves the game in build
      // phase (not won), allowing the sell-during-build flow to be tested.
      const WaveDefinition(groups: [], clearBonus: 0),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
    modifiers: modifiers,
  );
}

StageDefinition _lethalGravityFieldStage() {
  return StageDefinition(
    id: 'lethal-gravity-field-stage',
    name: 'Lethal Gravity Field Stage',
    mapLabel: 'Gravity',
    description: 'Two enemies share one lethal gravity field',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: [
      for (var wave = 0; wave < 4; wave += 1)
        const WaveDefinition(groups: [], clearBonus: 0),
      const WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 2,
            enemyStats: EnemyStats(
              health: 1,
              speed: 0,
              baseDamage: 1,
              goldReward: 0,
            ),
            spawnInterval: 0,
          ),
        ],
        clearBonus: 0,
      ),
      const WaveDefinition(groups: [], clearBonus: 0),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

void _tapCell(OrionDefenseGame game, GridPosition position) {
  final center = BoardLayout.cellCenter(
    position,
    cellSize: 100,
    boardOrigin: Offset.zero,
  );
  game.onTapDown(TapDownEvent(1, game, TapDownDetails(globalPosition: center)));
}

void _selectPendingModuleIfNeeded(OrionDefenseGame game) {
  final offer = game.snapshot.pendingRunModuleOffer;
  if (offer == null) return;
  final moduleId = offer.moduleIds.firstWhere(
    (id) => id != RunModuleId.emergencySalvage,
  );
  game.selectRunModule(offer.offerId, moduleId);
}

void _tapPoint(OrionDefenseGame game, Vector2 point) {
  game.onTapDown(
    TapDownEvent(
      1,
      game,
      TapDownDetails(globalPosition: Offset(point.x, point.y)),
    ),
  );
}
