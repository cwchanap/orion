import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import 'combat_colors.dart';

/// Kind of transient combat feedback cue.
enum CombatFeedbackKind { splash, chain, pierce, enemyDestroyed, coreImpact }

/// Callback contract for handing a resolved feedback cue to its owner.
typedef CombatFeedbackCallback =
    void Function(CombatFeedbackComponent feedback);

/// Presentation-only combat feedback drawn from already-resolved geometry.
///
/// The component never owns enemy references, target selectors, or damage
/// logic; callers pass it positions captured during the existing damage
/// loops. The private constructor clones whatever it stores, so callers may
/// hand over live vectors (the pierce, kill, and leak cues do; splash and
/// chain clone on their side). Rendering is stationary Canvas primitives
/// with opacity decay only — no travelling particles or animation state
/// machine. Paints and static paths are built once and reused across frames;
/// only the alpha-dependent color is refreshed per render.
class CombatFeedbackComponent extends Component {
  CombatFeedbackComponent.splash({
    required Vector2 origin,
    required double radius,
    required List<Vector2> positions,
    required Color color,
  }) : this._(
         kind: CombatFeedbackKind.splash,
         origin: origin,
         radius: radius,
         positions: positions,
         color: color,
         lifetime: _splashLifetime,
       );

  CombatFeedbackComponent.chain({
    required List<Vector2> positions,
    required Color color,
  }) : this._(
         kind: CombatFeedbackKind.chain,
         origin: positions.isEmpty ? Vector2.zero() : positions.first,
         radius: 0,
         positions: positions,
         color: color,
         lifetime: _chainLifetime,
       );

  CombatFeedbackComponent.pierce({
    required Vector2 origin,
    required Vector2 beamTarget,
    required List<Vector2> positions,
    required Color color,
  }) : this._(
         kind: CombatFeedbackKind.pierce,
         origin: origin,
         beamTarget: beamTarget,
         radius: 0,
         positions: positions,
         color: color,
         lifetime: _pierceLifetime,
       );

  CombatFeedbackComponent.enemyDestroyed({
    required Vector2 origin,
    required double radius,
  }) : this._(
         kind: CombatFeedbackKind.enemyDestroyed,
         origin: origin,
         radius: radius,
         positions: const [],
         color: CombatColors.enemyBody,
         lifetime: _destroyedLifetime,
       );

  CombatFeedbackComponent.coreImpact({
    required Vector2 origin,
    required double radius,
  }) : this._(
         kind: CombatFeedbackKind.coreImpact,
         origin: origin,
         radius: radius,
         positions: const [],
         color: CombatColors.shield,
         lifetime: _coreImpactLifetime,
       );

  // Only the private constructor clones its inputs; the public constructors
  // hand vectors straight through so the component always owns its own
  // copies. Splash and chain callers already clone on their side; pierce and
  // the kill/leak cues pass live vectors.
  CombatFeedbackComponent._({
    required this.kind,
    required Vector2 origin,
    Vector2? beamTarget,
    required double radius,
    required List<Vector2> positions,
    required Color color,
    required double lifetime,
  }) : _origin = origin.clone(),
       _beamTarget = (beamTarget ?? origin).clone(),
       // These three would be initializing formals if the field names matched
       // the public parameter names; they don't, so silence the lint here.
       // ignore: prefer_initializing_formals
       _radius = radius,
       _positions = List.unmodifiable(positions.map((p) => p.clone())),
       // ignore: prefer_initializing_formals
       _color = color,
       // ignore: prefer_initializing_formals
       _lifetime = lifetime,
       super(
         priority:
             kind == CombatFeedbackKind.splash ||
                 kind == CombatFeedbackKind.chain ||
                 kind == CombatFeedbackKind.pierce
             ? _liveCuePriority
             : _resolutionCuePriority,
       ) {
    switch (kind) {
      case CombatFeedbackKind.splash:
        _strokePaint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
      case CombatFeedbackKind.chain:
      case CombatFeedbackKind.pierce:
        _strokePaint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
      case CombatFeedbackKind.enemyDestroyed:
        _strokePaint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
      case CombatFeedbackKind.coreImpact:
        _strokePaint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5;
        // Doubles as the diamond-mark paint below.
        _accentPaint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round;
    }
  }

  static const int _liveCuePriority = 26;
  static const int _resolutionCuePriority = 15;
  static const double _splashLifetime = 0.45;
  static const double _chainLifetime = 0.4;
  static const double _pierceLifetime = 0.35;
  static const double _destroyedLifetime = 0.5;
  static const double _coreImpactLifetime = 0.6;
  static const double _pierceBeamOvershoot = 8;

  final CombatFeedbackKind kind;
  final Vector2 _origin;
  final Vector2 _beamTarget;
  final double _radius;
  final List<Vector2> _positions;
  final Color _color;
  final double _lifetime;

  // Reused every frame; only the alpha-dependent color changes per render.
  final Paint _strokePaint = Paint()..isAntiAlias = true;
  final Paint _accentPaint = Paint()..isAntiAlias = true;

  double _elapsed = 0;
  bool _hasRendered = false;

  /// Splash center, first chain point, firing origin, or resolution center.
  /// Returns a defensive copy.
  Vector2 get origin => _origin.clone();

  /// Cloned resolved target positions; empty for death/core cues.
  List<Vector2> get positions => [for (final p in _positions) p.clone()];

  /// Primary-target point the pierce beam fires toward; origin when unused.
  /// Returns a defensive copy.
  Vector2 get beamTarget => _beamTarget.clone();

  /// Splash area or enemy radius; 0 when unused.
  double get radius => _radius;

  Color get color => _color;

  double get lifetime => _lifetime;

  // --- Static geometry, computed once on first use -------------------------

  late final List<Offset> _accentOffsets = [
    for (final position in _positions) position.toOffset(),
  ];

  late final Path _chainPath = _buildChainPath();

  late final Offset? _pierceBeamEnd = _computePierceBeamEnd();

  late final Path _burstPath = _buildBurstPath();

  late final Path _coreMarkPath = _buildCoreMarkPath();

  Path _buildChainPath() {
    if (_positions.isEmpty) {
      return Path();
    }
    final path = Path()..moveTo(_positions.first.x, _positions.first.y);
    for (final position in _positions.skip(1)) {
      path.lineTo(position.x, position.y);
    }
    return path;
  }

  Offset? _computePierceBeamEnd() {
    // Pierce selects targets within pierceWidth of the firing line and sorts
    // them by projection, so the nearest resolved center can sit off-axis.
    // The beam follows the recorded origin -> primary-target ray; accents
    // stay at the actual resolved positions.
    final direction = _beamTarget - _origin;
    if (direction.length2 == 0) {
      return null;
    }
    direction.normalize();
    var reach = 0.0;
    for (final position in _positions) {
      reach = math.max(reach, direction.dot(position - _origin));
    }
    return (_origin + direction * (reach + _pierceBeamOvershoot)).toOffset();
  }

  Path _buildBurstPath() {
    // Stationary geometry: only opacity decays, per the spec.
    final path = Path();
    const burstSegments = 6;
    final inner = _radius * 0.5;
    final outer = _radius * 1.15;
    for (var segment = 0; segment < burstSegments; segment++) {
      final angle = segment * (2 * math.pi / burstSegments);
      path.moveTo(
        _origin.x + inner * math.cos(angle),
        _origin.y + inner * math.sin(angle),
      );
      path.lineTo(
        _origin.x + outer * math.cos(angle),
        _origin.y + outer * math.sin(angle),
      );
    }
    return path;
  }

  Path _buildCoreMarkPath() {
    // Four-point diamond distinguishing the core impact from enemy death.
    final diamond = _radius * 0.6;
    return Path()
      ..moveTo(_origin.x, _origin.y - diamond)
      ..lineTo(_origin.x + diamond, _origin.y)
      ..lineTo(_origin.x, _origin.y + diamond)
      ..lineTo(_origin.x - diamond, _origin.y)
      ..close();
  }

  // --- Lifecycle ------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);
    // A queued cue receives its first update before its first render. Hold
    // elapsed at zero until then so a cue is drawn at full opacity for at
    // least one frame — even when a single frame outlasts the lifetime.
    // Defeat teardown can still cancel a cue that has never rendered.
    if (!_hasRendered) {
      return;
    }
    _elapsed += dt;
    if (_elapsed >= _lifetime) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    _hasRendered = true;
    final progress = (_elapsed / _lifetime).clamp(0.0, 1.0);
    final alpha = (1 - progress).clamp(0.0, 1.0);
    switch (kind) {
      case CombatFeedbackKind.splash:
        _renderSplash(canvas, alpha);
      case CombatFeedbackKind.chain:
        _renderChain(canvas, alpha);
      case CombatFeedbackKind.pierce:
        _renderPierce(canvas, alpha);
      case CombatFeedbackKind.enemyDestroyed:
        _renderDestroyed(canvas, alpha);
      case CombatFeedbackKind.coreImpact:
        _renderCoreImpact(canvas, alpha);
    }
  }

  void _renderSplash(Canvas canvas, double alpha) {
    _strokePaint.color = _color.withValues(alpha: alpha);
    canvas.drawCircle(_origin.toOffset(), _radius, _strokePaint);
    // Restrained resolved-hit accent at each recorded position.
    _accentPaint.color = _color.withValues(alpha: alpha * 0.35);
    for (final accent in _accentOffsets) {
      canvas.drawCircle(accent, 3, _accentPaint);
    }
  }

  void _renderChain(Canvas canvas, double alpha) {
    if (_positions.isEmpty) {
      return;
    }
    _strokePaint.color = _color.withValues(alpha: alpha);
    canvas.drawPath(_chainPath, _strokePaint);
    _accentPaint.color = _color.withValues(alpha: alpha * 0.35);
    for (final accent in _accentOffsets) {
      canvas.drawCircle(accent, 2.5, _accentPaint);
    }
  }

  void _renderPierce(Canvas canvas, double alpha) {
    if (_positions.isEmpty) {
      return;
    }
    _strokePaint.color = _color.withValues(alpha: alpha);
    final beamEnd = _pierceBeamEnd;
    if (beamEnd != null) {
      canvas.drawLine(_origin.toOffset(), beamEnd, _strokePaint);
    }
    _accentPaint.color = _color.withValues(alpha: alpha * 0.35);
    for (final accent in _accentOffsets) {
      canvas.drawCircle(accent, 2.5, _accentPaint);
    }
  }

  void _renderDestroyed(Canvas canvas, double alpha) {
    _strokePaint.color = _color.withValues(alpha: alpha);
    canvas.drawPath(_burstPath, _strokePaint);
  }

  void _renderCoreImpact(Canvas canvas, double alpha) {
    _strokePaint.color = _color.withValues(alpha: alpha);
    canvas.drawCircle(_origin.toOffset(), _radius, _strokePaint);
    _accentPaint.color = _color.withValues(alpha: alpha);
    canvas.drawPath(_coreMarkPath, _accentPaint);
  }
}
