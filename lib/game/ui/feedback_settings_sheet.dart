import 'package:flutter/material.dart';

import '../feedback/feedback_preferences.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';

/// Self-contained settings sheet for the two persisted feedback toggles plus
/// the first-mission tutorial replay action.
///
/// Owns only a local draft of the preferences and pops the final value when
/// Done is tapped. Persistence, platform feedback calls, and the tutorial
/// store live in the page, never here — replay is a plain async callback.
class FeedbackSettingsSheet extends StatefulWidget {
  const FeedbackSettingsSheet({
    super.key,
    required this.initialPreferences,
    required this.reduceMotion,
    this.onReplayTutorial,
  });

  final FeedbackPreferences initialPreferences;
  final bool reduceMotion;

  /// Invoked once per Replay Tutorial tap; null (or an already-confirmed
  /// replay) keeps the action disabled. The page owns whatever the callback
  /// persists.
  final Future<void> Function()? onReplayTutorial;

  @override
  State<FeedbackSettingsSheet> createState() => _FeedbackSettingsSheetState();
}

class _FeedbackSettingsSheetState extends State<FeedbackSettingsSheet> {
  late FeedbackPreferences _draft = widget.initialPreferences;
  bool _isReplayInFlight = false;
  bool _isReplayConfirmed = false;

  Future<void> _replayTutorial() async {
    if (_isReplayInFlight ||
        _isReplayConfirmed ||
        widget.onReplayTutorial == null) {
      return;
    }
    setState(() => _isReplayInFlight = true);
    try {
      await widget.onReplayTutorial!();
      if (mounted) {
        setState(() => _isReplayConfirmed = true);
      }
    } catch (_) {
      // Replay request failed; leave the action enabled for another attempt.
    } finally {
      if (mounted) {
        setState(() => _isReplayInFlight = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    // The row reads disabled unless the page supplied a callback and no
    // replay is in flight or already confirmed.
    final canReplay =
        widget.onReplayTutorial != null &&
        !_isReplayInFlight &&
        !_isReplayConfirmed;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OrionTitle('Settings', color: uiTheme.textPrimary),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Sound Effects'),
                value: _draft.soundEffectsEnabled,
                onChanged: (enabled) {
                  setState(() {
                    _draft = _draft.copyWith(soundEffectsEnabled: enabled);
                  });
                },
              ),
              SwitchListTile(
                title: const Text('Haptics'),
                value: _draft.hapticsEnabled,
                onChanged: (enabled) {
                  setState(() {
                    _draft = _draft.copyWith(hapticsEnabled: enabled);
                  });
                },
              ),
              ListTile(
                title: const Text('Reduced Motion'),
                subtitle: Text(
                  widget.reduceMotion
                      ? 'Follows system • On'
                      : 'Follows system • Off',
                ),
                // Informational only: reduced motion follows the system
                // MediaQuery setting and is not persisted. A plain ListTile
                // with a status icon avoids the disabled-switch look.
                trailing: Semantics(
                  label: widget.reduceMotion
                      ? 'Reduced motion on'
                      : 'Reduced motion off',
                  child: Icon(
                    widget.reduceMotion
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                  ),
                ),
              ),
              ListTile(
                title: const Text('Replay Tutorial'),
                subtitle: _isReplayConfirmed
                    ? const Text(
                        'Tutorial will replay on your next Outpost Alpha run.',
                      )
                    : null,
                enabled: canReplay,
                onTap: canReplay ? _replayTutorial : null,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_draft),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
