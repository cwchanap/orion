import 'dart:math' as math;

import 'package:flutter/material.dart';

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

/// One soft, non-modal first-mission guidance callout.
///
/// A compact [OrionSurface] bubble pointing at either a [GlobalKey] anchor
/// ([anchorKey], measured after layout) or a board point ([targetPoint]) in
/// the surrounding Stack's coordinate space. There is deliberately no modal
/// barrier, spotlight mask, or full-screen gesture surface: the connector and
/// ring are ignored-pointer decoration, the bubble copy ignores the pointer,
/// and only the Skip / Got it buttons are tutorial hit targets — the game
/// beneath stays fully interactive (soft guidance, never a lock).
///
/// Presentation only: no controller, no overlay service. The page places it
/// last in the mission Stack inside bounded (Positioned.fill) constraints.
class FirstMissionGuideCallout extends StatefulWidget {
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
  State<FirstMissionGuideCallout> createState() =>
      _FirstMissionGuideCalloutState();
}

class _FirstMissionGuideCalloutState extends State<FirstMissionGuideCallout> {
  final GlobalKey _bubbleMeasureKey = GlobalKey();
  final GlobalKey _buttonRowKey = GlobalKey();

  /// Anchor rect and bubble size in this callout's own coordinates; null
  /// until the matching post-frame measurement lands.
  Rect? _anchorRect;
  Size? _bubbleSize;

  /// Height reserved for the (overlay) button row inside the chrome; corrected
  /// from the live row's measured height after the first frame.
  double _buttonRowHeight = 24;

  @override
  void didUpdateWidget(covariant FirstMissionGuideCallout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step != widget.step ||
        oldWidget.anchorKey != widget.anchorKey ||
        oldWidget.targetPoint != widget.targetPoint) {
      // Drop stale geometry; the post-frame measure re-derives both.
      _anchorRect = null;
      _bubbleSize = null;
    }
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
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
  }

  /// Prefers below the target, flips above when tight, and always clamps to
  /// the SafeArea-inset bounds.
  Rect _clampBubble(Rect safe, Offset target, Size bubbleSize) {
    final width = math.min(bubbleSize.width, safe.width);
    final height = bubbleSize.height;
    final belowTop = target.dy + _targetGap;
    final aboveTop = target.dy - _targetGap - height;
    final top = (belowTop + height <= safe.bottom || aboveTop < safe.top)
        ? belowTop
        : aboveTop;
    return Rect.fromLTWH(
      (target.dx - width / 2).clamp(
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
    final copy = _copyFor(widget.step);
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvas = constraints.biggest;
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
        final target =
            anchor?.center ??
            widget.targetPoint ??
            Offset(canvas.width / 2, canvas.height / 3);
        final bubbleRect = _clampBubble(
          safe,
          target,
          _bubbleSize ?? _estimatedBubbleSize,
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
                    bubbleRect: bubbleRect,
                    color: uiTheme.systemCyan,
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: orionMotionDuration(context, orionSheetDuration),
              curve: Curves.easeOutCubic,
              left: bubbleRect.left,
              top: bubbleRect.top,
              child: Stack(
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
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
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
              ),
            ),
          ],
        );
      },
    );
  }

  String _copyFor(FirstMissionGuideStep step) => switch (step) {
    FirstMissionGuideStep.buildCell => 'Tap an empty cell to build here.',
    FirstMissionGuideStep.towerCard => 'Pick a tower.',
    FirstMissionGuideStep.startWave =>
      "Start the wave when you're ready. Towers fire on their own.",
    FirstMissionGuideStep.upgrade => 'Tap a tower, then Upgrade between waves.',
    FirstMissionGuideStep.salvageModule =>
      'Salvage Modules last only for this mission.',
    FirstMissionGuideStep.scanner => 'Check the scanner before the next wave.',
  };
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

    // Spoke from the bubble boundary nearest the target up to the ring.
    final start = _boundaryPoint(bubbleRect, target);
    final direction = target - bubbleRect.center;
    if (direction.distance < 1) return;
    final end = target - (direction / direction.distance) * (_ringRadius + 3);
    if ((end - start).distance < 4) return;
    canvas.drawLine(start, end, stroke..color = color.withValues(alpha: 0.6));
  }

  Offset _boundaryPoint(Rect rect, Offset towards) {
    final clamped = Offset(
      towards.dx.clamp(rect.left, rect.right),
      towards.dy.clamp(rect.top, rect.bottom),
    );
    if (clamped != towards) return clamped;
    // Target inside the bubble: aim at the nearer horizontal edge.
    return Offset(
      towards.dx,
      towards.dy < rect.center.dy ? rect.top : rect.bottom,
    );
  }

  @override
  bool shouldRepaint(_GuideConnectorPainter oldDelegate) =>
      oldDelegate.target != target ||
      oldDelegate.bubbleRect != bubbleRect ||
      oldDelegate.color != color;
}
