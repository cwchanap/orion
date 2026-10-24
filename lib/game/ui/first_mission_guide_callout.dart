import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../onboarding/contextual_tips.dart';
import '../onboarding/first_mission_guide.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';

/// The guide bubble's key: the stable handle tests use to assert the
/// edge-clamp guarantee (bubble rect inside the SafeArea).
const firstMissionGuideBubbleKey = ValueKey(
  'first-mission-guide-callout-bubble',
);

const double _margin = 12;
const double _targetGap = 14;
const double _ringRadius = 26;

/// First-layout estimate only; the real bubble size is measured after the
/// frame and the position corrected (no second layout system).
const Size _estimatedBubbleSize = Size(300, 120);

/// One soft, non-modal first-mission guidance callout (HPA-412 guide mode).
///
/// A thin adapter over the shared [_GuideCallout] renderer: it only maps the
/// guided step to its copy and keeps the tutorial actions (Skip everywhere,
/// Got it on the scanner step). All geometry, semantics and touch behavior
/// live in the shared renderer.
class FirstMissionGuideCallout extends StatelessWidget {
  const FirstMissionGuideCallout({
    super.key,
    required this.step,
    this.anchorKey,
    this.targetPoint,
    required this.onSkip,
    this.onDone,
  });

  final FirstMissionGuideStep step;

  /// Optional Flutter target (dock card, wave pill, radial Upgrade, scanner,
  /// draft frame) measured against this callout's own space after layout.
  final GlobalKey? anchorKey;

  /// Fallback target in the surrounding Stack's coordinate space — the Flame
  /// board exposes no widgets, so the page passes board points directly.
  final Offset? targetPoint;

  final VoidCallback onSkip;

  /// Final acknowledgement; supplied only for the scanner step.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return _GuideCallout(
      copy: switch (step) {
        FirstMissionGuideStep.buildCell => 'Tap an empty cell to build here.',
        FirstMissionGuideStep.towerCard => 'Pick a tower.',
        FirstMissionGuideStep.startWave =>
          "Start the wave when you're ready. Towers fire on their own.",
        FirstMissionGuideStep.upgrade =>
          'Tap a tower, then Upgrade between waves.',
        FirstMissionGuideStep.salvageModule =>
          'Salvage Modules last only for this mission.',
        FirstMissionGuideStep.scanner =>
          'Check the scanner before the next wave.',
      },
      showSkip: true,
      anchorKey: anchorKey,
      targetPoint: targetPoint,
      onSkip: onSkip,
      onDone: onDone,
    );
  }
}

/// One soft, non-modal contextual-tip callout (HPA-413 mode).
///
/// Thin adapter over the same shared renderer as [FirstMissionGuideCallout],
/// preserving its wrapper, semantics, keys and geometry. Shows the tip copy
/// and Got it — contextual tips are never skippable, only acknowledged.
class ContextualTipCallout extends StatelessWidget {
  const ContextualTipCallout({
    super.key,
    required this.tip,
    this.anchorKey,
    this.targetPoint,
    required this.onDone,
  });

  final ContextualTip tip;

  /// Optional Flutter target (e.g. the collapsed scanner control) measured
  /// against this callout's own space after layout.
  final GlobalKey? anchorKey;

  /// Fallback target in the surrounding Stack's coordinate space.
  final Offset? targetPoint;

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return _GuideCallout(
      copy: contextualTipCopy[tip]!,
      showSkip: false,
      anchorKey: anchorKey,
      targetPoint: targetPoint,
      onSkip: null,
      onDone: onDone,
    );
  }
}

/// The shared callout renderer: anchor measurement, SafeArea clamping,
/// hit-transparent chrome and the overlaid action row. No controller, no
/// overlay service — the page places it last in the mission Stack inside
/// bounded (Positioned.fill) constraints.
class _GuideCallout extends StatefulWidget {
  const _GuideCallout({
    required this.copy,
    required this.showSkip,
    this.anchorKey,
    this.targetPoint,
    required this.onSkip,
    this.onDone,
  });

  final String copy;

  /// Whether the Skip tutorial action renders (HPA-412 only).
  final bool showSkip;

  final GlobalKey? anchorKey;
  final Offset? targetPoint;
  final VoidCallback? onSkip;

  /// Final acknowledgement; rendered only when non-null.
  final VoidCallback? onDone;

  @override
  State<_GuideCallout> createState() => _GuideCalloutState();
}

class _GuideCalloutState extends State<_GuideCallout> {
  final GlobalKey _bubbleMeasureKey = GlobalKey();
  final GlobalKey _buttonRowKey = GlobalKey();

  /// Anchor rect and bubble size in this callout's own coordinates; null
  /// until the matching post-frame measurement lands.
  Rect? _anchorRect;
  Size? _bubbleSize;

  /// Height reserved for the (overlay) button row inside the chrome; corrected
  /// from the live row's measured height after the first frame.
  double _buttonRowHeight = 24;

  /// The last canvas size the LayoutBuilder saw; a change without a
  /// widget rebuild (rotation with no fresh snapshot) still re-measures.
  Size? _lastCanvasSize;

  /// Guards the in-flight post-frame measure: at most one callback is
  /// ever queued, so builds and the anchored re-arm below cannot stack
  /// duplicates across a frame.
  bool _measurePending = false;

  @override
  void didUpdateWidget(covariant _GuideCallout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.copy != widget.copy ||
        oldWidget.anchorKey != widget.anchorKey ||
        oldWidget.targetPoint != widget.targetPoint) {
      // Drop stale geometry; the post-frame measure re-derives both.
      _anchorRect = null;
      _bubbleSize = null;
    }
  }

  void _scheduleMeasure() {
    if (_measurePending) return;
    _measurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurePending = false;
      _measure();
    });
  }

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final anchorBox =
        widget.anchorKey?.currentContext?.findRenderObject() as RenderBox?;
    Rect? anchorRect;
    if (box != null &&
        box.attached &&
        anchorBox != null &&
        anchorBox.attached) {
      final topLeft = box.globalToLocal(anchorBox.localToGlobal(Offset.zero));
      final bottomRight = box.globalToLocal(
        anchorBox.localToGlobal(anchorBox.size.bottomRight(Offset.zero)),
      );
      anchorRect = Rect.fromPoints(topLeft, bottomRight);
    }
    final bubbleBox =
        _bubbleMeasureKey.currentContext?.findRenderObject() as RenderBox?;
    final bubbleSize = bubbleBox?.size;
    final buttonRowBox =
        _buttonRowKey.currentContext?.findRenderObject() as RenderBox?;
    final buttonRowHeight = buttonRowBox?.size.height;
    if (anchorRect != _anchorRect ||
        bubbleSize != _bubbleSize ||
        (buttonRowHeight != null && buttonRowHeight != _buttonRowHeight)) {
      setState(() {
        _anchorRect = anchorRect;
        _bubbleSize = bubbleSize;
        if (buttonRowHeight != null) {
          _buttonRowHeight = buttonRowHeight;
        }
      });
    }
    // An anchor can move without rebuilding this widget — the module
    // draft's SingleChildScrollView slides its keyed frame — so while
    // anchored the measure re-arms for the next produced frame. A queued
    // post-frame callback never schedules a frame itself: the loop sleeps
    // whenever nothing repaints and wakes on the scroll's own frames.
    if (widget.anchorKey != null) {
      _scheduleMeasure();
    }
  }

  /// Prefers below the target, flips above when tight, and always clamps to
  /// the SafeArea-inset bounds.
  ///
  /// An anchored target places against the anchor's EDGES — below its
  /// bottom or above its top, horizontally centered on it — so the bubble
  /// (and the Skip/Got it row inside it) never covers a tall anchor's
  /// interior. Point targets keep point-relative placement.
  Rect _clampBubble(
    Rect safe,
    Offset target,
    Size bubbleSize, {
    Rect? anchorRect,
  }) {
    final width = math.min(bubbleSize.width, safe.width);
    final height = bubbleSize.height;
    final belowTop = (anchorRect?.bottom ?? target.dy) + _targetGap;
    final aboveTop = (anchorRect?.top ?? target.dy) - _targetGap - height;
    final centerDx = anchorRect?.center.dx ?? target.dx;
    final top = (belowTop + height <= safe.bottom || aboveTop < safe.top)
        ? belowTop
        : aboveTop;
    return Rect.fromLTWH(
      (centerDx - width / 2).clamp(
        safe.left,
        math.max(safe.left, safe.right - width),
      ),
      top.clamp(safe.top, math.max(safe.top, safe.bottom - height)),
      width,
      height,
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    final uiTheme = OrionUiTheme.of(context);
    final copy = widget.copy;
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvas = constraints.biggest;
        // A resize that does not rebuild this widget's ancestors
        // (rotation between snapshot publishes) leaves the measured
        // anchor rect in stale coordinates — re-measure on any canvas
        // change, not only on widget updates.
        if (canvas != _lastCanvasSize) {
          _lastCanvasSize = canvas;
          _scheduleMeasure();
        }
        final padding = MediaQuery.paddingOf(context);
        final safe = Rect.fromLTRB(
          padding.left + _margin,
          padding.top + _margin,
          math.max(
            padding.left + _margin,
            canvas.width - padding.right - _margin,
          ),
          math.max(
            padding.top + _margin,
            canvas.height - padding.bottom - _margin,
          ),
        );
        final anchor = _anchorRect;
        // An anchored callout with no measured anchor rect renders nothing:
        // the anchor is detached (its target surface is hidden this frame)
        // or simply unmeasured — painting the ring at a fixed fallback
        // point would point at nothing. The post-frame measure scheduled
        // above still runs, and anchor attach/detach always coincides with
        // a snapshot-driven rebuild, so the measure re-runs on every
        // relevant change.
        if (widget.anchorKey != null && anchor == null) {
          return const SizedBox.shrink();
        }
        final pointTarget =
            widget.targetPoint ?? Offset(canvas.width / 2, canvas.height / 3);
        final bubbleRect = _clampBubble(
          safe,
          pointTarget,
          _bubbleSize ?? _estimatedBubbleSize,
          anchorRect: anchor,
        );
        // The ring marks the anchor boundary point nearest the bubble —
        // never the anchor's interior — clamped into the SafeArea so a
        // partially off-screen anchor cannot paint it off-canvas.
        final ringTarget = anchor == null
            ? pointTarget
            : _boundaryPoint(anchor, bubbleRect.center);
        final target = Offset(
          ringTarget.dx.clamp(safe.left, safe.right),
          ringTarget.dy.clamp(safe.top, safe.bottom),
        );
        final measured = _bubbleSize != null;
        final bubble = Stack(
          clipBehavior: Clip.none,
          children: [
            // The chrome (surface + copy) never joins a gesture arena;
            // only the overlaid button row below receives tutorial
            // taps, so gameplay beneath the bubble stays interactive
            // (soft guidance, never a lock).
            IgnorePointer(
              child: KeyedSubtree(
                key: firstMissionGuideBubbleKey,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.max(0, safe.width),
                  ),
                  child: OrionSurface(
                    key: _bubbleMeasureKey,
                    tier: OrionSurfaceTier.t1,
                    radius: 16,
                    padding: const EdgeInsets.fromLTRB(14, 8, 6, 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The copy never swallows a tap meant for the
                        // control underneath the bubble; the whole
                        // chrome is hit-transparent anyway.
                        Semantics(
                          liveRegion: true,
                          label: copy,
                          excludeSemantics: true,
                          child: IgnorePointer(
                            child: Text(
                              copy,
                              style: OrionTypography.readout(
                                size: 13,
                                color: uiTheme.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        // Reserves the live button row's height so the
                        // chrome keeps the exact size it had when the
                        // row was inline.
                        SizedBox(height: _buttonRowHeight),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // The only tutorial hit targets, overlaid at the chrome's
            // bottom-right (padding right/bottom = 6).
            Positioned(
              right: 6,
              bottom: 6,
              child: KeyedSubtree(
                key: _buttonRowKey,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.showSkip)
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: widget.onSkip,
                        child: Text(
                          'Skip tutorial',
                          style: OrionTypography.readout(
                            size: 12,
                            color: uiTheme.textMuted,
                          ),
                        ),
                      ),
                    if (widget.onDone != null)
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: widget.onDone,
                        child: Text(
                          'Got it',
                          style: OrionTypography.readout(
                            size: 12,
                            color: uiTheme.systemCyan,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
        return Stack(
          children: [
            // Connector + ring are pure decoration and never join a gesture
            // arena: taps over empty overlay space reach the game beneath.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _GuideConnectorPainter(
                    target: target,
                    // The spoke starts on the bubble's measured edge; with
                    // only the first-frame estimate it would draw from a
                    // spot the bubble never occupied.
                    bubbleRect: measured ? bubbleRect : Rect.zero,
                    color: uiTheme.systemCyan,
                  ),
                ),
              ),
            ),
            if (measured)
              AnimatedPositioned(
                duration: orionMotionDuration(context, orionSheetDuration),
                curve: Curves.easeOutCubic,
                left: bubbleRect.left,
                top: bubbleRect.top,
                child: bubble,
              )
            else
              // First frame only: the bubble is being measured at its
              // intrinsic size. Placing it at the estimate and sliding to
              // the measured rect reads as a pop — keep it laid out (the
              // measure needs it) but invisible and untouchable.
              Positioned(
                left: 0,
                top: 0,
                child: IgnorePointer(child: Opacity(opacity: 0, child: bubble)),
              ),
          ],
        );
      },
    );
  }
}

/// The point on [rect]'s boundary nearest [towards]: the clamped point for
/// an outside approach, or the nearer horizontal edge when [towards] sits
/// inside the rect.
Offset _boundaryPoint(Rect rect, Offset towards) {
  final clamped = Offset(
    towards.dx.clamp(rect.left, rect.right),
    towards.dy.clamp(rect.top, rect.bottom),
  );
  if (clamped != towards) return clamped;
  // Target inside the rect: aim at the nearer horizontal edge.
  return Offset(
    towards.dx,
    towards.dy < rect.center.dy ? rect.top : rect.bottom,
  );
}

/// Ring around the target plus a short spoke from the bubble edge. Pure
/// decoration — its host is wrapped in [IgnorePointer].
class _GuideConnectorPainter extends CustomPainter {
  const _GuideConnectorPainter({
    required this.target,
    required this.bubbleRect,
    required this.color,
  });

  final Offset target;
  final Rect bubbleRect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(target, _ringRadius, stroke..color = color);

    // No measured bubble yet (the first layout frame): the ring alone
    // still marks the target — a spoke from Rect.zero would streak
    // across the canvas.
    if (bubbleRect.isEmpty) return;

    // Spoke from the bubble boundary nearest the target up to the ring.
    final start = _boundaryPoint(bubbleRect, target);
    final direction = target - bubbleRect.center;
    if (direction.distance < 1) return;
    final end = target - (direction / direction.distance) * (_ringRadius + 3);
    if ((end - start).distance < 4) return;
    canvas.drawLine(start, end, stroke..color = color.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(_GuideConnectorPainter oldDelegate) =>
      oldDelegate.target != target ||
      oldDelegate.bubbleRect != bubbleRect ||
      oldDelegate.color != color;
}
