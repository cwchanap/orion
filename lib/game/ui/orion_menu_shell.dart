import 'package:flutter/material.dart';

import 'orion_typography.dart';
import 'orion_ui_theme.dart';

enum OrionMenuDestination { sectors, research, codex }

class OrionMenuShell extends StatelessWidget {
  const OrionMenuShell({
    super.key,
    required this.destination,
    required this.medalEarned,
    required this.medalTotal,
    required this.researchPoints,
    required this.onDestinationSelected,
    required this.onOpenSettings,
    required this.child,
    this.navigationEnabled = true,
    this.settingsEnabled = true,
    this.feedback,
  });

  final OrionMenuDestination destination;

  final int medalEarned;

  final int medalTotal;

  final int researchPoints;

  final ValueChanged<OrionMenuDestination> onDestinationSelected;

  final VoidCallback? onOpenSettings;

  final Widget child;

  final bool navigationEnabled;

  final bool settingsEnabled;

  final String? feedback;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    // While the keyboard is open the shell sheds its top chrome so the child
    // and the navigation stay reachable in the shrunken area above it.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: uiTheme.voidBlack,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            children: [
              if (!keyboardOpen)
                _TopBar(
                  destination: destination,
                  medalEarned: medalEarned,
                  medalTotal: medalTotal,
                  researchPoints: researchPoints,
                  onOpenSettings: settingsEnabled ? onOpenSettings : null,
                )
              else
                const SafeArea(
                  left: false,
                  right: false,
                  bottom: false,
                  child: SizedBox.shrink(),
                ),
              if (feedback != null) _FeedbackLine(message: feedback!),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  removeBottom: true,
                  child: child,
                ),
              ),
              // The tab bar sits at the bottom of the body — which the
              // Scaffold shrinks above the keyboard — so it stays reachable
              // while typing. Its slot is capped and scrollable so a
              // degenerate viewport cannot overflow the column.
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: constraints.maxHeight),
                child: SingleChildScrollView(
                  child: _TabBar(
                    destination: destination,
                    onDestinationSelected: onDestinationSelected,
                    enabled: navigationEnabled,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.destination,
    required this.medalEarned,
    required this.medalTotal,
    required this.researchPoints,
    required this.onOpenSettings,
  });

  final OrionMenuDestination destination;
  final int medalEarned;
  final int medalTotal;
  final int researchPoints;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final (kicker, title) = switch (destination) {
      OrionMenuDestination.sectors => ('ORION CAMPAIGN', 'Sector Map'),
      OrionMenuDestination.research => ('CAMPAIGN UPGRADES', 'R&D Lab'),
      OrionMenuDestination.codex => ('FIELD MANUAL', 'Codex'),
    };
    final accent = destination == OrionMenuDestination.research
        ? uiTheme.systemViolet
        : uiTheme.textMuted;
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.15);
    return SafeArea(
      bottom: false,
      child: Container(
        decoration: const BoxDecoration(
          gradient: orionChromePlate,
          border: Border(bottom: BorderSide(color: orionPanelEdge)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kicker,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: textScaler,
                    style: OrionTypography.microLabel(
                      size: 10,
                      color: accent,
                    ).copyWith(letterSpacing: 0.8),
                  ),
                  OrionTitle(
                    title,
                    size: 15,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: textScaler,
                    color: uiTheme.textPrimary,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OrionResourceChip(
              icon: Icons.emoji_events,
              iconColor: uiTheme.creditGold,
              count: '$medalEarned/$medalTotal',
              semanticsLabel: '$medalEarned of $medalTotal campaign medals',
            ),
            const SizedBox(width: 8),
            OrionResourceChip(
              icon: Icons.diamond_rounded,
              iconColor: uiTheme.systemViolet,
              count: '$researchPoints',
              semanticsLabel: destination == OrionMenuDestination.research
                  ? 'Unspent: $researchPoints'
                  : '$researchPoints research points',
            ),
            const SizedBox(width: 8),
            _GhostIconButton(
              tooltip: 'Settings',
              icon: Icons.settings_rounded,
              onPressed: onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class OrionResourceChip extends StatelessWidget {
  const OrionResourceChip({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.count,
    required this.semanticsLabel,
  });

  final IconData icon;
  final Color iconColor;
  final String count;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: orionChipFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: orionPanelEdge, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Text(
                count,
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.3),
                style: OrionTypography.readout(size: 14, color: iconColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostIconButton extends StatelessWidget {
  const _GhostIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Ink(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: orionGhostFill,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: orionGhostEdge),
                  ),
                  child: Icon(icon, size: 20, color: uiTheme.textMuted),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.destination,
    required this.onDestinationSelected,
    required this.enabled,
  });

  final OrionMenuDestination destination;
  final ValueChanged<OrionMenuDestination> onDestinationSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          gradient: orionChromePlate,
          border: Border(top: BorderSide(color: orionPanelEdge)),
        ),
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: Row(
          children: [
            _Tab(
              destination: OrionMenuDestination.sectors,
              icon: Icons.public_rounded,
              label: 'Map',
              selected: destination == OrionMenuDestination.sectors,
              enabled: enabled,
              onTap: onDestinationSelected,
            ),
            _Tab(
              destination: OrionMenuDestination.research,
              icon: Icons.biotech_rounded,
              label: 'R&D',
              selected: destination == OrionMenuDestination.research,
              enabled: enabled,
              onTap: onDestinationSelected,
            ),
            _Tab(
              destination: OrionMenuDestination.codex,
              icon: Icons.menu_book_rounded,
              label: 'Codex',
              selected: destination == OrionMenuDestination.codex,
              enabled: enabled,
              onTap: onDestinationSelected,
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.destination,
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final OrionMenuDestination destination;
  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final ValueChanged<OrionMenuDestination> onTap;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final active = enabled;
    final accent = destination == OrionMenuDestination.research
        ? uiTheme.systemViolet
        : uiTheme.systemCyan;
    return Expanded(
      child: Semantics(
        button: true,
        enabled: active,
        selected: selected,
        label: label,
        child: Tooltip(
          message: label,
          child: Opacity(
            opacity: active ? 1 : 0.5,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: active ? () => onTap(destination) : null,
                borderRadius: BorderRadius.circular(14),
                child: ExcludeSemantics(
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      if (selected)
                        Container(
                          width: 52,
                          height: 3,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.65),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icon,
                              size: 22,
                              color: selected ? accent : uiTheme.textMuted,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              label,
                              textScaler: MediaQuery.textScalerOf(
                                context,
                              ).clamp(maxScaleFactor: 1.3),
                              style: OrionTypography.microLabel(
                                size: 10.5,
                                color: selected ? accent : uiTheme.textMuted,
                              ).copyWith(letterSpacing: 1.05),
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
      ),
    );
  }
}

class _FeedbackLine extends StatelessWidget {
  const _FeedbackLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Container(
      width: double.infinity,
      color: uiTheme.hullBlack.withValues(alpha: 0.72),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Text(
        message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: OrionTypography.microLabel(size: 11, color: uiTheme.textMuted),
      ),
    );
  }
}
