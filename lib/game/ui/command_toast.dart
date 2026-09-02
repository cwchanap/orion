import 'dart:async';

import 'package:flutter/material.dart';

import 'mission_surface.dart';
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
  GlobalKey<_CommandToastMessageState>? _messageKey;
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
    // A duration change re-arms the live toast even when the message is
    // unchanged; a new message restarts the timer itself in _accept.
    if (_visible && widget.visibleDuration != oldWidget.visibleDuration) {
      _startTimer();
    }
    _accept(widget.feedback, notify: true);
  }

  // Every non-null input is a feedback event, including repeats: the game
  // only republishes non-null feedback from a fresh player action (timer
  // driven publishes pass null), so two identical strings back to back mean
  // the player repeated the rejected action and must see the toast again.
  // Null keeps the current toast latched until its timer expires.
  void _accept(String? input, {required bool notify}) {
    if (input == null) return;

    final wasVisible = _visible;
    void updateState() {
      _latchedMessage = input;
      _visible = true;
      if (!wasVisible || _messageKey == null) {
        _messageKey = GlobalKey<_CommandToastMessageState>();
      }
    }

    if (notify) {
      setState(updateState);
    } else {
      updateState();
    }
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(widget.visibleDuration, () {
      if (!mounted) return;
      _messageKey?.currentState?.hideText();
      setState(() => _visible = false);
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

    final toast = _visible && message != null
        ? _CommandToastMessage(
            key: _messageKey,
            message: message,
            toneColor: toneColor,
            textScaler: textScaler,
          )
        : const SizedBox.shrink(key: ValueKey('command-toast-hidden'));

    final maxToastWidth = (MediaQuery.sizeOf(context).width - 32)
        .clamp(0.0, double.infinity)
        .toDouble();

    return IgnorePointer(
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxToastWidth),
          child: AnimatedSwitcher(
            duration: orionMotionDuration(
              context,
              const Duration(milliseconds: 160),
            ),
            reverseDuration: orionMotionDuration(
              context,
              const Duration(milliseconds: 140),
            ),
            child: toast,
          ),
        ),
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
    super.dispose();
  }
}

class _CommandToastMessage extends StatefulWidget {
  const _CommandToastMessage({
    super.key,
    required this.message,
    required this.toneColor,
    required this.textScaler,
  });

  final String message;
  final Color toneColor;
  final TextScaler textScaler;

  @override
  State<_CommandToastMessage> createState() => _CommandToastMessageState();
}

class _CommandToastMessageState extends State<_CommandToastMessage> {
  bool _renderText = true;

  void hideText() {
    if (!mounted || !_renderText) return;
    setState(() => _renderText = false);
  }

  @override
  Widget build(BuildContext context) {
    return MissionSurface(
      key: const ValueKey('command-toast'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      radius: 12,
      borderColor: widget.toneColor,
      emphasized: true,
      child: _renderText
          ? Semantics(
              container: true,
              liveRegion: true,
              label: widget.message,
              excludeSemantics: true,
              child: Text(
                widget.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textScaler: widget.textScaler,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: widget.toneColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

enum _ToastTone { danger, warning, neutral }
