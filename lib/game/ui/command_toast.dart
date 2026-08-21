import 'dart:async';

import 'package:flutter/material.dart';

import 'command_frame.dart';
import 'orion_ui_theme.dart';

class CommandToast extends StatefulWidget {
  const CommandToast({
    super.key,
    required this.feedback,
    this.visibleDuration = const Duration(milliseconds: 2400),
  });

  final String? feedback;
  final Duration visibleDuration;

  @override
  State<CommandToast> createState() => _CommandToastState();
}

class _CommandToastState extends State<CommandToast> {
  Timer? _timer;
  final ValueNotifier<bool> _renderText = ValueNotifier(false);
  String? _lastInput;
  String? _latchedMessage;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _accept(widget.feedback, notify: false);
  }

  @override
  void didUpdateWidget(covariant CommandToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    _accept(widget.feedback, notify: true);
  }

  void _accept(String? input, {required bool notify}) {
    if (input == null) {
      _lastInput = null;
      return;
    }
    if (_lastInput == input) return;

    void updateState() {
      _lastInput = input;
      _latchedMessage = input;
      _visible = true;
      _renderText.value = true;
    }

    if (notify) {
      setState(updateState);
    } else {
      updateState();
    }
    _timer?.cancel();
    _timer = Timer(widget.visibleDuration, () {
      if (!mounted) return;
      setState(() {
        _visible = false;
        _renderText.value = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.15);
    final message = _latchedMessage;
    final tone = message == null ? _ToastTone.neutral : _toneFor(message);
    final toneColor = switch (tone) {
      _ToastTone.danger => uiTheme.dangerRed,
      _ToastTone.warning => uiTheme.warningOrange,
      _ToastTone.neutral => uiTheme.systemCyan,
    };

    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: orionMotionDuration(
          context,
          const Duration(milliseconds: 160),
        ),
        reverseDuration: orionMotionDuration(
          context,
          const Duration(milliseconds: 140),
        ),
        child: _visible && message != null
            ? CommandFrame(
                key: const ValueKey('command-toast'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                color: uiTheme.hullBlack,
                borderColor: toneColor,
                emphasized: true,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _renderText,
                  builder: (context, renderText, _) => renderText
                      ? Text(
                          message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textScaler: textScaler,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: toneColor,
                                fontWeight: FontWeight.w700,
                              ),
                        )
                      : const SizedBox.shrink(),
                ),
              )
            : const SizedBox.shrink(key: ValueKey('command-toast-hidden')),
      ),
    );
  }

  _ToastTone _toneFor(String message) {
    final lowercase = message.toLowerCase();
    if (lowercase.contains('failed') || lowercase.startsWith('could not')) {
      return _ToastTone.danger;
    }
    if (lowercase.contains('not enough') ||
        lowercase.contains('locked') ||
        lowercase.contains('cannot')) {
      return _ToastTone.warning;
    }
    return _ToastTone.neutral;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _renderText.dispose();
    super.dispose();
  }
}

enum _ToastTone { danger, warning, neutral }
