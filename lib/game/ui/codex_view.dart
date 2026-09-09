import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../codex/codex_data.dart';
import '../models/game_models.dart';
import '../util/format.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';
import 'tower_icons.dart';

class CodexView extends StatefulWidget {
  const CodexView({super.key, required this.progress, required this.onBack});

  final CampaignProgress progress;
  final VoidCallback onBack;

  @override
  State<CodexView> createState() => _CodexViewState();
}

class _CodexViewState extends State<CodexView> {
  int _section = 0;
  static const _sections = ['Towers', 'Enemies', 'Effects', 'Stages'];

  // One ScrollController per section so each section's scroll offset is
  // preserved independently when the player switches chips.
  late final List<ScrollController> _scrollControllers;

  @override
  void initState() {
    super.initState();
    _scrollControllers = [
      for (var i = 0; i < _sections.length; i++) ScrollController(),
    ];
  }

  @override
  void dispose() {
    for (final controller in _scrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Codex',
                    style: OrionTypography.title(color: uiTheme.textPrimary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < _sections.length; i++)
                    ChoiceChip(
                      label: Text(_sections[i]),
                      selected: _section == i,
                      onSelected: (_) => setState(() => _section = i),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final uiTheme = OrionUiTheme.of(context);
    final controller = _scrollControllers[_section];
    return switch (_section) {
      0 => ListView(
        controller: controller,
        children: [for (final t in CodexData.towers) _towerCard(t)],
      ),
      1 => ListView(
        controller: controller,
        children: [
          for (final tr in CodexData.traits) _line(tr.label, tr.effect),
          const Divider(),
          for (final e in CodexData.enemies) _enemyCard(e),
        ],
      ),
      2 => ListView(
        controller: controller,
        children: [
          for (final ef in CodexData.effects)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ef.title,
                      style: OrionTypography.microLabel(
                        size: 11,
                        color: uiTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ef.description,
                      style: OrionTypography.microLabel(
                        size: 9,
                        color: uiTheme.textMuted,
                      ),
                    ),
                    if (ef.relatedSpecializations.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Used by: ${ef.relatedSpecializations.map((s) => s.label).join(', ')}',
                        style: OrionTypography.microLabel(
                          color: uiTheme.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
      _ => ListView(
        controller: controller,
        children: [
          for (final s in CodexData.stagesFor(widget.progress)) _stageCard(s),
        ],
      ),
    };
  }

  Widget _towerCard(CodexTowerEntry t) {
    final uiTheme = OrionUiTheme.of(context);
    final lines = <(String, String)>[
      ('Range', number(t.baseStats.range)),
      ('Cost', '${t.baseStats.cost}'),
      ('Upgrade cost', '${t.upgradeCost}'),
      // Damage / Fire interval only when meaningful (drone bay has damage 0).
      if (t.baseStats.damage > 0) ...[
        ('Damage', number(t.baseStats.damage)),
        ('Fire interval', '${cadence(t.baseStats.fireInterval)}s'),
      ],
      ..._specialtyLines(t.baseStats),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(towerIcon(t.type)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    t.label,
                    style: OrionTypography.microLabel(
                      size: 11,
                      color: uiTheme.textMuted,
                    ),
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    'Available from wave ${t.unlockWave}',
                    style: OrionTypography.microLabel(color: uiTheme.textMuted),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (k, v) in lines) _line(k, v),
            const SizedBox(height: 8),
            for (final spec in t.specializations) ...[
              Text(
                '${spec.label} (${t.specializationCost}g)',
                style: OrionTypography.microLabel(
                  size: 11,
                  color: uiTheme.textMuted,
                ),
              ),
              Text(
                spec.description,
                style: OrionTypography.microLabel(
                  size: 9,
                  color: uiTheme.textMuted,
                ),
              ),
              for (final (k, v) in _specializationCoreLines(
                spec.specializedStats,
              ))
                _line(k, v),
              for (final (k, v) in _specialtyLines(spec.specializedStats))
                _line(k, v),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }

  // Core stats for a specialization card. Range always renders; Damage and
  // Fire interval render when meaningful (drone bay has damage 0). These are
  // the values a specialization's defining benefit often lives in (e.g. Pulse
  // Laser's 0.24s fire interval), which _specialtyLines omits.
  List<(String, String)> _specializationCoreLines(TowerStats s) {
    final out = <(String, String)>[
      ('Range', number(s.range)),
      if (s.damage > 0) ...[
        ('Damage', number(s.damage)),
        ('Fire interval', '${cadence(s.fireInterval)}s'),
      ],
    ];
    return out;
  }

  // Specialty rows render only when non-default (spec §8.1).
  List<(String, String)> _specialtyLines(TowerStats s) {
    final out = <(String, String)>[];
    if (s.splashRadius > 0) out.add(('Splash radius', number(s.splashRadius)));
    if (s.slowMultiplier < 1) {
      out.add((
        'Slow',
        '${percent(1 - s.slowMultiplier)} for ${number(s.slowDuration)}s',
      ));
    }
    if (s.pierceCount > 0) out.add(('Pierce', '${s.pierceCount}'));
    if (s.chainCount > 0) {
      out.add(('Chain', '${s.chainCount} (range ${number(s.chainRange)})'));
    }
    if (s.corrosionDamagePerSecond > 0) {
      out.add((
        'Corrosion',
        '${number(s.corrosionDamagePerSecond)}/s for ${number(s.corrosionDuration)}s',
      ));
    }
    if (s.armorShred > 0) out.add(('Armor shred', percent(s.armorShred)));
    if (s.fieldRadius > 0) {
      out.add((
        'Field',
        'r ${number(s.fieldRadius)}, ${number(s.fieldDuration)}s, tick ${cadence(s.fieldTickInterval)}s',
      ));
    }
    if (s.droneCount > 0) {
      out.add((
        'Drones',
        '${s.droneCount} (cap ${s.maxActiveDrones}), ${number(s.droneDamage)} dmg / ${cadence(s.droneAttackInterval)}s, ${number(s.droneLifetime)}s life',
      ));
    }
    if (s.shieldDamageMultiplier != 1) {
      out.add(('vs Shield', 'x${decimal(s.shieldDamageMultiplier)}'));
    }
    if (s.armorDamageMultiplier != 1) {
      out.add(('vs Armored', 'x${decimal(s.armorDamageMultiplier)}'));
    }
    if (s.slowedDamageMultiplier != 1) {
      out.add(('vs Slowed', 'x${number(s.slowedDamageMultiplier)}'));
    }
    // Spec-only amplifiers (prism split, cluster burst) — surfaced on the
    // relevant specialization cards (spec §8.1).
    if (s.prismSplitDamageMultiplier > 0) {
      out.add(('Prism split', '${percent(s.prismSplitDamageMultiplier)} dmg'));
    }
    if (s.clusterBurstCount > 0) {
      out.add(('Cluster burst', '${s.clusterBurstCount}'));
    }
    return out;
  }

  Widget _enemyCard(CodexEnemyEntry e) {
    final uiTheme = OrionUiTheme.of(context);
    final lines = <(String, String)>[
      ('Health', number(e.stats.health)),
      ('Speed', number(e.stats.speed)),
      ('Base damage', '${e.stats.baseDamage}'),
      ('Reward', '${e.stats.goldReward}g'),
      if (e.stats.shieldHealth > 0) ('Shield', number(e.stats.shieldHealth)),
      if (e.stats.armorReduction > 0)
        ('Armor', percent(e.stats.armorReduction)),
      if (e.stats.regenPerSecond > 0)
        ('Regen', '${number(e.stats.regenPerSecond)}/s'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e.label,
              style: OrionTypography.microLabel(
                size: 11,
                color: uiTheme.textMuted,
              ),
            ),
            if (e.traits.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  children: [for (final tr in e.traits) _badge(tr.label)],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              e.roleDescription,
              style: OrionTypography.microLabel(
                size: 9,
                color: uiTheme.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            for (final (k, v) in lines) _line(k, v),
          ],
        ),
      ),
    );
  }

  Widget _stageCard(CodexStageEntry s) {
    final uiTheme = OrionUiTheme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    '${s.stage.name} (${s.stage.mapLabel})',
                    style: OrionTypography.microLabel(
                      size: 11,
                      color: uiTheme.textMuted,
                    ),
                  ),
                ),
                const Spacer(),
                _badge(_statusLabel(s.status)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${s.stage.isMainPath ? "Main" : "Side"} • ${s.waveCount} waves',
              style: OrionTypography.microLabel(color: uiTheme.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              s.stage.description,
              style: OrionTypography.microLabel(
                size: 9,
                color: uiTheme.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            for (final m in s.modifiers) _line(m.title, m.description),
            // stageRewardLabel already prefixes uncleared rewards with
            // "Reward: " (and returns the bare amount when cleared), so render
            // it as a standalone label rather than a keyed row to avoid a
            // duplicated "Reward Reward: ..." string.
            if (s.rewardLabel != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  s.rewardLabel!,
                  style: OrionTypography.microLabel(
                    size: 9,
                    color: uiTheme.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(StageProgressStatus s) => switch (s) {
    StageProgressStatus.cleared => 'Cleared',
    StageProgressStatus.unlocked => 'Unlocked',
    StageProgressStatus.locked => 'Locked',
  };

  Widget _line(String key, String value) {
    final uiTheme = OrionUiTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              key,
              style: OrionTypography.microLabel(
                size: 9,
                color: uiTheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: OrionTypography.microLabel(
                size: 9,
                color: uiTheme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text) {
    final uiTheme = OrionUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: uiTheme.frameSteel,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: OrionTypography.microLabel(color: uiTheme.textMuted),
      ),
    );
  }
}
