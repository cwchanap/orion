import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../util/format.dart';
import 'orion_surface.dart';
import 'hold_to_salvage.dart';
import 'orion_atlas_sprite.dart';
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

    final maxHeight = math.min(600.0, MediaQuery.sizeOf(context).height * .72);
    return FocusScope(
      autofocus: true,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: OrionSurface(
          tier: OrionSurfaceTier.t3,
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
                  Row(
                    children: [
                      const SizedBox(width: 48),
                      const Spacer(),
                      Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: OrionUiTheme.of(context).frameSteel,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        autofocus: true,
                        tooltip: 'Close tower inspector',
                        onPressed: onClose,
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      key: const ValueKey('tower-inspector-scroll'),
                      child: _InspectorBody(
                        snapshot: snapshot,
                        tower: tower,
                        onUpgrade: onUpgrade,
                        onSpecialize: onSpecialize,
                        onTargetingChanged: onTargetingChanged,
                        onSell: onSell,
                        sellRefund: sellRefund,
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

class _InspectorBody extends StatelessWidget {
  const _InspectorBody({
    required this.snapshot,
    required this.tower,
    required this.onUpgrade,
    required this.onSpecialize,
    required this.onTargetingChanged,
    required this.onSell,
    required this.sellRefund,
  });

  final GameSnapshot snapshot;
  final PlacedTower tower;
  final VoidCallback onUpgrade;
  final ValueChanged<TowerSpecialization> onSpecialize;
  final ValueChanged<TowerTargetingMode> onTargetingChanged;
  final VoidCallback onSell;
  final int sellRefund;

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
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              key: const ValueKey('tower-inspector-hero'),
              width: 96,
              height: 96,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: uiTheme.panelRaised,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: uiTheme.frameSteel.withValues(alpha: 0.55),
                ),
              ),
              child: OrionAtlasSprite(
                art: OrionArt.tower(tower.type),
                size: const Size(78, 78),
              ),
            ),
            const SizedBox(width: 8),
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
                    size: 9,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _TargetingActions(
          tower: tower,
          canMutate: canMutate,
          onTargetingChanged: onTargetingChanged,
        ),
        if (stats != null) ...[
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _StatRow(
                  key: const ValueKey('tower-stat-damage'),
                  label: 'Damage',
                  value: number(stats.damage),
                  fill: scale.damageFill(stats),
                  accent: uiTheme.dangerRed,
                ),
              ),
              Expanded(
                child: _StatRow(
                  key: const ValueKey('tower-stat-fire'),
                  label: 'Fire',
                  value: '${cadence(stats.fireInterval)}s',
                  fill: scale.fireFill(stats),
                  accent: uiTheme.creditGold,
                ),
              ),
              Expanded(
                child: _StatRow(
                  key: const ValueKey('tower-stat-range'),
                  label: 'Range',
                  value: number(stats.range),
                  fill: scale.rangeFill(stats),
                  accent: uiTheme.systemCyan,
                ),
              ),
              if (scale.secondaryMetric case final metric?)
                Expanded(
                  child: _StatRow(
                    key: const ValueKey('tower-stat-secondary'),
                    label: _secondaryLabel(metric),
                    value: _secondaryValue(metric, stats),
                    fill: scale.secondaryFill(stats) ?? 0,
                    accent: uiTheme.systemViolet,
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        _ProgressionActions(
          snapshot: snapshot,
          tower: tower,
          stats: stats,
          canMutate: canMutate,
          onUpgrade: onUpgrade,
          onSpecialize: onSpecialize,
        ),
        const SizedBox(height: 16),
        HoldToSalvage(
          key: ValueKey('salvage-${tower.id}'),
          refund: sellRefund,
          onSell: canMutate ? onSell : null,
        ),
      ],
    );
  }

  static String _secondaryLabel(TowerSecondaryMetric metric) =>
      switch (metric) {
        TowerSecondaryMetric.chainCount => 'Chain',
        TowerSecondaryMetric.pierceCount => 'Pierce',
        TowerSecondaryMetric.slowDuration => 'Slow',
        TowerSecondaryMetric.splashRadius => 'Splash',
        TowerSecondaryMetric.corrosionDamagePerSecond => 'Corrosion',
        TowerSecondaryMetric.droneDamage => 'Drone dmg',
      };

  static String _secondaryValue(TowerSecondaryMetric metric, TowerStats stats) {
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
      child: Column(
        children: [
          SizedBox.square(
            dimension: 58,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CircularProgressIndicator(
                    value: fill,
                    strokeWidth: 7,
                    backgroundColor: uiTheme.frameSteel.withValues(alpha: .5),
                    color: accent,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: OrionTypography.readout(
                        size: 16,
                        color: uiTheme.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: OrionTypography.microLabel(
              size: 8,
              color: uiTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressionActions extends StatelessWidget {
  const _ProgressionActions({
    required this.snapshot,
    required this.tower,
    required this.stats,
    required this.canMutate,
    required this.onUpgrade,
    required this.onSpecialize,
  });

  final GameSnapshot snapshot;
  final PlacedTower tower;
  final TowerStats? stats;
  final bool canMutate;
  final VoidCallback onUpgrade;
  final ValueChanged<TowerSpecialization> onSpecialize;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    if (tower.isMaxLevel) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.check, size: 17),
          label: const Text('Max'),
        ),
      );
    }

    final resolvedStats = stats;
    if (tower.canUpgrade) {
      final cost = resolvedStats?.upgradeCost;
      final enabled =
          canMutate &&
          resolvedStats != null &&
          snapshot.gold >= resolvedStats.upgradeCost;
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: const ValueKey('tower-upgrade'),
          onPressed: enabled ? onUpgrade : null,
          icon: const Icon(Icons.upgrade, size: 17),
          label: Text(cost == null ? 'Upgrade' : 'Upgrade $cost'),
        ),
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
    required this.cost,
    required this.enabled,
    required this.onSpecialize,
  });

  final TowerType towerType;
  final TowerSpecialization specialization;
  final int? cost;
  final bool enabled;
  final ValueChanged<TowerSpecialization> onSpecialize;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Semantics(
      key: ValueKey('tower-specialization-${specialization.name}'),
      button: true,
      enabled: enabled,
      onTap: enabled ? () => onSpecialize(specialization) : null,
      excludeSemantics: true,
      label: cost == null
          ? specialization.label
          : '${specialization.label} $cost',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        OrionText.micro('Targeting', color: uiTheme.textMuted, size: 11),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final mode in TowerTargetingMode.values) ...[
                if (mode != TowerTargetingMode.first) const SizedBox(width: 5),
                Tooltip(
                  message: _targetingTooltip(mode),
                  child: ChoiceChip(
                    key: ValueKey('tower-target-${mode.name}'),
                    label: Text(mode.label),
                    selected: tower.targetingMode == mode,
                    onSelected: canMutate
                        ? (_) => onTargetingChanged(mode)
                        : null,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _targetingTooltip(TowerTargetingMode mode) => switch (mode) {
    TowerTargetingMode.first => 'Target the enemy furthest along the path',
    TowerTargetingMode.strongest => 'Target the enemy with the highest health',
    TowerTargetingMode.weakest => 'Target the enemy with the lowest health',
    TowerTargetingMode.closest => 'Target the enemy closest to this tower',
    TowerTargetingMode.shielded => 'Target shielded enemies first',
    TowerTargetingMode.armored => 'Target armored enemies first',
  };
}
