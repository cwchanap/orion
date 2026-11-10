import 'package:flutter/material.dart';

import 'orion_typography.dart';
import 'orion_ui_theme.dart';

/// The menu destinations the shared shell switches between. The page owns
/// which view is mounted for each destination; the shell only reports taps
/// and renders which destination is active.
enum OrionMenuDestination { sectors, research, codex }

/// Shared chrome around the map, R&D, and codex views: a top bar carrying
/// the campaign resource chips plus the Settings action, a persistent
/// breadcrumb line, and a bottom Map / R&D / Codex tab bar. One Scaffold
/// owns the SafeArea insets so the embedded views stay flat bodies instead
/// of nested scaffolds — a view's own SafeArea resolves to a no-op inside
/// [child] because the shell strips ambient padding first.
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

  /// Which tab reads as active; the page swaps [child] on selection.
  final OrionMenuDestination destination;

  /// Campaign medals earned (main-path medal ranks total).
  final int medalEarned;

  /// Campaign medals available (main-path count x3).
  final int medalTotal;

  /// Unspent research points shown in the top bar.
  final int researchPoints;

  /// Reports a tab tap; the page decides whether to switch views.
  final ValueChanged<OrionMenuDestination> onDestinationSelected;

  /// Settings gear tap; null renders the gear disabled.
  final VoidCallback? onOpenSettings;

  /// The view body for the active destination.
  final Widget child;

  /// False while a campaign save/reset is in flight: the tabs stay visible
  /// but inert so navigation cannot interleave with a write.
  final bool navigationEnabled;

  /// False while a feedback-preferences save is in flight: only the
  /// settings gear is inert — map destinations stay available.
  final bool settingsEnabled;

  /// Transient status line shared by every destination (locked-stage,
  /// persistence, and save breadcrumbs), rendered under the top bar.
  final String? feedback;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Scaffold(
      backgroundColor: uiTheme.voidBlack,
      body: Column(
        children: [
          _TopBar(
            medalEarned: medalEarned,
            medalTotal: medalTotal,
            researchPoints: researchPoints,
            onOpenSettings: settingsEnabled ? onOpenSettings : null,
          ),
          if (feedback != null) _FeedbackLine(message: feedback!),
          Expanded(
            // The shell's own SafeArea already consumed every ambient inset,
            // so an embedded view's own SafeArea must not double-apply them.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              removeLeft: true,
              removeRight: true,
              child: child,
            ),
          ),
          _TabBar(
            destination: destination,
            onDestinationSelected: onDestinationSelected,
            enabled: navigationEnabled,
          ),
        ],
      ),
    );
  }
}

/// `.topbar` from the kit: a flat dark plate, resource chips left, the
/// Settings gear pinned right.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.medalEarned,
    required this.medalTotal,
    required this.researchPoints,
    required this.onOpenSettings,
  });

  final int medalEarned;
  final int medalTotal;
  final int researchPoints;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
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
              semanticsLabel: '$researchPoints research points',
            ),
            const Spacer(),
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

/// `.chip` from the kit: a compact rounded plate carrying one icon + a
/// count. Shared by the shell's top bar and the title's campaign card.
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
                // The chip is a fixed 28px slot; unbounded system text
                // would burst the top bar. Same dense-chrome clamp the
                // map uses.
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

/// The small ghost-plate icon button used for the Settings gear. Kit's
/// `.btn.ghost` compressed to a 40px square.
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
          child: Ink(
            decoration: BoxDecoration(
              gradient: orionGhostFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: orionGhostEdge),
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(icon, size: 20, color: uiTheme.textMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.tabbar` from the kit: three tabs pinned to the bottom edge. The active
/// tab takes the ghost plate; the rest stay quiet muted.
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
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
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
    return Expanded(
      child: Semantics(
        button: true,
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
              child: Ink(
                decoration: BoxDecoration(
                  gradient: selected ? orionGhostFill : null,
                  borderRadius: BorderRadius.circular(14),
                  border: selected ? Border.all(color: orionGhostEdge) : null,
                ),
                child: InkWell(
                  onTap: active ? () => onTap(destination) : null,
                  borderRadius: BorderRadius.circular(14),
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            icon,
                            size: 18,
                            color: selected
                                ? uiTheme.textPrimary
                                : uiTheme.textMuted,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            // A third of the bar is ~97px on a phone; the
                            // label clamps like the other dense-chrome text
                            // instead of bleeding off its tab.
                            textScaler: MediaQuery.textScalerOf(
                              context,
                            ).clamp(maxScaleFactor: 1.3),
                            style: OrionTypography.microLabel(
                              size: 10.5,
                              // microLabel is muted-only; the active tab
                              // takes the system's navigation accent
                              // instead of the kit's literal white.
                              color: selected
                                  ? uiTheme.systemCyan
                                  : uiTheme.textMuted,
                            ).copyWith(letterSpacing: 1.05),
                          ),
                        ],
                      ),
                    ),
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

/// The persistent breadcrumb under the top bar — same role the map's old
/// fixed-header feedback line played, now shared by every destination.
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
