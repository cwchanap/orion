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
  int gold = 150,
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
    gold: gold,
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
    test('returns copy for every tip', () {
      // The function is an exhaustive switch over the enum: a tip without
      // copy fails to compile, so this loop can only drift on a rename.
      for (final tip in ContextualTip.values) {
        expect(contextualTipCopy(tip), isNotEmpty, reason: tip.name);
      }
    });

    test('carries the exact design copy verbatim', () {
      expect(
        contextualTipCopy(ContextualTip.bossWave),
        'Boss ahead. Check the scanner and prepare your defense.',
      );
      expect(
        contextualTipCopy(ContextualTip.railgun),
        'Railgun unlocked. Pierces enemies in a line.',
      );
      expect(
        contextualTipCopy(ContextualTip.ionChain),
        'Ion Chain unlocked. Lightning jumps between targets.',
      );
      expect(
        contextualTipCopy(ContextualTip.nanite),
        'Nanite unlocked. Corrodes armor to help other towers.',
      );
      expect(
        contextualTipCopy(ContextualTip.gravityWell),
        'Gravity Well unlocked. Damages enemies within its field.',
      );
      expect(
        contextualTipCopy(ContextualTip.droneBay),
        'Drone Bay unlocked. Launches autonomous interceptors.',
      );
      expect(
        contextualTipCopy(ContextualTip.specialization),
        'Specialization ready. Choose one of two ways to evolve this tower.',
      );
      expect(
        contextualTipCopy(ContextualTip.targeting),
        'Targeting modes. Choose which enemies this tower attacks first.',
      );
      expect(
        contextualTipCopy(ContextualTip.stageModifier),
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
      // Slice 3: a selected level-1 tower now legitimately yields the
      // targeting tip — but never the boss tip, whose scanner anchor is
      // collapsed and tap-ignored while any selection is active.
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
          {ContextualTip.targeting},
        ),
        isNull,
      );
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
        isNot(ContextualTip.bossWave),
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

    test('a specialized tower marks specialization learned', () {
      final snapshot = _snapshot(
        placedTowers: [
          PlacedTower(
            id: 1,
            type: TowerType.laser,
            position: const GridPosition(2, 5),
            level: 3,
            specialization: GameBalance.specializationsFor(
              TowerType.laser,
            ).first,
          ),
        ],
      );
      expect(learnedTipsIn(snapshot), {ContextualTip.specialization});
    });

    test('a nondefault targeting mode marks targeting learned', () {
      final snapshot = _snapshot(
        placedTowers: [
          PlacedTower(
            id: 1,
            type: TowerType.laser,
            position: const GridPosition(2, 5),
            targetingMode: TowerTargetingMode.strongest,
          ),
        ],
      );
      expect(learnedTipsIn(snapshot), {ContextualTip.targeting});
    });

    test('default towers teach neither specialization nor targeting', () {
      final snapshot = _snapshot(
        placedTowers: [
          _placed(TowerType.laser, 1),
          PlacedTower(
            id: 2,
            type: TowerType.rocket,
            position: const GridPosition(4, 5),
            level: 2,
          ),
        ],
      );
      expect(
        learnedTipsIn(snapshot),
        isNot(contains(ContextualTip.specialization)),
      );
      expect(learnedTipsIn(snapshot), isNot(contains(ContextualTip.targeting)));
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
      // A selected tower replaces the rail with its radial, so no unlock
      // card can be the candidate. (Slice 3's targeting tip may resolve in
      // that state; marking it seen isolates the unlock question here.)
      expect(
        contextualTipFor(
          _snapshot(
            unlockedTowerTypes: TowerType.values,
            selectedCell: cell,
            selectedTower: _placed(TowerType.laser, 1),
          ),
          {ContextualTip.targeting},
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

  group('specialization tip', () {
    final level2 = PlacedTower(
      id: 1,
      type: TowerType.laser,
      position: const GridPosition(2, 5),
      level: 2,
    );

    test('nothing selected: aims at a placed level-2 unspecialized tower', () {
      expect(
        contextualTipFor(
          _snapshot(placedTowers: [level2, _placed(TowerType.rocket, 2)]),
          {},
        ),
        ContextualTip.specialization,
      );
    });

    test('nothing selected: the boss still outranks specialization', () {
      final snapshot = _snapshot(
        nextWavePreview: _bossPreview(),
        placedTowers: [level2],
      );
      expect(contextualTipFor(snapshot, {}), ContextualTip.bossWave);
      // Once the boss lesson is seen, the same board yields specialization.
      expect(
        contextualTipFor(snapshot, {ContextualTip.bossWave}),
        ContextualTip.specialization,
      );
    });

    test('nothing selected: stays silent without a qualifying tower', () {
      // Only level-1 and level-3 towers: nothing left to specialize.
      final specialized = PlacedTower(
        id: 3,
        type: TowerType.laser,
        position: const GridPosition(4, 5),
        level: 3,
        specialization: GameBalance.specializationsFor(TowerType.laser).first,
      );
      expect(
        contextualTipFor(
          _snapshot(placedTowers: [_placed(TowerType.laser, 1), specialized]),
          {},
        ),
        isNull,
      );
    });

    test('nothing selected: stays silent once specialization is seen', () {
      expect(
        contextualTipFor(_snapshot(placedTowers: [level2]), {
          ContextualTip.specialization,
        }),
        isNull,
      );
    });

    test('nothing selected: an unaffordable level-2 tower is skipped', () {
      // Railgun specialization costs 210 — more than the 150 gold on
      // hand — so every inspector option would be disabled. The tip stays
      // silent until the action is actually usable, exactly like the
      // HPA-412 upgrade tip's gold check.
      final pricey = PlacedTower(
        id: 1,
        type: TowerType.railgun,
        position: const GridPosition(2, 5),
        level: 2,
      );
      expect(contextualTipFor(_snapshot(placedTowers: [pricey]), {}), isNull);
      expect(
        contextualTipFor(_snapshot(gold: 300, placedTowers: [pricey]), {}),
        ContextualTip.specialization,
      );
    });

    test('nothing selected: the candidate is the first affordable tower', () {
      // 150 covers laser's 120 but not railgun's 210: the board-cell
      // anchor must aim at the laser — the tower the player can actually
      // specialize — not the earlier railgun on the board.
      final pricey = PlacedTower(
        id: 1,
        type: TowerType.railgun,
        position: const GridPosition(2, 5),
        level: 2,
      );
      final cheap = PlacedTower(
        id: 2,
        type: TowerType.laser,
        position: const GridPosition(4, 5),
        level: 2,
      );
      final candidate = specializationCandidateIn(
        _snapshot(placedTowers: [pricey, cheap]),
      );
      expect(candidate?.id, cheap.id);
    });

    test('selected tower: unaffordable specialization yields to targeting', () {
      // The radial's Specialize action would open a dead inspector, so
      // the tip falls through to targeting for this snapshot and comes
      // back once gold covers the cost.
      final pricey = PlacedTower(
        id: 1,
        type: TowerType.railgun,
        position: const GridPosition(2, 5),
        level: 2,
      );
      final selected = _snapshot(
        placedTowers: [pricey],
        selectedCell: pricey.position,
        selectedTower: pricey,
      );
      expect(contextualTipFor(selected, {}), ContextualTip.targeting);
      expect(
        contextualTipFor(
          _snapshot(
            gold: 300,
            placedTowers: [pricey],
            selectedCell: pricey.position,
            selectedTower: pricey,
          ),
          {},
        ),
        ContextualTip.specialization,
      );
    });

    test('the selected tower itself eligible: resolves specialization', () {
      // Selecting the level-2 tower keeps the tip, now anchored at its own
      // radial progression button.
      final snapshot = _snapshot(
        placedTowers: [level2],
        selectedCell: level2.position,
        selectedTower: level2,
      );
      expect(contextualTipFor(snapshot, {}), ContextualTip.specialization);
    });

    test(
      'a different level-1 tower selected never inherits specialization',
      () {
        // The board has a level-2 tower, but the SELECTED tower cannot
        // specialize: aiming at its Upgrade button would teach the wrong
        // control, so the resolver yields to targeting instead.
        final other = _placed(TowerType.rocket, 2);
        final snapshot = _snapshot(
          placedTowers: [level2, other],
          selectedCell: other.position,
          selectedTower: other,
        );
        expect(contextualTipFor(snapshot, {}), ContextualTip.targeting);
        // And once targeting is seen too, silence — still no specialization.
        expect(contextualTipFor(snapshot, {ContextualTip.targeting}), isNull);
      },
    );

    test('a nonbuildable path-cell selection stays silent', () {
      expect(
        contextualTipFor(
          _snapshot(
            placedTowers: [level2],
            selectedCell: const GridPosition(2, 1),
            selectedCellBuildable: false,
          ),
          {},
        ),
        isNull,
      );
    });

    test('suppressed during combat, a draft, and ended sessions', () {
      for (final (description, snapshot) in [
        (
          'wave',
          _snapshot(
            phase: GamePhase.wave,
            placedTowers: [level2],
            selectedCell: level2.position,
            selectedTower: level2,
          ),
        ),
        (
          'draft',
          _snapshot(
            placedTowers: [level2],
            selectedCell: level2.position,
            selectedTower: level2,
            pendingRunModuleOffer: RunModuleOffer(
              offerId: 1,
              draftNumber: 1,
              draftTotal: 3,
              moduleIds: const [RunModuleId.heavyCaliber],
            ),
          ),
        ),
        ('won', _snapshot(phase: GamePhase.won, placedTowers: [level2])),
        ('lost', _snapshot(phase: GamePhase.lost, placedTowers: [level2])),
      ]) {
        expect(contextualTipFor(snapshot, {}), isNull, reason: description);
      }
    });
  });

  group('targeting tip', () {
    test('a selected level-1 tower resolves targeting', () {
      final tower = _placed(TowerType.laser, 1);
      final snapshot = _snapshot(
        placedTowers: [tower],
        selectedCell: tower.position,
        selectedTower: tower,
      );
      expect(contextualTipFor(snapshot, {}), ContextualTip.targeting);
    });

    test('a selected specialized (level-3) tower resolves targeting', () {
      final tower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: const GridPosition(2, 5),
        level: 3,
        specialization: GameBalance.specializationsFor(TowerType.laser).first,
      );
      final snapshot = _snapshot(
        placedTowers: [tower],
        selectedCell: tower.position,
        selectedTower: tower,
      );
      expect(contextualTipFor(snapshot, {}), ContextualTip.targeting);
    });

    test('a selected level-2 tower whose specialization was seen yields to '
        'targeting', () {
      final tower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: const GridPosition(2, 5),
        level: 2,
      );
      final snapshot = _snapshot(
        placedTowers: [tower],
        selectedCell: tower.position,
        selectedTower: tower,
      );
      expect(
        contextualTipFor(snapshot, {ContextualTip.specialization}),
        ContextualTip.targeting,
      );
    });

    test('specialization keeps priority over targeting for its own tower', () {
      final tower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: const GridPosition(2, 5),
        level: 2,
      );
      final snapshot = _snapshot(
        placedTowers: [tower],
        selectedCell: tower.position,
        selectedTower: tower,
      );
      expect(contextualTipFor(snapshot, {}), ContextualTip.specialization);
    });

    test('stays silent once targeting is seen', () {
      final tower = _placed(TowerType.laser, 1);
      final snapshot = _snapshot(
        placedTowers: [tower],
        selectedCell: tower.position,
        selectedTower: tower,
      );
      expect(contextualTipFor(snapshot, {ContextualTip.targeting}), isNull);
    });

    test('suppressed during combat, a draft, and ended sessions', () {
      final tower = _placed(TowerType.laser, 1);
      for (final (description, snapshot) in [
        (
          'wave',
          _snapshot(
            phase: GamePhase.wave,
            placedTowers: [tower],
            selectedCell: tower.position,
            selectedTower: tower,
          ),
        ),
        (
          'draft',
          _snapshot(
            placedTowers: [tower],
            selectedCell: tower.position,
            selectedTower: tower,
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
            placedTowers: [tower],
            selectedCell: tower.position,
            selectedTower: tower,
          ),
        ),
        (
          'lost',
          _snapshot(
            phase: GamePhase.lost,
            placedTowers: [tower],
            selectedCell: tower.position,
            selectedTower: tower,
          ),
        ),
      ]) {
        expect(contextualTipFor(snapshot, {}), isNull, reason: description);
      }
    });

    test('nothing selected never resolves targeting', () {
      // The radial targeting button only exists while a tower is selected.
      final tower = _placed(TowerType.laser, 1);
      expect(contextualTipFor(_snapshot(placedTowers: [tower]), {}), isNull);
    });
  });

  group('specializationCandidateIn', () {
    test('returns the first placed level-2 unspecialized tower', () {
      final first = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: const GridPosition(2, 5),
        level: 2,
      );
      final second = PlacedTower(
        id: 2,
        type: TowerType.rocket,
        position: const GridPosition(4, 5),
        level: 2,
      );
      final snapshot = _snapshot(
        placedTowers: [_placed(TowerType.cryo, 3), first, second],
      );
      expect(specializationCandidateIn(snapshot), same(first));
    });

    test('is null when no placed tower can specialize', () {
      final specialized = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: const GridPosition(2, 5),
        level: 3,
        specialization: GameBalance.specializationsFor(TowerType.laser).first,
      );
      expect(
        specializationCandidateIn(
          _snapshot(placedTowers: [_placed(TowerType.laser, 2), specialized]),
        ),
        isNull,
      );
    });
  });
}
