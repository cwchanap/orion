import 'package:flutter/material.dart';

import 'orion_typography.dart';
import 'orion_ui_theme.dart';

/// The destinations the shared menu shell switches between. Title and stage
/// stay outside the shell: the title is the front door, the stage is gameplay.
enum OrionMenuDestination { map, techTree, codex }

/// Shared menu chrome for the campaign screens (artboards 02/07/08): a faded
/// top bar with the destination title, resource chips, and the Settings
/// entry, over a bottom Map/R&D/Codex tab bar. Each destination renders only
/// its body inside the middle of this column — no nested Scaffold chrome.
class OrionMenuShell extends StatelessWidget {
  const OrionMenuShell({
    super.key,
    required this.destination,
    required this.onDestinationSelected,
    this.navigationEnabled = true,
    required this.medalRank,
    required this.medalRankMax,
    required this.researchPoints,
    this.onOpenSettings,
    this.feedback,
    required this.child,
  });

  final OrionMenuDestination destination;
  final ValueChanged<OrionMenuDestination> onDestinationSelected;

  /// Save/reset busy states freeze destination switching, mirroring the
  /// retired utility rail's disabled buttons.
  final bool navigationEnabled;
  final int medalRank;
  final int medalRankMax;
  final int researchPoints;

  /// Null keeps the Settings gear disabled (preferences still loading or a
  /// preference save in flight).
  final VoidCallback? onOpenSettings;

  /// Shell-level breadcrumb (e.g. the feedback-save failure) shown under
  /// the top bar on every destination — the map/title feedback slots do not
  /// cover the other bodies.
  final String? feedback;

  final Widget child;

  String get _title => switch (destination) {
    OrionMenuDestination.map => 'Sector map',
    OrionMenuDestination.techTree => 'R & D',
    OrionMenuDestination.codex => 'Codex',
  };

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final onMap = destination == OrionMenuDestination.map;
    return Scaffold(
      backgroundColor: uiTheme.voidBlack,
      body: Column(
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(gradient: orionTopBarFade),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 60,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  // Dense shell chrome follows the map's 1.3x clamp so
                  // large system text never bursts the fixed bar height.
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Row(
                      children: [
                        if (!onMap)
                          IconButton(
                            tooltip: 'Back',
                            onPressed: navigationEnabled
                                ? () => onDestinationSelected(
                                    OrionMenuDestination.map,
                                  )
                                : null,
                            icon: Icon(
                              Icons.arrow_back_rounded,
                              color: uiTheme.systemCyan,
                            ),
                          )
                        else
                          const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Orion campaign',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: OrionTypography.microLabel(
                                  color: uiTheme.textDim,
                                  size: 10,
                                ),
                              ),
                              const SizedBox(height: 2),
                              OrionTitle(
                                _title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                color: uiTheme.textPrimary,
                                size: 19,
                              ),
                            ],
                          ),
                        ),
                        _ShellChip(
                          icon: Icons.emoji_events_rounded,
                          value: '$medalRank/$medalRankMax',
                          color: uiTheme.creditGold,
                        ),
                        const SizedBox(width: 8),
                        _ShellChip(
                          icon: Icons.science_rounded,
                          value: '$researchPoints',
                          color: uiTheme.systemViolet,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Settings',
                          onPressed: onOpenSettings,
                          icon: Icon(
                            Icons.settings_rounded,
                            color: onOpenSettings == null
                                ? uiTheme.textDim
                                : uiTheme.systemCyan,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (feedback != null)
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                color: uiTheme.dangerRed.withValues(alpha: 0.16),
                child: Row(
                  children: [
                    Icon(Icons.sensors, size: 13, color: uiTheme.warningOrange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        feedback!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OrionTypography.microLabel(
                          color: uiTheme.warningOrange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            // Destinations own their SafeArea for standalone mounts; inside
            // the shell the bar above already consumed the top inset and the
            // tab bar below pads the bottom one.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: child,
            ),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: orionTabBarFill,
              border: Border(top: BorderSide(color: orionShelfEdge)),
            ),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: SizedBox(
                height: 58,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Row(
                    children: [
                      _ShellTab(
                        tooltip: 'Sectors',
                        label: 'Map',
                        icon: Icons.map_rounded,
                        active: onMap,
                        color: uiTheme.systemCyan,
                        onTap: navigationEnabled
                            ? () => onDestinationSelected(
                                OrionMenuDestination.map,
                              )
                            : null,
                      ),
                      _ShellTab(
                        tooltip: 'Tech Tree',
                        label: 'R&D',
                        icon: Icons.science_rounded,
                        active: destination == OrionMenuDestination.techTree,
                        color: uiTheme.systemViolet,
                        onTap: navigationEnabled
                            ? () => onDestinationSelected(
                                OrionMenuDestination.techTree,
                              )
                            : null,
                      ),
                      _ShellTab(
                        tooltip: 'Codex',
                        label: 'Codex',
                        icon: Icons.menu_book_rounded,
                        active: destination == OrionMenuDestination.codex,
                        color: uiTheme.systemCyan,
                        onTap: navigationEnabled
                            ? () => onDestinationSelected(
                                OrionMenuDestination.codex,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One destination's top-bar resource chip: icon plus readout value.
class _ShellChip extends StatelessWidget {
  const _ShellChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(value, style: OrionTypography.readout(size: 11, color: color)),
          ],
        ),
      ),
    );
  }
}

/// One tab-bar entry: a top accent tick, glyph, and micro label. The tab owns
/// its own Semantics button so screen readers announce destination + state.
class _ShellTab extends StatelessWidget {
  const _ShellTab({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final tint = onTap == null
        ? uiTheme.textDim.withValues(alpha: 0.5)
        : active
        ? color
        : uiTheme.textDim;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: tooltip,
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onTap,
            child: Column(
              children: [
                Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: active ? color : Colors.transparent,
                    boxShadow: active
                        ? [BoxShadow(color: color, blurRadius: 8)]
                        : null,
                  ),
                ),
                const SizedBox(height: 7),
                Icon(
                  icon,
                  size: 20,
                  color: tint,
                  shadows: active
                      ? [
                          Shadow(
                            color: color.withValues(alpha: .55),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  style: OrionTypography.microLabel(size: 10, color: tint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
