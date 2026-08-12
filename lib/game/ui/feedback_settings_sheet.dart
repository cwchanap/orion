import 'package:flutter/material.dart';

import '../feedback/feedback_preferences.dart';

/// Self-contained settings sheet for the two persisted feedback toggles.
///
/// Owns only a local draft of the preferences and pops the final value when
/// Done is tapped. Persistence and platform feedback calls live in the
/// page, never here.
class FeedbackSettingsSheet extends StatefulWidget {
  const FeedbackSettingsSheet({
    super.key,
    required this.initialPreferences,
    required this.reduceMotion,
  });

  final FeedbackPreferences initialPreferences;
  final bool reduceMotion;

  @override
  State<FeedbackSettingsSheet> createState() => _FeedbackSettingsSheetState();
}

class _FeedbackSettingsSheetState extends State<FeedbackSettingsSheet> {
  late FeedbackPreferences _draft = widget.initialPreferences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Feedback',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
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
