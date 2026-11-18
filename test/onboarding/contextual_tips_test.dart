import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/onboarding/contextual_tips.dart';

WavePreviewGroup _group(String label, {int count = 8}) =>
    WavePreviewGroup(enemyCount: count, label: label, traits: const {});

WavePreview _preview({int waveNumber = 7, List<WavePreviewGroup>? groups}) {
  return WavePreview(
    waveNumber: waveNumber,
    missionWaveTotal: 8,
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
  List<Character> squad = const [
    Character.haruto,
    Character.elena,
    Character.kaito,
    Character.shiori,
    Character.ren,
    Character.tetsuo,
  ],
}) {
  return GameSnapshot(
    phase: phase,
    gold: gold,
    baseHealth: 20,
    startingBaseHealth: 20,
    waveNumber: waveNumber,
    missionWaveTotal: 8,
    wavesCleared: 0,
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
    squad: squad,
  );
}

PlacedTower _placed(Character member, int id) =>
    PlacedTower(id: id, character: member, position: GridPosition(2, 2 + id));

void main() {
  group('ContextualTip enum', () {
    test('declares the four tips in resolver priority order', () {
      // HPA-922 deleted the five wave-unlock tips; the roster's squad
      // membership already teaches what each member fields.
      expect(ContextualTip.values.map((tip) => tip.name), [
        'bossWave',
        'signature',
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
        contextualTipCopy(ContextualTip.signature),
        'Signature ready. Upgrade this member to tier 3 to apply it.',
      );
      expect(
        contextualTipCopy(ContextualTip.targeting),
        'Targeting modes. Choose which enemies this member attacks first.',
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
      // No tip may take over while a cell is selected — the boss tip's
      // scanner anchor is collapsed and tap-ignored in that state.
      expect(
        contextualTipFor(
          _snapshot(
            nextWavePreview: _bossPreview(),
            selectedCell: const GridPosition(2, 2),
          ),
          {},
        ),
        isNull,
      );
    });

    test('requires no selected tower so the collapsed scanner is usable', () {
      // A selected level-1 member legitimately yields the targeting tip —
      // but never the boss tip, whose scanner anchor is collapsed and
      // tap-ignored while any selection is active.
      expect(
        contextualTipFor(
          _snapshot(
            nextWavePreview: _bossPreview(),
            selectedTower: const PlacedTower(
              id: 1,
              character: Character.haruto,
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
              character: Character.haruto,
              position: GridPosition(2, 2),
            ),
          ),
          {},
        ),
        isNot(ContextualTip.bossWave),
      );
    });

    test('never resolves the stage modifier tip', () {
      // The modifier tip belongs to the separate briefing route.
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

    test('placed members alone teach nothing', () {
      // Deployment is normal play, not a lesson: only reaching tier 3 or
      // changing a targeting mode demonstrates the remaining tips.
      final snapshot = _snapshot(
        placedTowers: [
          _placed(Character.elena, 1),
          _placed(Character.tetsuo, 2),
          _placed(Character.haruto, 3),
        ],
      );
      expect(learnedTipsIn(snapshot), isEmpty);
    });

    test('a tier-3 member marks signature learned', () {
      final snapshot = _snapshot(
        placedTowers: [
          PlacedTower(
            id: 1,
            character: Character.haruto,
            position: const GridPosition(2, 5),
            level: 3,
          ),
        ],
      );
      expect(learnedTipsIn(snapshot), {ContextualTip.signature});
    });

    test('a nondefault targeting mode marks targeting learned', () {
      final snapshot = _snapshot(
        placedTowers: [
          PlacedTower(
            id: 1,
            character: Character.haruto,
            position: const GridPosition(2, 5),
            targetingMode: TowerTargetingMode.strongest,
          ),
        ],
      );
      expect(learnedTipsIn(snapshot), {ContextualTip.targeting});
    });

    test('default members teach neither signature nor targeting', () {
      final snapshot = _snapshot(
        placedTowers: [
          _placed(Character.haruto, 1),
          PlacedTower(
            id: 2,
            character: Character.mio,
            position: const GridPosition(4, 5),
            level: 2,
          ),
        ],
      );
      expect(learnedTipsIn(snapshot), isNot(contains(ContextualTip.signature)));
      expect(learnedTipsIn(snapshot), isNot(contains(ContextualTip.targeting)));
    });
  });

  group('selected-cell silence', () {
    const cell = GridPosition(2, 2);

    test('a buildable selected cell resolves no tip', () {
      // HPA-922: the rail shows squad members the player already owns, so
      // there is nothing left to teach there — not even when an unseen
      // boss waits in the preview.
      expect(contextualTipFor(_snapshot(selectedCell: cell), {}), isNull);
      expect(
        contextualTipFor(
          _snapshot(selectedCell: cell, nextWavePreview: _bossPreview()),
          {},
        ),
        isNull,
      );
    });

    test('a nonbuildable (path) selection stays silent', () {
      expect(
        contextualTipFor(
          _snapshot(selectedCell: cell, selectedCellBuildable: false),
          {},
        ),
        isNull,
      );
    });

    test('a cell selection during a wave, draft or ended session stays '
        'silent', () {
      for (final (description, snapshot) in [
        ('wave', _snapshot(phase: GamePhase.wave, selectedCell: cell)),
        (
          'draft',
          _snapshot(
            selectedCell: cell,
            pendingRunModuleOffer: RunModuleOffer(
              offerId: 1,
              draftNumber: 1,
              draftTotal: 3,
              moduleIds: const [RunModuleId.heavyCaliber],
            ),
          ),
        ),
        ('won', _snapshot(phase: GamePhase.won, selectedCell: cell)),
        ('lost', _snapshot(phase: GamePhase.lost, selectedCell: cell)),
      ]) {
        expect(contextualTipFor(snapshot, {}), isNull, reason: description);
      }
    });
  });

  group('signature tip', () {
    final level2 = PlacedTower(
      id: 1,
      character: Character.haruto,
      position: const GridPosition(2, 5),
      level: 2,
    );

    test('nothing selected: aims at a placed level-2 member', () {
      expect(
        contextualTipFor(
          _snapshot(placedTowers: [level2, _placed(Character.mio, 2)]),
          {},
        ),
        ContextualTip.signature,
      );
    });

    test('nothing selected: the boss still outranks signature', () {
      final snapshot = _snapshot(
        nextWavePreview: _bossPreview(),
        placedTowers: [level2],
      );
      expect(contextualTipFor(snapshot, {}), ContextualTip.bossWave);
      // Once the boss lesson is seen, the same board yields signature.
      expect(
        contextualTipFor(snapshot, {ContextualTip.bossWave}),
        ContextualTip.signature,
      );
    });

    test('nothing selected: stays silent without a qualifying member', () {
      // Only tier-1 and tier-3 members: no signature step left to teach.
      final tier3 = PlacedTower(
        id: 3,
        character: Character.haruto,
        position: const GridPosition(4, 5),
        level: 3,
      );
      expect(
        contextualTipFor(
          _snapshot(placedTowers: [_placed(Character.haruto, 1), tier3]),
          {},
        ),
        isNull,
      );
    });

    test('nothing selected: stays silent once signature is seen', () {
      expect(
        contextualTipFor(_snapshot(placedTowers: [level2]), {
          ContextualTip.signature,
        }),
        isNull,
      );
    });

    test('nothing selected: an unaffordable tier-2 member is skipped', () {
      // Elena's signature costs 210 — more than the 150 gold on hand — so
      // every inspector option would be disabled. The tip stays silent
      // until the action is actually usable, exactly like the HPA-412
      // upgrade tip's gold check.
      final pricey = PlacedTower(
        id: 1,
        character: Character.elena,
        position: const GridPosition(2, 5),
        level: 2,
      );
      expect(contextualTipFor(_snapshot(placedTowers: [pricey]), {}), isNull);
      expect(
        contextualTipFor(_snapshot(gold: 300, placedTowers: [pricey]), {}),
        ContextualTip.signature,
      );
    });

    test('nothing selected: the candidate is the first affordable member', () {
      // 150 covers Haruto's 120 but not Elena's 210: the board-cell anchor
      // must aim at Haruto — the member the player can actually upgrade —
      // not the earlier railgun member on the board.
      final pricey = PlacedTower(
        id: 1,
        character: Character.elena,
        position: const GridPosition(2, 5),
        level: 2,
      );
      final cheap = PlacedTower(
        id: 2,
        character: Character.haruto,
        position: const GridPosition(4, 5),
        level: 2,
      );
      final candidate = signatureCandidateIn(
        _snapshot(placedTowers: [pricey, cheap]),
      );
      expect(candidate?.id, cheap.id);
    });

    test('selected member: unaffordable signature yields to targeting', () {
      // The radial's signature action would open a dead inspector, so the
      // tip falls through to targeting for this snapshot and comes back
      // once gold covers the cost.
      final pricey = PlacedTower(
        id: 1,
        character: Character.elena,
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
        ContextualTip.signature,
      );
    });

    test('the selected member itself eligible: resolves signature', () {
      // Selecting the tier-2 member keeps the tip, now anchored at its own
      // radial progression button.
      final snapshot = _snapshot(
        placedTowers: [level2],
        selectedCell: level2.position,
        selectedTower: level2,
      );
      expect(contextualTipFor(snapshot, {}), ContextualTip.signature);
    });

    test('a different tier-1 member selected never inherits signature', () {
      // The board has a tier-2 member, but the SELECTED member cannot
      // take the signature step: aiming at its Upgrade button would teach
      // the wrong control, so the resolver yields to targeting instead.
      final other = _placed(Character.mio, 2);
      final snapshot = _snapshot(
        placedTowers: [level2, other],
        selectedCell: other.position,
        selectedTower: other,
      );
      expect(contextualTipFor(snapshot, {}), ContextualTip.targeting);
      // And once targeting is seen too, silence — still no signature.
      expect(contextualTipFor(snapshot, {ContextualTip.targeting}), isNull);
    });

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
    test('a selected tier-1 member resolves targeting', () {
      final tower = _placed(Character.haruto, 1);
      final snapshot = _snapshot(
        placedTowers: [tower],
        selectedCell: tower.position,
        selectedTower: tower,
      );
      expect(contextualTipFor(snapshot, {}), ContextualTip.targeting);
    });

    test('a selected tier-3 member resolves targeting', () {
      final tower = PlacedTower(
        id: 1,
        character: Character.haruto,
        position: const GridPosition(2, 5),
        level: 3,
      );
      final snapshot = _snapshot(
        placedTowers: [tower],
        selectedCell: tower.position,
        selectedTower: tower,
      );
      expect(contextualTipFor(snapshot, {}), ContextualTip.targeting);
    });

    test('a selected tier-2 member whose signature was seen yields to '
        'targeting', () {
      final tower = PlacedTower(
        id: 1,
        character: Character.haruto,
        position: const GridPosition(2, 5),
        level: 2,
      );
      final snapshot = _snapshot(
        placedTowers: [tower],
        selectedCell: tower.position,
        selectedTower: tower,
      );
      expect(
        contextualTipFor(snapshot, {ContextualTip.signature}),
        ContextualTip.targeting,
      );
    });

    test('signature keeps priority over targeting for its own member', () {
      final tower = PlacedTower(
        id: 1,
        character: Character.haruto,
        position: const GridPosition(2, 5),
        level: 2,
      );
      final snapshot = _snapshot(
        placedTowers: [tower],
        selectedCell: tower.position,
        selectedTower: tower,
      );
      expect(contextualTipFor(snapshot, {}), ContextualTip.signature);
    });

    test('stays silent once targeting is seen', () {
      final tower = _placed(Character.haruto, 1);
      final snapshot = _snapshot(
        placedTowers: [tower],
        selectedCell: tower.position,
        selectedTower: tower,
      );
      expect(contextualTipFor(snapshot, {ContextualTip.targeting}), isNull);
    });

    test('suppressed during combat, a draft, and ended sessions', () {
      final tower = _placed(Character.haruto, 1);
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
      // The radial targeting button only exists while a member is selected.
      final tower = _placed(Character.haruto, 1);
      expect(contextualTipFor(_snapshot(placedTowers: [tower]), {}), isNull);
    });
  });

  group('signatureCandidateIn', () {
    test('returns the first placed level-2 member', () {
      final first = PlacedTower(
        id: 1,
        character: Character.haruto,
        position: const GridPosition(2, 5),
        level: 2,
      );
      final second = PlacedTower(
        id: 2,
        character: Character.mio,
        position: const GridPosition(4, 5),
        level: 2,
      );
      final snapshot = _snapshot(
        placedTowers: [_placed(Character.jin, 3), first, second],
      );
      expect(signatureCandidateIn(snapshot), same(first));
    });

    test('is null when no placed member can take the signature step', () {
      final tier3 = PlacedTower(
        id: 1,
        character: Character.haruto,
        position: const GridPosition(2, 5),
        level: 3,
      );
      expect(
        signatureCandidateIn(
          _snapshot(placedTowers: [_placed(Character.haruto, 2), tier3]),
        ),
        isNull,
      );
    });
  });
}
