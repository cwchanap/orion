import 'package:flutter/material.dart';

import 'orion_ui_theme.dart';

typedef MissionCollapsibleBuilder =
    Widget Function(BuildContext context, VoidCallback toggle);

/// Shared in-tree collapse invariant for mission chrome: an optional expanded
/// state that toggles in place, snaps closed when [collapseRequested] rises or
/// [resetToken] changes, keeps only the current child in the layout while
/// switching (the outgoing child is never hit-testable), blocks pointer input
/// while collapse is requested, and switches in zero duration under Reduced
/// Motion.
class MissionCollapsible extends StatefulWidget {
  const MissionCollapsible({
    super.key,
    required this.collapseRequested,
    required this.collapsedBuilder,
    required this.expandedBuilder,
    this.resetToken,
    this.onExpandedChanged,
  });

  final bool collapseRequested;
  final Object? resetToken;
  final MissionCollapsibleBuilder collapsedBuilder;
  final MissionCollapsibleBuilder expandedBuilder;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<MissionCollapsible> createState() => _MissionCollapsibleState();
}

class _MissionCollapsibleState extends State<MissionCollapsible> {
  bool _expanded = false;

  void _toggle() {
    if (widget.collapseRequested) return;
    setState(() => _expanded = !_expanded);
    widget.onExpandedChanged?.call(_expanded);
  }

  @override
  void didUpdateWidget(covariant MissionCollapsible oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken ||
        (!oldWidget.collapseRequested && widget.collapseRequested)) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: widget.collapseRequested,
      child: AnimatedSwitcher(
        duration: orionMotionDuration(
          context,
          const Duration(milliseconds: 180),
        ),
        // Keep only the current child in the layout while switching. The
        // default Stack layout keeps the outgoing expanded detector
        // hit-testable for the fade duration, even after a board/tower
        // selection requests an immediate collapse.
        layoutBuilder: (currentChild, _) =>
            currentChild ?? const SizedBox.shrink(),
        child: KeyedSubtree(
          key: ValueKey(_expanded ? 'expanded' : 'collapsed'),
          child: _expanded
              ? widget.expandedBuilder(context, _toggle)
              : widget.collapsedBuilder(context, _toggle),
        ),
      ),
    );
  }
}
