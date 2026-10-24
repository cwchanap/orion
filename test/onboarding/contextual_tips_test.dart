import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/onboarding/contextual_tips.dart';

WavePreviewGroup _group(String label, {int count = 8}) =>
    WavePreviewGroup(enemyCount: count, label: label, traits: const {});

WavePreview _preview({int waveNumber = 7, List<WavePreviewGroup>? groups}) {
  return WavePreview(
    waveNumber: waveNumber,
    waveTotal: 8,
    groups: groups ?? [_group('Armored Drones'), _group('Regen Heavy Drones')],
    traits: const {},
    clearBonus: 95,
    recommendedTowerTypes: const [TowerType.laser],
  );
}

/// The finale preview of Outpost Alpha: ordinary groups plus the boss.
WavePreview _bossPreview({int waveNumber = 8}) {
  return _preview(
    waveNumber: waveNumber,
    groups: [
      _group('Basic Drones', count: 6),
      _group('Relay Breaker', count: 1),
    ],
  );
}

GameSnapshot _snapshot({
  GamePhase phase = GamePhase.build,
  int waveNumber = 7,
  WavePreview? nextWavePreview,
  GridPosition? selectedCell,
  PlacedTower? selectedTower,
  RunModuleOffer? pendingRunModuleOffer,
  List<StageModifier> stageModifiers = const [],
  List<TowerType> unlockedTowerTypes = const [
    TowerType.laser,
    TowerType.railgun,
  ],
  bool selectedCellBuildable = true,
  List<PlacedTower> placedTowers = const [],
}) {
  return GameSnapshot(
    phase: phase,
    gold: 150,
    baseHealth: 20,
    startingBaseHealth: 20,
    waveNumber: waveNumber,
    waveTotal: 8,
    stageId: 'nebula-relay',
    stageName: 'Nebula Relay',
    stageLabel: 'NR',
    unlockedTowerTypes: unlockedTowerTypes,
    stageModifiers: stageModifiers,
    nextWavePreview: nextWavePreview,
    selectedCell: selectedCell,
    selectedTower: selectedTower,
    selectedCellBuildable: selectedCellBuildable,
    feedback: null,
    isPaused: false,
    speedMultiplier: 1,
    autoStartEnabled: false,
    autoStartCountdownRemaining: null,
    pendingRunModuleOffer: pendingRunModuleOffer,
    placedTowers: placedTowers,
  );
}

PlacedTower _placed(TowerType type, int id) =>
    PlacedTower(id: id, type: type, position: GridPosition(2, 2 + id));

void main() {
  group('ContextualTip enum', () {
    test('declares the nine tips in resolver priority order', () {
      expect(ContextualTip.values.map((tip) => tip.name), [
        'bossWave',
        'railgun',
        'ionChain',
        'nanite',
        'gravityWell',
        'droneBay',
        'specialization',
        'targeting',
        'stageModifier',
      ]);
    });
  });

  group('contextualTipCopy', () {
    test('covers every tip exactly once', () {
      expect(contextualTipCopy.length, ContextualTip.values.length);
      for (final tip in ContextualTip.values) {
        expect(contextualTipCopy[tip], isNotNull, reason: tip.name);
      }
    });

    test('carries the exact design copy verbatim', () {
      expect(
        contextualTipCopy[ContextualTip.bossWave],
        'Boss ahead. Check the scanner and prepare your defense.',
      );
      expect(
        contextualTipCopy[ContextualTip.railgun],
        'Railgun unlocked. Pierces enemies in a line.',
      );
      expect(
        contextualTipCopy[ContextualTip.ionChain],
        'Ion Chain unlocked. Lightning jumps between targets.',
      );
      expect(
        contextualTipCopy[ContextualTip.nanite],
        'Nanite unlocked. Corrodes armor to help other towers.',
      );
      expect(
        contextualTipCopy[ContextualTip.gravityWell],
        'Gravity Well unlocked. Damages enemies within its field.',
      );
      expect(
        contextualTipCopy[ContextualTip.droneBay],
        'Drone Bay unlocked. Launches autonomous interceptors.',
      );
      expect(
        contextualTipCopy[ContextualTip.specialization],
        'Specialization ready. Choose one of two ways to evolve this tower.',
      );
      expect(
        contextualTipCopy[ContextualTip.targeting],
        'Targeting modes. Choose which enemies this tower attacks first.',
      );
      expect(
        contextualTipCopy[ContextualTip.stageModifier],
        'Stage modifier. These conditions change how this mission plays.',
      );
    });
  });

  group('WavePreview.bossGroups', () {
    test('matches groups whose label is a GameBalance boss', () {
      final bossName = GameBalance.bosses.first.name;
      final preview = _preview(groups: [_group(bossName), _group('Drones')]);

      expect(preview.bossGroups.map((g) => g.label), [bossName]);
    });

    test('keeps ordinary labels out', () {
      expect(_bossPreview().bossGroups.map((g) => g.label), ['Relay Breaker']);
      expect(_preview().bossGroups, isEmpty);
    });

    test('stays in sync with the scanner-facing boss roster', () {
      // Every boss roster name must match some group label predicate-wise:
      // the scanner cards and the boss tip share this one getter, so a
      // renamed boss changes both together or neither.
      for (final boss in GameBalance.bosses) {
        final preview = _preview(groups: [_group(boss.name, count: 1)]);
        expect(preview.bossGroups, isNotEmpty, reason: boss.name);
      }
    });
  });

  group('contextualTipFor', () {
    test('resolves the boss tip for an eligible build snapshot', () {
      expect(
        contextualTipFor(_snapshot(nextWavePreview: _bossPreview()), {}),
        ContextualTip.bossWave,
      );
    });

    test('stays silent without a boss in the preview', () {
      expect(
        contextualTipFor(_snapshot(nextWavePreview: _preview()), {}),
        isNull,
      );
    });

    test('stays silent without a preview', () {
      expect(contextualTipFor(_snapshot(), {}), isNull);
    });

    test('stays silent once the boss tip was seen', () {
      expect(
        contextualTipFor(_snapshot(nextWavePreview: _bossPreview()), {
          ContextualTip.bossWave,
        }),
        isNull,
      );
    });

    test('stays silent during an active wave', () {
      expect(
        contextualTipFor(
          _snapshot(
            phase: GamePhase.wave,
            waveNumber: 8,
            nextWavePreview: _bossPreview(),
          ),
          {},
        ),
        isNull,
      );
    });

    test('stays silent while a module draft is open', () {
      expect(
        contextualTipFor(
          _snapshot(
            nextWavePreview: _bossPreview(),
            pendingRunModuleOffer: RunModuleOffer(
              offerId: 1,
              draftNumber: 1,
              draftTotal: 3,
              moduleIds: const [RunModuleId.heavyCaliber],
            ),
          ),
          {},
        ),
        isNull,
      );
    });

    test('stays silent on an ended session', () {
      for (final phase in [GamePhase.won, GamePhase.lost]) {
        expect(
          contextualTipFor(
            _snapshot(phase: phase, nextWavePreview: _bossPreview()),
            {},
          ),
          isNull,
          reason: phase.name,
        );
      }
    });

    test('requires no selected cell so the collapsed scanner is usable', () {
      // With every unlock lesson already seen, a selected cell leaves no
      // unlock candidate — and the boss tip must NOT take over, because the
      // collapsed scanner ignores taps while a cell is selected.
      final unlockLessonsSeen = contextualTipTowerTypes.keys.toSet();
      expect(
        contextualTipFor(
          _snapshot(
            nextWavePreview: _bossPreview(),
            selectedCell: const GridPosition(2, 2),
          ),
          unlockLessonsSeen,
        ),
        isNull,
      );
    });

    test('requires no selected tower so the collapsed scanner is usable', () {
      expect(
        contextualTipFor(
          _snapshot(
            nextWavePreview: _bossPreview(),
            selectedTower: const PlacedTower(
              id: 1,
              type: TowerType.laser,
              position: GridPosition(2, 2),
            ),
          ),
          {},
        ),
        isNull,
      );
    });

    test('never resolves the stage modifier tip', () {
      // The modifier tip belongs to the separate briefing route (slice 4).
      final tip = contextualTipFor(
        _snapshot(
          nextWavePreview: _bossPreview(),
          stageModifiers: const [StageModifier.shieldRecharge],
        ),
        {},
      );
      expect(tip, isNot(ContextualTip.stageModifier));
    });
  });

  group('learnedTipsIn', () {
    test('an empty board teaches nothing', () {
      expect(learnedTipsIn(_snapshot()), isEmpty);
    });

    test('each placed unlock family marks exactly its own tip', () {
      final snapshot = _snapshot(
        placedTowers: [
          _placed(TowerType.railgun, 1),
          _placed(TowerType.droneBay, 2),
        ],
      );
      expect(learnedTipsIn(snapshot), {
        ContextualTip.railgun,
        ContextualTip.droneBay,
      });
    });

    test('covers every unlock family in one board', () {
      final snapshot = _snapshot(
        placedTowers: [
          _placed(TowerType.railgun, 1),
          _placed(TowerType.ionChain, 2),
          _placed(TowerType.nanite, 3),
          _placed(TowerType.gravityWell, 4),
          _placed(TowerType.droneBay, 5),
        ],
      );
      expect(learnedTipsIn(snapshot), {
        ContextualTip.railgun,
        ContextualTip.ionChain,
        ContextualTip.nanite,
        ContextualTip.gravityWell,
        ContextualTip.droneBay,
      });
    });

    test('wave-1 families have no tips and teach nothing', () {
      final snapshot = _snapshot(
        placedTowers: [
          _placed(TowerType.laser, 1),
          _placed(TowerType.rocket, 2),
          _placed(TowerType.cryo, 3),
        ],
      );
      expect(learnedTipsIn(snapshot), isEmpty);
    });
  });

  group('unlock tips (selected-cell rail)', () {
    const cell = GridPosition(2, 2);

    test('an unlocked unseen Railgun is eligible when a buildable cell is '
        'selected', () {
      expect(
        contextualTipFor(
          _snapshot(unlockedTowerTypes: TowerType.values, selectedCell: cell),
          {},
        ),
        ContextualTip.railgun,
      );
    });

    test('multiple eligible tips resolve in unlock (enum) order', () {
      final snapshot = _snapshot(
        unlockedTowerTypes: TowerType.values,
        selectedCell: cell,
      );
      expect(contextualTipFor(snapshot, {}), ContextualTip.railgun);
      expect(
        contextualTipFor(snapshot, {ContextualTip.railgun}),
        ContextualTip.ionChain,
      );
      expect(
        contextualTipFor(snapshot, {
          ContextualTip.railgun,
          ContextualTip.ionChain,
        }),
        ContextualTip.nanite,
      );
      expect(
        contextualTipFor(snapshot, {
          ContextualTip.railgun,
          ContextualTip.ionChain,
          ContextualTip.nanite,
        }),
        ContextualTip.gravityWell,
      );
      expect(
        contextualTipFor(snapshot, {
          ContextualTip.railgun,
          ContextualTip.ionChain,
          ContextualTip.nanite,
          ContextualTip.gravityWell,
        }),
        ContextualTip.droneBay,
      );
      expect(
        contextualTipFor(snapshot, {
          ContextualTip.railgun,
          ContextualTip.ionChain,
          ContextualTip.nanite,
          ContextualTip.gravityWell,
          ContextualTip.droneBay,
        }),
        isNull,
      );
    });

    test('a locked card is skipped in favor of the next unlocked tip', () {
      // Only Drone Bay has cleared its unlock wave among the five.
      expect(
        contextualTipFor(
          _snapshot(
            unlockedTowerTypes: const [TowerType.laser, TowerType.droneBay],
            selectedCell: cell,
          ),
          {},
        ),
        ContextualTip.droneBay,
      );
    });

    test('stays silent without a selected cell', () {
      expect(
        contextualTipFor(_snapshot(unlockedTowerTypes: TowerType.values), {}),
        isNull,
      );
    });

    test('stays silent on a nonbuildable (path) selection', () {
      expect(
        contextualTipFor(
          _snapshot(
            unlockedTowerTypes: TowerType.values,
            selectedCell: cell,
            selectedCellBuildable: false,
          ),
          {},
        ),
        isNull,
      );
    });

    test('stays silent while a tower is selected', () {
      expect(
        contextualTipFor(
          _snapshot(
            unlockedTowerTypes: TowerType.values,
            selectedCell: cell,
            selectedTower: _placed(TowerType.laser, 1),
          ),
          {},
        ),
        isNull,
      );
    });

    test(
      'stays silent during an active wave, a draft, or an ended session',
      () {
        for (final (description, snapshot) in [
          (
            'wave',
            _snapshot(
              phase: GamePhase.wave,
              unlockedTowerTypes: TowerType.values,
              selectedCell: cell,
            ),
          ),
          (
            'draft',
            _snapshot(
              unlockedTowerTypes: TowerType.values,
              selectedCell: cell,
              pendingRunModuleOffer: RunModuleOffer(
                offerId: 1,
                draftNumber: 1,
                draftTotal: 3,
                moduleIds: const [RunModuleId.heavyCaliber],
              ),
            ),
          ),
          (
            'won',
            _snapshot(
              phase: GamePhase.won,
              unlockedTowerTypes: TowerType.values,
              selectedCell: cell,
            ),
          ),
          (
            'lost',
            _snapshot(
              phase: GamePhase.lost,
              unlockedTowerTypes: TowerType.values,
              selectedCell: cell,
            ),
          ),
        ]) {
          expect(contextualTipFor(snapshot, {}), isNull, reason: description);
        }
      },
    );

    test('a placed type counts as learned and suppresses its own hint', () {
      final snapshot = _snapshot(
        unlockedTowerTypes: TowerType.values,
        selectedCell: cell,
        placedTowers: [_placed(TowerType.railgun, 1)],
      );
      expect(
        contextualTipFor(snapshot, learnedTipsIn(snapshot)),
        ContextualTip.ionChain,
      );
    });

    test('boss keeps priority only when nothing is selected', () {
      // With a cell selected, unlocks are the candidates — even an unseen
      // boss stays silent because the scanner is unusable then.
      final cellSelected = _snapshot(
        unlockedTowerTypes: TowerType.values,
        selectedCell: cell,
        nextWavePreview: _bossPreview(),
      );
      expect(contextualTipFor(cellSelected, {}), ContextualTip.railgun);

      // Nothing selected: boss leads, exactly as before.
      final idle = _snapshot(
        unlockedTowerTypes: TowerType.values,
        nextWavePreview: _bossPreview(),
      );
      expect(contextualTipFor(idle, {}), ContextualTip.bossWave);
    });
  });
}
