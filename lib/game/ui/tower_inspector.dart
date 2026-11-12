import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../util/format.dart';
import 'orion_surface.dart';
import 'hold_to_salvage.dart';
import 'orion_atlas_sprite.dart';
import 'orion_primary_button.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';
import 'tower_stat_scale.dart';

class TowerInspector extends StatelessWidget {
  const TowerInspector({
    super.key,
    required this.snapshot,
    required this.onUpgrade,
    required this.onSpecialize,
    required this.onTargetingChanged,
    required this.onSell,
    required this.sellRefund,
    this.onClose,
  });

  final GameSnapshot snapshot;
  final VoidCallback onUpgrade;
  final ValueChanged<TowerSpecialization> onSpecialize;
  final ValueChanged<TowerTargetingMode> onTargetingChanged;
  final VoidCallback onSell;
  final int sellRefund;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final tower = snapshot.selectedTower;
    if (tower == null) return const SizedBox.shrink();

    final maxHeight = math.min(480.0, MediaQuery.sizeOf(context).height * .78);
    final uiTheme = OrionUiTheme.of(context);
    final canMutate = snapshot.phase == GamePhase.build;
    return FocusScope(
      autofocus: true,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: OrionSurface(
          role: OrionSurfaceRole.sheet,
          radius: 26,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: SizedBox(
            key: const ValueKey('tower-inspector'),
            width: double.infinity,
            height: maxHeight,
            child: Material(
              color: Colors.transparent,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: uiTheme.frameSteel,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        key: const ValueKey('tower-inspector-hero'),
                        width: 70,
                        height: 70,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: uiTheme.panelRaised,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: uiTheme.systemCyanStrong.withValues(
                              alpha: 0.45,
                            ),
                            width: 1.5,
                          ),
                        ),
                        child: OrionAtlasSprite(
                          art: OrionArt.tower(tower.type),
                          size: const Size(56, 56),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OrionTitle(
                              tower.type.label,
                              size: 22,
                              color: uiTheme.textPrimary,
                            ),
                            const SizedBox(height: 2),
                            OrionText.micro(
                              tower.specialization == null
                                  ? 'Level ${tower.level}'
                                  : 'Level ${tower.level} • '
                                        '${tower.specialization!.label}',
                              color: uiTheme.textMuted,
                              size: 10,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      HoldToSalvage(
                        key: ValueKey('salvage-${tower.id}'),
                        compact: true,
                        refund: sellRefund,
                        onSell: canMutate ? onSell : null,
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        autofocus: true,
                        tooltip: 'Close tower inspector',
                        onPressed: onClose,
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _InspectorBodyViewport(
                      child: _InspectorBody(
                        snapshot: snapshot,
                        tower: tower,
                        onSpecialize: onSpecialize,
                        onTargetingChanged: onTargetingChanged,
                      ),
                    ),
                  ),
                  _ProgressionFooter(
                    snapshot: snapshot,
                    tower: tower,
                    canMutate: canMutate,
                    onUpgrade: onUpgrade,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InspectorBodyViewport extends StatefulWidget {
  const _InspectorBodyViewport({required this.child});

  final Widget child;

  @override
  State<_InspectorBodyViewport> createState() => _InspectorBodyViewportState();
}

class _InspectorBodyViewportState extends State<_InspectorBodyViewport> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _controller,
    thumbVisibility: true,
    child: SingleChildScrollView(
      key: const ValueKey('tower-inspector-scroll'),
      controller: _controller,
      padding: const EdgeInsets.only(right: 8),
      child: widget.child,
    ),
  );
}

class _InspectorBody extends StatelessWidget {
  const _InspectorBody({
    required this.snapshot,
    required this.tower,
    required this.onSpecialize,
    required this.onTargetingChanged,
  });

  final GameSnapshot snapshot;
  final PlacedTower tower;
  final ValueChanged<TowerSpecialization> onSpecialize;
  final ValueChanged<TowerTargetingMode> onTargetingChanged;

  @override
  Widget build(BuildContext context) {
    final stats = snapshot.selectedTowerStats;
    final scale = TowerStatScale.forType(tower.type);
    final canMutate = snapshot.phase == GamePhase.build;
    final uiTheme = OrionUiTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _TargetingActions(
          tower: tower,
          canMutate: canMutate,
          onTargetingChanged: onTargetingChanged,
        ),
        if (stats != null) ...[
          const SizedBox(height: 14),
          _StatRow(
            key: const ValueKey('tower-stat-damage'),
            label: 'Damage',
            value: number(stats.damage),
            fill: scale.damageFill(stats),
            accent: uiTheme.dangerRed,
          ),
          _StatRow(
            key: const ValueKey('tower-stat-fire'),
            label: 'Fire',
            value: '${cadence(stats.fireInterval)}s',
            fill: scale.fireFill(stats),
            accent: uiTheme.creditGold,
          ),
          _StatRow(
            key: const ValueKey('tower-stat-range'),
            label: 'Range',
            value: number(stats.range),
            fill: scale.rangeFill(stats),
            accent: uiTheme.systemCyan,
          ),
          if (scale.secondaryMetric case final metric?)
            _StatRow(
              key: const ValueKey('tower-stat-secondary'),
              label: _secondaryMetricLabel(metric),
              value: _secondaryMetricValue(metric, stats),
              fill: scale.secondaryFill(stats) ?? 0,
              accent: uiTheme.systemViolet,
            ),
        ],
        const SizedBox(height: 20),
        _ProgressionActions(
          snapshot: snapshot,
          tower: tower,
          stats: stats,
          canMutate: canMutate,
          onSpecialize: onSpecialize,
        ),
      ],
    );
  }
}

String _secondaryMetricLabel(TowerSecondaryMetric metric) => switch (metric) {
  TowerSecondaryMetric.chainCount => 'Chain',
  TowerSecondaryMetric.pierceCount => 'Pierce',
  TowerSecondaryMetric.slowDuration => 'Slow',
  TowerSecondaryMetric.splashRadius => 'Splash',
  TowerSecondaryMetric.corrosionDamagePerSecond => 'Corrosion',
  TowerSecondaryMetric.droneDamage => 'Drone dmg',
};

String _secondaryMetricValue(TowerSecondaryMetric metric, TowerStats stats) {
  final value = number(metric.valueOf(stats));
  return switch (metric) {
    TowerSecondaryMetric.slowDuration => '${value}s',
    TowerSecondaryMetric.chainCount ||
    TowerSecondaryMetric.pierceCount ||
    TowerSecondaryMetric.splashRadius => value,
    TowerSecondaryMetric.corrosionDamagePerSecond => '$value/s',
    TowerSecondaryMetric.droneDamage => value,
  };
}

typedef _PreviewRow = ({String label, String from, String to});

/// Tower-specific mechanics that an upgrade can change but that the four
/// inspector metrics don't show. Shot speed is included because a slower shot
/// can miss a target that dies or leaves first. The specialization-only damage
/// multipliers are left out: each specialization's role sentence explains them.
final List<({String label, String Function(TowerStats stats) format})>
_mechanicMetrics = [
  (label: 'Shot speed', format: (s) => number(s.projectileSpeed)),
  (label: 'Splash', format: (s) => number(s.splashRadius)),
  (label: 'Slow', format: (s) => '${number(s.slowDuration)}s'),
  (label: 'Slow power', format: (s) => percent(1 - s.slowMultiplier)),
  (label: 'Pierce', format: (s) => '${s.pierceCount}'),
  (label: 'Pierce width', format: (s) => number(s.pierceWidth)),
  (label: 'Chain', format: (s) => '${s.chainCount}'),
  (label: 'Chain range', format: (s) => number(s.chainRange)),
  (label: 'Chain dmg', format: (s) => percent(s.chainFalloff)),
  (
    label: 'Corrosion',
    format: (s) => '${number(s.corrosionDamagePerSecond)}/s',
  ),
  (label: 'Corrode time', format: (s) => '${number(s.corrosionDuration)}s'),
  (label: 'Shred', format: (s) => percent(s.armorShred)),
  (label: 'Field', format: (s) => number(s.fieldRadius)),
  (label: 'Field time', format: (s) => '${number(s.fieldDuration)}s'),
  (label: 'Field pulse', format: (s) => '${cadence(s.fieldTickInterval)}s'),
  (label: 'Drones', format: (s) => '${s.droneCount}'),
  (label: 'Max drones', format: (s) => '${s.maxActiveDrones}'),
  (label: 'Drone dmg', format: (s) => number(s.droneDamage)),
  (label: 'Drone life', format: (s) => '${number(s.droneLifetime)}s'),
  (label: 'Drone fire', format: (s) => '${cadence(s.droneAttackInterval)}s'),
];

/// Formats the inspector metrics that differ between two already-resolved
/// stat blocks. Rows whose formatted values match are dropped so rounding
/// never shows a no-op change. With [includeMechanics], tower-specific
/// mechanics follow the four inspector metrics; the upgrade preview needs
/// them because, unlike a specialization card, it has no role sentence.
List<_PreviewRow> _previewRows(
  TowerStats current,
  TowerStats candidate, {
  bool includeMechanics = false,
}) {
  final metric = TowerStatScale.forType(current.type).secondaryMetric;
  final rows = <_PreviewRow>[
    (
      label: 'Damage',
      from: number(current.damage),
      to: number(candidate.damage),
    ),
    (
      label: 'Fire',
      from: '${cadence(current.fireInterval)}s',
      to: '${cadence(candidate.fireInterval)}s',
    ),
    (label: 'Range', from: number(current.range), to: number(candidate.range)),
    if (metric != null)
      (
        label: _secondaryMetricLabel(metric),
        from: _secondaryMetricValue(metric, current),
        to: _secondaryMetricValue(metric, candidate),
      ),
    if (includeMechanics)
      for (final mechanic in _mechanicMetrics)
        if (metric == null || mechanic.label != _secondaryMetricLabel(metric))
          (
            label: mechanic.label,
            from: mechanic.format(current),
            to: mechanic.format(candidate),
          ),
  ];
  return [
    for (final row in rows)
      if (row.from != row.to) row,
  ];
}

String _spokenValue(String value) {
  if (value.endsWith('/s')) {
    return '${value.substring(0, value.length - 2)} per second';
  }
  if (value.endsWith('s')) {
    return '${value.substring(0, value.length - 1)} seconds';
  }
  return value;
}

String _spokenRows(List<_PreviewRow> rows) => rows
    .map(
      (row) =>
          '${row.label} ${_spokenValue(row.from)} to ${_spokenValue(row.to)}',
    )
    .join('. ');

class _StatPreview extends StatelessWidget {
  const _StatPreview({super.key, required this.rows, this.centered = false});

  final List<_PreviewRow> rows;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${row.label.toUpperCase()} ',
                    style: OrionTypography.microLabel(
                      size: 10,
                      color: uiTheme.textMuted,
                    ),
                  ),
                  TextSpan(
                    text: '${row.from} → ${row.to}',
                    style: OrionTypography.readout(
                      size: 13,
                      color: uiTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              textAlign: centered ? TextAlign.center : TextAlign.start,
            ),
          ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    super.key,
    required this.label,
    required this.value,
    required this.fill,
    required this.accent,
  });

  final String label;
  final String value;
  final double fill;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Semantics(
      label: '$label $value',
      readOnly: true,
      container: true,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          children: [
            SizedBox(
              width: 84,
              child: Text(
                label.toUpperCase(),
                style: OrionTypography.microLabel(
                  size: 10,
                  color: uiTheme.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: fill.clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: uiTheme.frameSteel.withValues(alpha: .5),
                  color: accent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 52,
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: OrionTypography.readout(
                      size: 15,
                      color: uiTheme.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressionFooter extends StatelessWidget {
  const _ProgressionFooter({
    required this.snapshot,
    required this.tower,
    required this.canMutate,
    required this.onUpgrade,
  });

  final GameSnapshot snapshot;
  final PlacedTower tower;
  final bool canMutate;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final stats = snapshot.selectedTowerStats;
    final Widget? action;
    if (tower.isMaxLevel) {
      action = OrionPrimaryButton(
        onPressed: null,
        icon: Icons.check,
        label: 'Max',
        height: 48,
      );
    } else if (tower.canUpgrade) {
      final cost = stats?.upgradeCost;
      final enabled =
          canMutate && stats != null && snapshot.gold >= stats.upgradeCost;
      final label = cost == null ? 'Upgrade' : 'Upgrade $cost';
      action = Semantics(
        key: const ValueKey('tower-upgrade'),
        button: true,
        enabled: enabled,
        label: label,
        onTap: enabled ? onUpgrade : null,
        excludeSemantics: true,
        child: OrionPrimaryButton(
          onPressed: enabled ? onUpgrade : null,
          icon: Icons.upgrade,
          label: label,
          height: 48,
        ),
      );
    } else {
      action = null;
    }
    if (action == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: uiTheme.frameSteel.withValues(alpha: .6)),
        ),
      ),
      child: action,
    );
  }
}

class _ProgressionActions extends StatelessWidget {
  const _ProgressionActions({
    required this.snapshot,
    required this.tower,
    required this.stats,
    required this.canMutate,
    required this.onSpecialize,
  });

  final GameSnapshot snapshot;
  final PlacedTower tower;
  final TowerStats? stats;
  final bool canMutate;
  final ValueChanged<TowerSpecialization> onSpecialize;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    if (tower.isMaxLevel) {
      return const SizedBox.shrink();
    }

    final resolvedStats = stats;
    if (tower.canUpgrade) {
      final candidate = snapshot.selectedTowerUpgradeStats;
      final rows = resolvedStats == null || candidate == null
          ? const <_PreviewRow>[]
          : _previewRows(resolvedStats, candidate, includeMechanics: true);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          OrionText.micro(
            'UPGRADE - LV ${tower.level + 1}',
            color: uiTheme.textMuted,
            size: 11,
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 4),
            Semantics(
              label: 'Upgrade preview. ${_spokenRows(rows)}',
              readOnly: true,
              container: true,
              excludeSemantics: true,
              child: _StatPreview(
                key: const ValueKey('tower-upgrade-preview'),
                rows: rows,
              ),
            ),
          ],
        ],
      );
    }

    final cost = resolvedStats?.specializationCost;
    final enabled =
        canMutate &&
        resolvedStats != null &&
        snapshot.gold >= resolvedStats.specializationCost;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        OrionText.micro(
          'SPECIALIZE - LV ${tower.level + 1}',
          color: uiTheme.textMuted,
          size: 11,
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, specialization)
                in GameBalance.specializationsFor(tower.type).indexed) ...[
              if (index > 0) const SizedBox(width: 8),
              Expanded(
                child: _SpecializationCard(
                  towerType: tower.type,
                  specialization: specialization,
                  currentStats: resolvedStats,
                  candidateStats:
                      snapshot.selectedTowerSpecializationStats[specialization],
                  cost: cost,
                  enabled: enabled,
                  onSpecialize: onSpecialize,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _SpecializationCard extends StatelessWidget {
  const _SpecializationCard({
    required this.towerType,
    required this.specialization,
    required this.currentStats,
    required this.candidateStats,
    required this.cost,
    required this.enabled,
    required this.onSpecialize,
  });

  final TowerType towerType;
  final TowerSpecialization specialization;
  final TowerStats? currentStats;
  final TowerStats? candidateStats;
  final int? cost;
  final bool enabled;
  final ValueChanged<TowerSpecialization> onSpecialize;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final current = currentStats;
    final candidate = candidateStats;
    final rows = current == null || candidate == null
        ? const <_PreviewRow>[]
        : _previewRows(current, candidate);
    final title = cost == null
        ? specialization.label
        : '${specialization.label} $cost';
    return Semantics(
      key: ValueKey('tower-specialization-${specialization.name}'),
      button: true,
      enabled: enabled,
      onTap: enabled ? () => onSpecialize(specialization) : null,
      excludeSemantics: true,
      label: [
        '$title. ${specialization.role}',
        if (rows.isNotEmpty) _spokenRows(rows),
      ].join(' '),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? () => onSpecialize(specialization) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: uiTheme.panelRaised.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled
                  ? uiTheme.systemViolet.withValues(alpha: 0.55)
                  : uiTheme.frameSteel.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OrionAtlasSprite(
                art: OrionArt.specialization(specialization),
                size: const Size(62, 62),
              ),
              const SizedBox(height: 6),
              Text(
                specialization.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: OrionTypography.microLabel(
                  size: 11,
                  color: uiTheme.systemViolet,
                ),
              ),
              const SizedBox(height: 2),
              if (cost != null)
                Text(
                  '$cost',
                  style: OrionTypography.readout(
                    size: 16,
                    color: uiTheme.creditGold,
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                specialization.role,
                textAlign: TextAlign.center,
                style: OrionTypography.microLabel(
                  size: 10,
                  color: uiTheme.textMuted,
                ),
              ),
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 4),
                _StatPreview(
                  key: ValueKey(
                    'tower-specialization-preview-${specialization.name}',
                  ),
                  rows: rows,
                  centered: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetingActions extends StatelessWidget {
  const _TargetingActions({
    required this.tower,
    required this.canMutate,
    required this.onTargetingChanged,
  });

  final PlacedTower tower;
  final bool canMutate;
  final ValueChanged<TowerTargetingMode> onTargetingChanged;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final modes = TowerTargetingMode.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        OrionText.micro('Targeting', color: uiTheme.textMuted, size: 11),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final style = OrionTypography.microLabel(
              size: 11,
              color: uiTheme.textMuted,
            );
            final scaler = MediaQuery.textScalerOf(context);
            var widest = 0.0;
            for (final mode in modes) {
              final painter = TextPainter(
                text: TextSpan(text: mode.label, style: style),
                textDirection: TextDirection.ltr,
                textScaler: scaler,
              )..layout();
              widest = math.max(widest, painter.width);
              painter.dispose();
            }
            const cellPadding = 12.0;
            const selectedIcon = 16.0;
            final needed = widest + cellPadding + selectedIcon;
            var columns = 3;
            while (columns > 1 &&
                (constraints.maxWidth - (columns - 1) * 8.0) / columns <
                    needed) {
              columns--;
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var row = 0; row * columns < modes.length; row++) ...[
                  if (row > 0) const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var col = 0; col < columns; col++) ...[
                        if (col > 0) const SizedBox(width: 8),
                        if (row * columns + col < modes.length)
                          Expanded(
                            child: _TargetingCell(
                              mode: modes[row * columns + col],
                              selected:
                                  tower.targetingMode ==
                                  modes[row * columns + col],
                              enabled: canMutate,
                              onTap: () => onTargetingChanged(
                                modes[row * columns + col],
                              ),
                            ),
                          )
                        else
                          const Spacer(),
                      ],
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

String _targetingTooltip(TowerTargetingMode mode) => switch (mode) {
  TowerTargetingMode.first => 'Target the enemy furthest along the path',
  TowerTargetingMode.strongest => 'Target the enemy with the highest health',
  TowerTargetingMode.weakest => 'Target the enemy with the lowest health',
  TowerTargetingMode.closest => 'Target the enemy closest to this tower',
  TowerTargetingMode.shielded => 'Target shielded enemies first',
  TowerTargetingMode.armored => 'Target armored enemies first',
};

class _TargetingCell extends StatelessWidget {
  const _TargetingCell({
    required this.mode,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final TowerTargetingMode mode;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final radius = BorderRadius.circular(10);
    return Semantics(
      key: ValueKey('tower-target-${mode.name}'),
      button: true,
      enabled: enabled,
      selected: selected,
      label: mode.label,
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: Tooltip(
        message: _targetingTooltip(mode),
        child: Material(
          color: selected
              ? uiTheme.systemCyan.withValues(alpha: 0.10)
              : uiTheme.hullBlack.withValues(alpha: 0.55),
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: enabled ? onTap : null,
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: selected
                      ? uiTheme.systemCyan
                      : uiTheme.frameSteel.withValues(alpha: 0.7),
                  width: 1.5,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: uiTheme.systemCyan.withValues(alpha: 0.25),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    Icon(Icons.check, size: 12, color: uiTheme.systemCyan),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      mode.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OrionTypography.microLabel(
                        size: 11,
                        color: !enabled
                            ? uiTheme.textDim
                            : selected
                            ? uiTheme.systemCyan
                            : uiTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
