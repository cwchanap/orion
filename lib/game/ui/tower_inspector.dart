import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../util/format.dart';
import 'orion_atlas_sprite.dart';
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
  });

  final GameSnapshot snapshot;
  final VoidCallback onUpgrade;
  final ValueChanged<TowerSpecialization> onSpecialize;
  final ValueChanged<TowerTargetingMode> onTargetingChanged;
  final VoidCallback onSell;
  final int sellRefund;

  @override
  Widget build(BuildContext context) {
    final tower = snapshot.selectedTower;
    if (tower == null) return const SizedBox.shrink();

    final maxHeight = math.min(210.0, MediaQuery.sizeOf(context).height * 0.31);
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        key: const ValueKey('tower-inspector'),
        width: double.infinity,
        height: maxHeight,
        child: Material(
          color: Colors.transparent,
          child: SingleChildScrollView(
            key: const ValueKey('tower-inspector-scroll'),
            padding: const EdgeInsets.symmetric(horizontal: 10),
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
            OrionAtlasSprite(
              art: OrionArt.tower(tower.type),
              size: const Size(32, 32),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${tower.type.label} Tower',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: uiTheme.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tower.specialization == null
                        ? 'Level ${tower.level}'
                        : 'Level ${tower.level} • '
                              '${tower.specialization!.label}',
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: uiTheme.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        _TargetingActions(
          tower: tower,
          canMutate: canMutate,
          onTargetingChanged: onTargetingChanged,
        ),
        const SizedBox(height: 3),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ProgressionActions(
              snapshot: snapshot,
              tower: tower,
              stats: stats,
              canMutate: canMutate,
              onUpgrade: onUpgrade,
              onSpecialize: onSpecialize,
            ),
            Semantics(
              key: const ValueKey('tower-sell-semantics'),
              button: true,
              enabled: canMutate,
              label: 'Sell $sellRefund',
              onTap: canMutate ? onSell : null,
              excludeSemantics: true,
              child: OutlinedButton.icon(
                key: const ValueKey('tower-sell'),
                onPressed: canMutate ? onSell : null,
                icon: const Icon(Icons.sell_outlined, size: 17),
                label: Text('Sell $sellRefund'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: uiTheme.dangerRed,
                  side: BorderSide(
                    color: uiTheme.dangerRed.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        const Divider(height: 1),
        if (stats != null) ...[
          const SizedBox(height: 7),
          _StatRow(
            key: const ValueKey('tower-stat-damage'),
            label: 'Damage',
            value: number(stats.damage),
            fill: scale.damageFill(stats),
          ),
          _StatRow(
            key: const ValueKey('tower-stat-fire'),
            label: 'Fire',
            value: '${cadence(stats.fireInterval)}s',
            fill: scale.fireFill(stats),
          ),
          _StatRow(
            key: const ValueKey('tower-stat-range'),
            label: 'Range',
            value: number(stats.range),
            fill: scale.rangeFill(stats),
          ),
          if (scale.secondaryMetric case final metric?)
            _StatRow(
              key: const ValueKey('tower-stat-secondary'),
              label: _secondaryLabel(metric),
              value: _secondaryValue(metric, stats),
              fill: scale.secondaryFill(stats) ?? 0,
            ),
        ],
      ],
    );
  }

  static String _secondaryLabel(TowerSecondaryMetric metric) =>
      switch (metric) {
        TowerSecondaryMetric.slowDuration => 'Slow',
        TowerSecondaryMetric.splashRadius => 'Splash',
        TowerSecondaryMetric.corrosionDamagePerSecond => 'Corrosion',
        TowerSecondaryMetric.droneDamage => 'Drone dmg',
      };

  static String _secondaryValue(TowerSecondaryMetric metric, TowerStats stats) {
    final value = number(metric.valueOf(stats));
    return switch (metric) {
      TowerSecondaryMetric.slowDuration => '${value}s',
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
  });

  final String label;
  final String value;
  final double fill;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Semantics(
      label: '$label $value',
      readOnly: true,
      container: true,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: uiTheme.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: fill,
                    minHeight: 5,
                    backgroundColor: uiTheme.frameSteel.withValues(alpha: 0.35),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      uiTheme.systemCyan,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
            SizedBox(
              width: 54,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: uiTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
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
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final specialization in GameBalance.specializationsFor(tower.type))
          FilledButton.tonalIcon(
            key: ValueKey('tower-specialization-${specialization.name}'),
            onPressed: enabled ? () => onSpecialize(specialization) : null,
            icon: const Icon(Icons.call_split, size: 16),
            label: Text(
              cost == null
                  ? specialization.label
                  : '${specialization.label} $cost',
            ),
          ),
      ],
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
        Text(
          'Targeting',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: uiTheme.textMuted,
            fontWeight: FontWeight.w800,
          ),
        ),
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
