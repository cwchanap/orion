import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';

class HoldToSalvage extends StatefulWidget {
  const HoldToSalvage({
    super.key,
    required this.refund,
    required this.onSell,
    this.compact = false,
  });
  final int refund;
  final VoidCallback? onSell;
  final bool compact;
  @override
  State<HoldToSalvage> createState() => _HoldToSalvageState();
}

class _HoldToSalvageState extends State<HoldToSalvage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
        // This duration authorizes a sale, so accessibility must not shorten it.
        animationBehavior: AnimationBehavior.preserve,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _activePointer = null;
          _hold.reset();
          widget.onSell?.call();
        }
      });

  /// The one pointer holding the control; other touches are ignored and a
  /// second finger cannot restart or extend a hold.
  int? _activePointer;

  void _endHold() {
    _activePointer = null;
    _hold.reset();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.onSell == null || _activePointer != null) return;
    _activePointer = event.pointer;
    _hold.forward(from: 0);
  }

  /// A hold only counts while the finger stays on the control: sliding off
  /// abandons it, and re-entering does not resume it — only a fresh press can.
  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null ||
        !box.paintBounds.contains(box.globalToLocal(event.position))) {
      _endHold();
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _endHold();
  }

  @override
  void didUpdateWidget(covariant HoldToSalvage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onSell == null || oldWidget.refund != widget.refund) {
      _endHold();
    }
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Salvage tower?'),
        content: Text('Recover ${widget.refund} credits.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salvage'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) widget.onSell?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = OrionUiTheme.of(context);
    final enabled = widget.onSell != null;
    return Semantics(
      key: const ValueKey('tower-sell-semantics'),
      button: true,
      enabled: enabled,
      label: 'Sell ${widget.refund}',
      hint: 'Hold to salvage, or activate to confirm',
      onTap: enabled ? _confirm : null,
      excludeSemantics: true,
      child: Tooltip(
        message: 'Hold to salvage +${widget.refund}',
        triggerMode: TooltipTriggerMode.manual,
        child: FocusableActionDetector(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                if (enabled) _confirm();
                return null;
              },
            ),
          },
          child: Listener(
            key: const ValueKey('tower-sell'),
            behavior: HitTestBehavior.opaque,
            onPointerDown: _handlePointerDown,
            onPointerMove: _handlePointerMove,
            onPointerUp: _handlePointerEnd,
            onPointerCancel: _handlePointerEnd,
            child: AnimatedBuilder(
              animation: _hold,
              builder: (context, _) => Container(
                constraints: BoxConstraints(
                  minHeight: widget.compact ? 56 : 54,
                  minWidth: widget.compact ? 64 : 0,
                ),
                width: widget.compact ? null : double.infinity,
                padding: widget.compact
                    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                    : EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: t.hullBlack.withValues(alpha: .85),
                  borderRadius: BorderRadius.circular(widget.compact ? 28 : 14),
                  border: Border.all(
                    color: enabled
                        ? t.dangerRed.withValues(alpha: .6)
                        : t.frameSteel,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _hold.value,
                        child: ColoredBox(
                          color: t.dangerRed.withValues(alpha: .35),
                        ),
                      ),
                    ),
                    Center(
                      widthFactor: widget.compact ? 1 : null,
                      heightFactor: 1,
                      child: widget.compact
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  color: enabled ? t.dangerRed : t.textMuted,
                                  size: 20,
                                ),
                                Text(
                                  '+${widget.refund}',
                                  style: OrionTypography.readout(
                                    size: 11,
                                    color: t.creditGold,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  color: enabled ? t.dangerRed : t.textMuted,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: OrionText.micro(
                                    'HOLD TO SALVAGE',
                                    color: t.dangerRed,
                                    size: 9,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '+${widget.refund}',
                                  style: OrionTypography.readout(
                                    size: 18,
                                    color: t.creditGold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
