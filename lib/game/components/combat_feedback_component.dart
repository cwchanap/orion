import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

/// Kind of transient combat feedback cue.
enum CombatFeedbackKind { splash, chain, pierce, enemyDestroyed, coreImpact }

/// Callback contract for handing a resolved feedback cue to its owner.
typedef CombatFeedbackCallback =
    void Function(CombatFeedbackComponent feedback);

/// Presentation-only combat feedback drawn from already-resolved geometry.
///
/// The component never owns enemy references, target selectors, or damage
/// logic; callers hand it cloned positions captured during the existing
/// damage loops. Rendering is stationary Canvas primitives with opacity
/// decay only — no travelling particles or animation state machine.
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
         origin: positions.isEmpty ? Vector2.zero() : positions.first.clone(),
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
         color: const Color(0xFFE35D6A),
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
         color: const Color(0xFF6EC6FF),
         lifetime: _coreImpactLifetime,
       );

  // Redirecting constructors pre-clone inputs; the mapping initializer for
  // _positions makes plain assignments clearer than initializing formals.
  CombatFeedbackComponent._({
    required this.kind,
    required Vector2 origin,
    Vector2? beamTarget,
    required double radius,
    required List<Vector2> positions,
    required Color color,
    required double lifetime,
  }) // ignore: prefer_initializing_formals
  : _origin = origin.clone(),
       _beamTarget = (beamTarget ?? origin).clone(),
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
       );

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

  double _elapsed = 0;

  /// Splash center, first chain point, firing origin, or resolution center.
  Vector2 get origin => _origin;

  /// Cloned resolved target positions; empty for death/core cues.
  List<Vector2> get positions => _positions;

  /// Primary-target point the pierce beam fires toward; origin when unused.
  Vector2 get beamTarget => _beamTarget;

  /// Splash area or enemy radius; 0 when unused.
  double get radius => _radius;

  Color get color => _color;

  double get lifetime => _lifetime;

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _lifetime) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
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
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _color.withValues(alpha: alpha)
      ..isAntiAlias = true;
    canvas.drawCircle(_origin.toOffset(), _radius, paint);
    // Restrained resolved-hit accent at each recorded position.
    final accentPaint = Paint()
      ..color = _color.withValues(alpha: alpha * 0.35)
      ..isAntiAlias = true;
    for (final position in _positions) {
      canvas.drawCircle(position.toOffset(), 3, accentPaint);
    }
  }

  void _renderChain(Canvas canvas, double alpha) {
    if (_positions.isEmpty) {
      return;
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = _color.withValues(alpha: alpha)
      ..isAntiAlias = true;
    final path = Path()..moveTo(_positions.first.x, _positions.first.y);
    for (final position in _positions.skip(1)) {
      path.lineTo(position.x, position.y);
    }
    canvas.drawPath(path, paint);
    final accentPaint = Paint()
      ..color = _color.withValues(alpha: alpha * 0.35)
      ..isAntiAlias = true;
    for (final position in _positions) {
      canvas.drawCircle(position.toOffset(), 2.5, accentPaint);
    }
  }

  void _renderPierce(Canvas canvas, double alpha) {
    if (_positions.isEmpty) {
      return;
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = _color.withValues(alpha: alpha)
      ..isAntiAlias = true;
    // Pierce selects targets within pierceWidth of the firing line and sorts
    // them by projection, so the nearest resolved center can sit off-axis.
    // The beam follows the recorded origin -> primary-target ray; accents
    // stay at the actual resolved positions.
    final direction = _beamTarget - _origin;
    if (direction.length2 > 0) {
      direction.normalize();
      var reach = 0.0;
      for (final position in _positions) {
        reach = math.max(reach, direction.dot(position - _origin));
      }
      canvas.drawLine(
        _origin.toOffset(),
        (_origin + direction * (reach + _pierceBeamOvershoot)).toOffset(),
        paint,
      );
    }
    final accentPaint = Paint()
      ..color = _color.withValues(alpha: alpha * 0.35)
      ..isAntiAlias = true;
    for (final position in _positions) {
      canvas.drawCircle(position.toOffset(), 2.5, accentPaint);
    }
  }

  void _renderDestroyed(Canvas canvas, double alpha) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = _color.withValues(alpha: alpha)
      ..isAntiAlias = true;
    final center = _origin.toOffset();
    const burstSegments = 6;
    final inner = _radius * 0.5;
    // Stationary geometry: only opacity decays, per the spec.
    final outer = _radius * 1.15;
    for (var segment = 0; segment < burstSegments; segment++) {
      final angle = segment * (2 * math.pi / burstSegments);
      canvas.drawLine(
        Offset(
          center.dx + inner * math.cos(angle),
          center.dy + inner * math.sin(angle),
        ),
        Offset(
          center.dx + outer * math.cos(angle),
          center.dy + outer * math.sin(angle),
        ),
        paint,
      );
    }
  }

  void _renderCoreImpact(Canvas canvas, double alpha) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = _color.withValues(alpha: alpha)
      ..isAntiAlias = true;
    final center = _origin.toOffset();
    canvas.drawCircle(center, _radius, paint);
    // Cross/diamond mark distinguishing the core impact from enemy death.
    final markPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = _color.withValues(alpha: alpha)
      ..isAntiAlias = true;
    final diamond = _radius * 0.6;
    final mark = Path()
      ..moveTo(center.dx, center.dy - diamond)
      ..lineTo(center.dx + diamond, center.dy)
      ..lineTo(center.dx, center.dy + diamond)
      ..lineTo(center.dx - diamond, center.dy)
      ..close();
    canvas.drawPath(mark, markPaint);
  }
}
