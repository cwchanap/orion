import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../codex/codex_data.dart';
import '../models/game_models.dart';
import '../util/format.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';
import 'tower_icons.dart';

class CodexView extends StatefulWidget {
  const CodexView({super.key, required this.progress, this.onBack});

  final CampaignProgress progress;

  /// Back action for standalone hosts. Null inside the shared menu shell —
  /// the bottom tabs own navigation there, so no back button renders.
  final VoidCallback? onBack;

  @override
  State<CodexView> createState() => _CodexViewState();
}

class _CodexViewState extends State<CodexView> {
  int _section = 0;
  static const _sections = ['Towers', 'Enemies', 'Effects', 'Stages'];

  // One ScrollController per section so each section's scroll offset is
  // preserved independently when the player switches chips.
  late final List<ScrollController> _scrollControllers;
  final _searchController = TextEditingController();

  // The shell hosts the Codex by in-place view swap (no route of its own), so
  // the section lists must not store offsets in the app-long root route
  // bucket: a bucket scoped to this State keeps offsets across chip switches
  // within a visit but resets them when the Codex is reopened.
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();

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
    _searchController.dispose();
    super.dispose();
  }

  // Only a different section clears the search: re-tapping the selected
  // chip keeps the query (and focus) so accidental taps lose nothing.
  // When leaving a searched section, reset its scroll offset so returning
  // to it starts at the top of the full list; unfiltered sections preserve
  // their scroll positions.
  void _selectSection(int index) {
    if (_section == index) return;
    FocusScope.of(context).unfocus();
    if (_searchController.text.isNotEmpty) {
      final controller = _scrollControllers[_section];
      if (controller.hasClients) controller.jumpTo(0);
    }
    setState(() {
      _section = index;
      _searchController.clear();
    });
  }

  // One path for typed input and programmatic Clear (clear() never calls
  // onChanged): re-filter and reset the active section's scroll, guarding
  // against jumpTo while the controller has no clients.
  void _applySearchUpdate() {
    setState(() {});
    final controller = _scrollControllers[_section];
    if (controller.hasClients) controller.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    // A flat body, not a Scaffold: inside the shared menu shell the shell's
    // Scaffold owns insets and chrome, and its MediaQuery.removePadding
    // turns this view's own SafeArea into a no-op. Standalone test hosts
    // still get the full layout.
    return Material(
      color: uiTheme.voidBlack,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Compact chrome follows the app convention of clamping text
            // scale; result cards below keep scaling fully.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.15,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        if (widget.onBack != null)
                          IconButton(
                            tooltip: 'Back',
                            onPressed: widget.onBack,
                            icon: const Icon(Icons.arrow_back),
                          ),
                        const SizedBox(width: 8),
                        OrionTitle('Codex', color: uiTheme.textPrimary),
                      ],
                    ),
                  ),
                  // The chips join the field's tap region: mouse/stylus (and
                  // web touch) taps outside a TextField unfocus it on
                  // pointer-down, which would run before _selectSection's
                  // re-tap guard and steal focus from a no-op chip re-tap.
                  TextFieldTapRegion(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (var i = 0; i < _sections.length; i++)
                            ChoiceChip(
                              label: Text(_sections[i]),
                              selected: _section == i,
                              onSelected: (_) => _selectSection(i),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => _applySearchUpdate(),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText:
                            'Search ${_sections[_section].toLowerCase()}',
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                onPressed: () {
                                  _searchController.clear();
                                  _applySearchUpdate();
                                },
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              // A user drag (dragDetails != null) unfocuses the search field
              // immediately — on a clamping list with zero scroll extent the
              // built-in onDrag dismissal never sees a scroll update.
              child: PageStorage(
                bucket: _pageStorageBucket,
                child: NotificationListener<ScrollStartNotification>(
                  onNotification: (notification) {
                    if (notification.dragDetails != null) {
                      FocusScope.of(context).unfocus();
                    }
                    return false;
                  },
                  child: _body(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final uiTheme = OrionUiTheme.of(context);
    final controller = _scrollControllers[_section];
    final query = _searchController.text;
    List<Widget> children;
    switch (_section) {
      case 0:
        children = [
          for (final t in CodexData.towers.where(
            (t) => codexMatches(query, t.searchTerms),
          ))
            _towerCard(t),
        ];
      case 1:
        final traits = CodexData.traits
            .where((tr) => codexMatches(query, tr.searchTerms))
            .toList();
        final enemies = CodexData.enemies
            .where((e) => codexMatches(query, e.searchTerms))
            .toList();
        children = [
          for (final tr in traits) _line(tr.label, tr.effect),
          // The divider only makes sense between the two groups.
          if (traits.isNotEmpty && enemies.isNotEmpty) const Divider(),
          for (final e in enemies) _enemyCard(e),
        ];
      case 2:
        children = [
          for (final ef in CodexData.effects.where(
            (ef) => codexMatches(query, ef.searchTerms),
          ))
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
                        size: 10,
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
        ];
      default:
        children = [
          for (final s in CodexData.stagesFor(
            widget.progress,
          ).where((s) => codexMatches(query, s.searchTerms)))
            _stageCard(s),
        ];
    }
    // Zero results stay inside the same ListView (same key, controller and
    // always-scrollable drag behavior) rather than swapping in a Center.
    if (children.isEmpty) children = [_noMatches()];
    return ListView(
      key: PageStorageKey<int>(_section),
      controller: controller,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );
  }

  Widget _noMatches() {
    final uiTheme = OrionUiTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      // Padded centered child, per spec: the message is not a list row.
      child: Center(
        child: Text(
          'No matches in ${_sections[_section]}',
          style: OrionTypography.microLabel(color: uiTheme.textMuted),
        ),
      ),
    );
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
                  size: 10,
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
                size: 10,
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
                size: 10,
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
                    size: 10,
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
                size: 10,
                color: uiTheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: OrionTypography.microLabel(
                size: 10,
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
        // panelRaised fills, frameSteel outlines: the pairing every other
        // filled chip in the UI uses (see next_wave_scanner.dart). frameSteel
        // is a border accent everywhere else, never a fill.
        color: uiTheme.panelRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: uiTheme.frameSteel),
      ),
      child: Text(
        text,
        style: OrionTypography.microLabel(color: uiTheme.textMuted),
      ),
    );
  }
}
