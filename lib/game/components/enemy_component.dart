import 'dart:ui';

import 'package:flame/components.dart';

import '../assets/game_boss_sheet.dart';
import '../assets/game_sprite_sheet.dart';
import '../assets/game_tower_variety_sheet.dart';
import '../models/game_models.dart';
import '../rules/enemy_logic.dart';
import '../rules/enemy_overlay_state.dart';
import '../rules/tower_targeting.dart';
import 'enemy_overlay.dart';

typedef EnemyKilledCallback = void Function(EnemyComponent enemy);
typedef EnemyReachedBaseCallback = void Function(EnemyComponent enemy);

class EnemyComponent extends CircleComponent {
  EnemyComponent({
    required this.enemyId,
    required this.stats,
    required this.logic,
    required this.onKilled,
    required this.onReachedBase,
    this.spriteSheet,
    this.towerVarietySheet,
    this.bossSheet,
    this.minionOf,
    this.onSummonMinionsFn,
    double radius = 11,
    super.priority,
  }) : super(
         radius: radius,
         anchor: Anchor.center,
         position: Vector2(logic.position.dx, logic.position.dy),
         paint: Paint()..color = const Color(0xFFE35D6A),
       );

  final int enemyId;
  final EnemyStats stats;
  final EnemyLogic logic;
  final EnemyKilledCallback onKilled;
  final EnemyReachedBaseCallback onReachedBase;
  final GameSpriteSheet? spriteSheet;
  final GameTowerVarietySheet? towerVarietySheet;
  final GameBossSheet? bossSheet;
  final int? minionOf;
  final void Function(EnemyComponent source, int count)? onSummonMinionsFn;

  bool _isInspected = false;
  bool _resolutionDispatched = false;
  EnemyOverlayState? _cachedOverlayState;
  bool _overlayDirty = true;

  static final EnemyOverlayRenderer _overlayRenderer = EnemyOverlayRenderer();

  // read-through getters to logic
  double get health => logic.health;
  double get shield => logic.shield;
  double get maxHealth => logic.maxHealth;
  bool get isAlive => logic.isAlive;
  bool get isResolved => logic.isResolved;
  bool get isInspected => _isInspected;
  bool get isCorroded => logic.isCorroded;
  bool get isSlowed => logic.isSlowed;
  double get armorReduction => logic.armorReduction;
  double get pathProgress => logic.pathProgress;

  EnemyOverlayState get overlayState {
    final cached = _cachedOverlayState;
    if (cached != null && !_overlayDirty) {
      return cached;
    }
    final state = EnemyOverlayState.fromData(
      EnemyOverlayData(
        isResolved: isResolved,
        isInspected: isInspected,
        health: health,
        maxHealth: maxHealth,
        shield: shield,
        maxShield: stats.shieldHealth,
        traits: stats.traits,
        isSlowed: isSlowed,
        isCorroded: isCorroded,
        isBoss: stats is BossDefinition,
      ),
    );
    _cachedOverlayState = state;
    _overlayDirty = false;
    return state;
  }

  void setInspected(bool value) {
    if (_isInspected == value) return;
    _isInspected = value;
    _overlayDirty = true;
  }

  void applyDamage(
    double amount, {
    double shieldDamageMultiplier = 1,
    double armorDamageMultiplier = 1,
    double armorShred = 0,
    bool bypassArmor = false,
  }) {
    if (!isAlive || amount <= 0) return;
    final outcome = logic.applyDamage(
      amount,
      shieldDamageMultiplier: shieldDamageMultiplier,
      armorDamageMultiplier: armorDamageMultiplier,
      armorShred: armorShred,
      bypassArmor: bypassArmor,
    );
    _overlayDirty = true;
    if (outcome.died) _resolve(onKilled);
  }

  void applySlow({required double multiplier, required double duration}) {
    if (!isAlive) return;
    logic.applySlow(multiplier: multiplier, duration: duration);
    _overlayDirty = true;
  }

  void applyCorrosion({
    required double damagePerSecond,
    required double duration,
    required double armorShred,
  }) {
    if (!isAlive) return;
    logic.applyCorrosion(
      damagePerSecond: damagePerSecond,
      duration: duration,
      armorShred: armorShred,
    );
    _overlayDirty = true;
  }

  // NOTE: logic.residualWaypointsFromHere() already returns [position, ...rest],
  // so we convert without re-prepending the component position (Correction 1).
  List<Vector2> residualWaypointsFromHere() => logic
      .residualWaypointsFromHere()
      .map((o) => Vector2(o.dx, o.dy))
      .toList();

  TargetCandidate get targetCandidate => TargetCandidate(
    id: enemyId,
    x: position.x,
    y: position.y,
    pathProgress: pathProgress,
    isAlive: isAlive,
    currentHealth: health,
    currentShield: shield,
    isShielded: stats.traits.contains(EnemyTrait.shielded),
    isArmored: stats.traits.contains(EnemyTrait.armored),
  );

  void resolveKilled() => _resolve(onKilled);
  void resolveReachedBase() => _resolve(onReachedBase);

  void _resolve(void Function(EnemyComponent enemy) callback) {
    if (_resolutionDispatched) return;
    _resolutionDispatched = true;
    _overlayDirty = true;
    callback(this);
    removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final bossDef = stats is BossDefinition ? stats as BossDefinition : null;
    if (bossDef != null && bossSheet != null) {
      bossSheet!
          .sprite(bossDef.sprite)
          .render(
            canvas,
            position: Vector2(radius, radius),
            size: Vector2.all(radius * 2.4),
            anchor: Anchor.center,
          );
    } else if (spriteSheet != null) {
      spriteSheet!
          .sprite(GameSpriteSheet.spriteForEnemy(stats))
          .render(
            canvas,
            position: Vector2(radius, radius),
            size: Vector2.all(radius * 2.4),
            anchor: Anchor.center,
          );
    } else {
      super.render(canvas);
    }

    _overlayRenderer.render(
      canvas,
      state: overlayState,
      radius: radius,
      towerVarietySheet: towerVarietySheet,
      name: bossDef?.name,
    );
  }

  // temporary (removed in Task 7): component still ticks during super.update
  @override
  void update(double dt) {
    super.update(dt);
    if (!isAlive) return;
    final result = logic.tick(dt); // dt is already Flame-time-scaled
    position.setValues(logic.position.dx, logic.position.dy);
    if (result.overlayDirty) _overlayDirty = true;
    if (result.reachedBase) {
      resolveReachedBase();
    } else if (result.diedByCorrosion) {
      resolveKilled();
    } else {
      final bossDef = stats is BossDefinition ? stats as BossDefinition : null;
      final mechanic = bossDef?.summonMechanic;
      if (mechanic != null) {
        for (var i = 0; i < result.summonsDue; i++) {
          onSummonMinionsFn?.call(this, mechanic.count);
        }
      }
    }
  }
}
