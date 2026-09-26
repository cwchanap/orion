import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/components/combat_feedback_component.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CombatFeedbackComponent', () {
    group('constructors', () {
      test('splash clones caller-owned origin and positions', () {
        final origin = Vector2(10, 20);
        final positions = [Vector2(11, 21), Vector2(12, 22)];
        final feedback = CombatFeedbackComponent.splash(
          origin: origin,
          radius: 48,
          positions: positions,
          color: const Color(0xFFFFB84D),
        );

        origin.setValues(999, 999);
        positions.add(Vector2(0, 0));
        positions.first.setValues(999, 999);

        expect(feedback.origin, Vector2(10, 20));
        expect(feedback.positions, [Vector2(11, 21), Vector2(12, 22)]);
      });

      test('chain clones caller-owned positions and derives origin', () {
        final positions = [Vector2(1, 2), Vector2(3, 4)];
        final feedback = CombatFeedbackComponent.chain(
          positions: positions,
          color: const Color(0xFFD7B2FF),
        );

        positions.first.setValues(999, 999);
        positions.clear();

        expect(feedback.kind, CombatFeedbackKind.chain);
        expect(feedback.origin, Vector2(1, 2));
        expect(feedback.positions, [Vector2(1, 2), Vector2(3, 4)]);
      });

      test('pierce retains origin, beam target, and ordered positions', () {
        final feedback = CombatFeedbackComponent.pierce(
          origin: Vector2(0, 0),
          beamTarget: Vector2(60, 0),
          positions: [Vector2(30, 0), Vector2(60, 0)],
          color: const Color(0xFFE8F1FF),
        );

        expect(feedback.kind, CombatFeedbackKind.pierce);
        expect(feedback.origin, Vector2(0, 0));
        expect(feedback.beamTarget, Vector2(60, 0));
        expect(feedback.positions, [Vector2(30, 0), Vector2(60, 0)]);
      });

      test('enemyDestroyed and coreImpact retain origin/radius and color', () {
        final destroyed = CombatFeedbackComponent.enemyDestroyed(
          origin: Vector2(5, 6),
          radius: 11,
        );
        final coreImpact = CombatFeedbackComponent.coreImpact(
          origin: Vector2(7, 8),
          radius: 14,
        );

        expect(destroyed.kind, CombatFeedbackKind.enemyDestroyed);
        expect(destroyed.origin, Vector2(5, 6));
        expect(destroyed.radius, 11);
        expect(coreImpact.kind, CombatFeedbackKind.coreImpact);
        expect(coreImpact.origin, Vector2(7, 8));
        expect(coreImpact.radius, 14);
        expect(destroyed.color, isNot(coreImpact.color));
      });

      test('unused geometry stays total with sensible empty/zero values', () {
        final destroyed = CombatFeedbackComponent.enemyDestroyed(
          origin: Vector2.zero(),
          radius: 11,
        );
        final chain = CombatFeedbackComponent.chain(
          positions: [Vector2(1, 1)],
          color: const Color(0xFFFFFFFF),
        );

        expect(destroyed.positions, isEmpty);
        expect(chain.radius, 0);
      });

      test('geometry getters return defensive copies', () {
        final feedback = CombatFeedbackComponent.pierce(
          origin: Vector2(0, 0),
          beamTarget: Vector2(60, 0),
          positions: [Vector2(30, 0)],
          color: const Color(0xFFE8F1FF),
        );

        feedback.origin.setValues(999, 999);
        feedback.beamTarget.setValues(999, 999);
        feedback.positions.first.setValues(999, 999);

        expect(feedback.origin, Vector2.zero());
        expect(feedback.beamTarget, Vector2(60, 0));
        expect(feedback.positions, [Vector2(30, 0)]);
      });
    });

    group('priority', () {
      test('death and core cues render at priority 15', () {
        expect(
          CombatFeedbackComponent.enemyDestroyed(
            origin: Vector2.zero(),
            radius: 11,
          ).priority,
          15,
        );
        expect(
          CombatFeedbackComponent.coreImpact(
            origin: Vector2.zero(),
            radius: 11,
          ).priority,
          15,
        );
      });

      test('live multi-target cues render above gravity fields at 26', () {
        expect(
          CombatFeedbackComponent.splash(
            origin: Vector2.zero(),
            radius: 10,
            positions: const [],
            color: const Color(0xFFFFFFFF),
          ).priority,
          26,
        );
        expect(
          CombatFeedbackComponent.chain(
            positions: [Vector2.zero()],
            color: const Color(0xFFFFFFFF),
          ).priority,
          26,
        );
        expect(
          CombatFeedbackComponent.pierce(
            origin: Vector2.zero(),
            beamTarget: Vector2.zero(),
            positions: [Vector2.zero()],
            color: const Color(0xFFFFFFFF),
          ).priority,
          26,
        );
      });
    });

    group('lifecycle', () {
      test('expires and removes itself once elapsed passes its lifetime', () {
        final game = FlameGame();
        game.onGameResize(Vector2(100, 100));
        // ignore: invalid_use_of_internal_member
        game.setMounted();
        final feedback = CombatFeedbackComponent.enemyDestroyed(
          origin: Vector2.zero(),
          radius: 11,
        );
        game.add(feedback);
        game.processLifecycleEvents();
        expect(feedback.isRemoved, isFalse);

        _renderToCanvas(feedback);
        game.update(feedback.lifetime + 0.01);
        game.processLifecycleEvents();

        expect(feedback.isRemoved, isTrue);
        expect(game.children.whereType<CombatFeedbackComponent>(), isEmpty);
      });

      test(
        'never-drawn cue survives an oversized frame until it renders once',
        () {
          // A cue queued in frame N receives its first update before its
          // first render; a long frame must not expire it before it is ever
          // drawn.
          final game = FlameGame();
          game.onGameResize(Vector2(100, 100));
          // ignore: invalid_use_of_internal_member
          game.setMounted();
          final feedback = CombatFeedbackComponent.coreImpact(
            origin: Vector2.zero(),
            radius: 11,
          );
          game.add(feedback);
          game.processLifecycleEvents();

          game.update(feedback.lifetime + 5);
          game.processLifecycleEvents();

          expect(feedback.isRemoved, isFalse);
          _renderToCanvas(feedback);
          game.update(feedback.lifetime + 0.01);
          game.processLifecycleEvents();
          expect(feedback.isRemoved, isTrue);
        },
      );
    });

    group('render', () {
      List<CombatFeedbackComponent> feedbacks() => [
        CombatFeedbackComponent.splash(
          origin: Vector2(50, 50),
          radius: 48,
          positions: [Vector2(60, 55), Vector2(70, 60)],
          color: const Color(0xFFFFB84D),
        ),
        CombatFeedbackComponent.chain(
          positions: [Vector2(10, 10), Vector2(40, 30), Vector2(70, 60)],
          color: const Color(0xFFD7B2FF),
        ),
        CombatFeedbackComponent.pierce(
          origin: Vector2(0, 0),
          beamTarget: Vector2(60, 0),
          positions: [Vector2(30, 0), Vector2(60, 0)],
          color: const Color(0xFFE8F1FF),
        ),
        CombatFeedbackComponent.enemyDestroyed(
          origin: Vector2(80, 80),
          radius: 11,
        ),
        CombatFeedbackComponent.coreImpact(origin: Vector2(20, 90), radius: 14),
      ];

      test('every kind renders at full opacity without throwing', () {
        for (final feedback in feedbacks()) {
          expect(() => _renderToCanvas(feedback), returnsNormally);
        }
      });

      test('every kind still draws near expiry', () {
        for (final feedback in feedbacks()) {
          // update holds elapsed at 0 until the first render, so prime the
          // cue with a full-opacity frame before advancing time.
          _renderToCanvas(feedback);
          feedback.update(feedback.lifetime * 0.95);
          final canvas = TestRecordingCanvas();
          feedback.render(canvas);
          expect(feedback.isRemoved, isFalse);
          expect(canvas.invocations, isNotEmpty);
        }
      });

      test('splash and chain draw an accent at every resolved position', () {
        final splash = CombatFeedbackComponent.splash(
          origin: Vector2(50, 50),
          radius: 48,
          positions: [Vector2(60, 55), Vector2(70, 60)],
          color: const Color(0xFFFFB84D),
        );
        final splashCanvas = TestRecordingCanvas();
        splash.render(splashCanvas);
        // Splash area circle first, then one accent per resolved position.
        expect(
          splashCanvas.invocations
              .where((call) => call.invocation.memberName == #drawCircle)
              .map((call) => call.invocation.positionalArguments[0] as Offset)
              .toList(),
          [const Offset(50, 50), const Offset(60, 55), const Offset(70, 60)],
        );

        final chain = CombatFeedbackComponent.chain(
          positions: [Vector2(10, 10), Vector2(40, 30), Vector2(70, 60)],
          color: const Color(0xFFD7B2FF),
        );
        final chainCanvas = TestRecordingCanvas();
        chain.render(chainCanvas);
        // The chain polyline is a drawPath; its circles are accents only.
        expect(
          chainCanvas.invocations
              .where((call) => call.invocation.memberName == #drawCircle)
              .map((call) => call.invocation.positionalArguments[0] as Offset)
              .toList(),
          [const Offset(10, 10), const Offset(40, 30), const Offset(70, 60)],
        );
      });

      test('pierce beam stays on the firing ray when hits sit off-axis', () {
        // selectPierceTargets accepts enemies within pierceWidth of the firing
        // line, so resolved centers can be off the origin -> primary ray.
        final feedback = CombatFeedbackComponent.pierce(
          origin: Vector2.zero(),
          beamTarget: Vector2(30, 0),
          positions: [Vector2(30, 0), Vector2(60, 20)],
          color: const Color(0xFFE8F1FF),
        );
        final canvas = TestRecordingCanvas();

        feedback.render(canvas);

        final beams = canvas.invocations
            .where((call) => call.invocation.memberName == #drawLine)
            .toList();
        expect(beams, hasLength(1));
        final beam = beams.single.invocation.positionalArguments;
        expect(beam[0], Offset.zero);
        final beamEnd = beam[1] as Offset;
        // Collinear with the +x firing ray instead of bending toward the
        // off-axis hit, and carried past the farthest hit's projection.
        expect(beamEnd.dy, 0);
        expect(beamEnd.dx, greaterThan(60));

        final accents = canvas.invocations
            .where((call) => call.invocation.memberName == #drawCircle)
            .map((call) => call.invocation.positionalArguments[0] as Offset)
            .toList();
        expect(accents, [const Offset(30, 0), const Offset(60, 20)]);
      });

      test('pierce beam follows the primary-target ray when a closer hit sits '
          'off-axis', () {
        // selectPierceTargets sorts corridor hits by projection, so an
        // off-axis enemy nearer than the primary target resolves first.
        final feedback = CombatFeedbackComponent.pierce(
          origin: Vector2.zero(),
          beamTarget: Vector2(60, 0),
          positions: [Vector2(30, 20), Vector2(60, 0)],
          color: const Color(0xFFE8F1FF),
        );
        final canvas = TestRecordingCanvas();

        feedback.render(canvas);

        final beams = canvas.invocations
            .where((call) => call.invocation.memberName == #drawLine)
            .toList();
        expect(beams, hasLength(1));
        final beam = beams.single.invocation.positionalArguments;
        expect(beam[0], Offset.zero);
        final beamEnd = beam[1] as Offset;
        // The beam tracks the +x primary-target ray rather than rotating
        // toward the nearer off-axis hit.
        expect(beamEnd.dy, 0);
        expect(beamEnd.dx, greaterThan(60));
      });

      test(
        'pierce draws only accents when the beam target sits on the origin',
        () {
          final feedback = CombatFeedbackComponent.pierce(
            origin: Vector2(10, 10),
            beamTarget: Vector2(10, 10),
            positions: [Vector2(10, 10)],
            color: const Color(0xFFE8F1FF),
          );
          final canvas = TestRecordingCanvas();

          feedback.render(canvas);

          expect(
            canvas.invocations.where(
              (call) => call.invocation.memberName == #drawLine,
            ),
            isEmpty,
          );
          expect(
            canvas.invocations.where(
              (call) => call.invocation.memberName == #drawCircle,
            ),
            hasLength(1),
          );
        },
      );
    });
  });
}

void _renderToCanvas(CombatFeedbackComponent feedback) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder)..translate(60, 80);
  feedback.render(canvas);
  recorder.endRecording().dispose();
}
