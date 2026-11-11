import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../codex/codex_data.dart';
import '../models/game_models.dart';
import '../util/format.dart';
import 'orion_atlas_sprite.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';
import 'tower_stat_scale.dart';

class CodexView extends StatefulWidget {
  const CodexView({
    super.key,
    required this.progress,
    this.onBack,
    this.embeddedInMenuShell = false,
  });

  final CampaignProgress progress;

  final VoidCallback? onBack;
  final bool embeddedInMenuShell;

  @override
  State<CodexView> createState() => _CodexViewState();
}

class _CodexViewState extends State<CodexView> {
  int _section = 0;
  static const _sections = ['Towers', 'Enemies', 'Effects', 'Stages'];
  TowerType? _selectedTower;
  EnemyArchetype? _selectedEnemy;

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
    return Material(
      color: uiTheme.voidBlack,
      child: Stack(
        children: [
          const Positioned.fill(child: _CodexBackdrop()),
          SafeArea(
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
                      if (!widget.embeddedInMenuShell)
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
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'FIELD MANUAL',
                                    style: OrionTypography.microLabel(
                                      size: 10,
                                      color: uiTheme.textMuted,
                                    ),
                                  ),
                                  OrionTitle(
                                    'Codex',
                                    size: 19,
                                    color: uiTheme.textPrimary,
                                  ),
                                ],
                              ),
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
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: orionChipFill,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: orionShelfEdge,
                                width: 1.5,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Row(
                                children: [
                                  for (var i = 0; i < _sections.length; i++)
                                    Expanded(
                                      child: _CodexTab(
                                        label: _sections[i],
                                        selected: _section == i,
                                        onTap: () => _selectSection(i),
                                      ),
                                    ),
                                ],
                              ),
                            ),
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
        ],
      ),
    );
  }

  Widget _body() {
    final controller = _scrollControllers[_section];
    final query = _searchController.text;
    List<Widget> children;
    switch (_section) {
      case 0:
        final towers = CodexData.towers
            .where((t) => codexMatches(query, t.searchTerms))
            .toList();
        if (towers.isEmpty) {
          children = const [];
          break;
        }
        final detail = towers.firstWhere(
          (t) => t.type == _selectedTower,
          orElse: () => towers.first,
        );
        children = [
          _towerGrid(towers, detail.type),
          const SizedBox(height: 12),
          _towerDetail(detail),
          ..._specIndex(towers, detail),
        ];
      case 1:
        final traits = CodexData.traits
            .where((tr) => codexMatches(query, tr.searchTerms))
            .toList();
        final enemies = CodexData.enemies
            .where((e) => codexMatches(query, e.searchTerms))
            .toList();
        final enemyDetail = enemies.isEmpty
            ? null
            : enemies.firstWhere(
                (e) => e.archetype == _selectedEnemy,
                orElse: () => enemies.first,
              );
        children = [
          for (final tr in traits)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _line(tr.label, tr.effect),
            ),
          // The divider only makes sense between the two groups.
          if (traits.isNotEmpty && enemies.isNotEmpty) const Divider(),
          if (enemyDetail != null) ...[
            _enemyDetail(enemyDetail),
            const SizedBox(height: 12),
            _enemyGrid(enemies, enemyDetail.archetype),
          ],
        ];
      case 2:
        final uiTheme = OrionUiTheme.of(context);
        children = [
          for (final ef in CodexData.effects.where(
            (ef) => codexMatches(query, ef.searchTerms),
          ))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: OrionSurface(
                role: OrionSurfaceRole.card,
                radius: 14,
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

  Widget _towerGrid(List<CodexTowerEntry> towers, TowerType detailType) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _tileColumns(constraints.maxWidth, [
            for (final t in towers) t.label,
          ]);
          return Column(
            children: [
              for (var row = 0; row < towers.length; row += columns) ...[
                if (row > 0) const SizedBox(height: 8),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var col = 0; col < columns; col++) ...[
                        if (col > 0) const SizedBox(width: 8),
                        Expanded(
                          child: row + col < towers.length
                              ? _CodexTile(
                                  entry: towers[row + col],
                                  selected:
                                      towers[row + col].type == detailType,
                                  onSelect: () => setState(
                                    () =>
                                        _selectedTower = towers[row + col].type,
                                  ),
                                )
                              : const SizedBox(height: 92),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _enemyGrid(List<CodexEnemyEntry> enemies, EnemyArchetype detailType) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _tileColumns(constraints.maxWidth, [
            for (final e in enemies) e.label,
          ]);
          return Column(
            children: [
              for (var row = 0; row < enemies.length; row += columns) ...[
                if (row > 0) const SizedBox(height: 8),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var col = 0; col < columns; col++) ...[
                        if (col > 0) const SizedBox(width: 8),
                        Expanded(
                          child: row + col < enemies.length
                              ? _EnemyTile(
                                  entry: enemies[row + col],
                                  selected:
                                      enemies[row + col].archetype ==
                                      detailType,
                                  onSelect: () => setState(
                                    () => _selectedEnemy =
                                        enemies[row + col].archetype,
                                  ),
                                )
                              : const SizedBox(height: 92),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  int _tileColumns(double maxWidth, List<String> labels) {
    final scaler = MediaQuery.textScalerOf(context);
    if (scaler.scale(10) <= 15) return 4;
    var widest = 0.0;
    final style = OrionTypography.microLabel(size: 10);
    for (final label in labels) {
      for (final word in label.split(' ')) {
        final painter = TextPainter(
          text: TextSpan(text: word, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        if (painter.width > widest) widest = painter.width;
      }
    }
    const gap = 8;
    final tile = widest + 14;
    return ((maxWidth + gap) / (tile + gap)).floor().clamp(1, 4);
  }

  Widget _towerDetail(CodexTowerEntry t) {
    final uiTheme = OrionUiTheme.of(context);
    final stats = t.baseStats;
    final scale = TowerStatScale.forType(t.type);
    final secondaryFill = scale.secondaryFill(stats);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final heading = Text(
      t.label.toUpperCase(),
      style: OrionTypography.readout(size: 20, color: uiTheme.textPrimary),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: OrionSurface(
        role: OrionSurfaceRole.sheet,
        key: const ValueKey('codex-detail'),
        radius: 18,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (largeText) ...[heading, const SizedBox(height: 8)],
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                OrionAtlasSprite(
                  art: OrionArt.tower(t.type),
                  size: const Size.square(56),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!largeText) ...[heading, const SizedBox(height: 4)],
                      Text(
                        'Available from wave ${t.unlockWave}',
                        style: OrionTypography.microLabel(
                          size: 10,
                          color: uiTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${stats.cost}g',
                  style: OrionTypography.readout(
                    size: 14,
                    color: uiTheme.creditGold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Damage / Fire interval only when meaningful (drone bay has damage 0).
            if (stats.damage > 0)
              _statBar(
                'Damage',
                number(stats.damage),
                scale.damageFill(stats),
                orionBarDamage,
              ),
            _statBar(
              'Fire rate',
              '${cadence(stats.fireInterval)}s',
              scale.fireFill(stats),
              orionBarFire,
            ),
            _statBar(
              'Range',
              number(stats.range),
              scale.rangeFill(stats),
              orionBarRange,
            ),
            if (secondaryFill != null)
              _statBar(
                _secondaryLabel(scale.secondaryMetric!),
                _secondaryValue(scale.secondaryMetric!, stats),
                secondaryFill,
                orionBarSecondary,
              ),
            const SizedBox(height: 8),
            _line('Upgrade cost', '${t.upgradeCost}'),
            for (final (k, v) in _specialtyLines(stats)) _line(k, v),
            const SizedBox(height: 12),
            Text(
              'Specializations',
              style: OrionTypography.microLabel(
                size: 10,
                color: uiTheme.textMuted,
              ),
            ),
            for (final spec in t.specializations)
              _specCard(t, spec, includeCoreLines: true),
          ],
        ),
      ),
    );
  }

  List<Widget> _specIndex(
    List<CodexTowerEntry> towers,
    CodexTowerEntry detail,
  ) {
    final uiTheme = OrionUiTheme.of(context);
    final others = [
      for (final t in towers)
        if (t.type != detail.type) t,
    ];
    if (others.isEmpty) return const [];
    return [
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'All specializations',
          style: OrionTypography.microLabel(size: 10, color: uiTheme.textMuted),
        ),
      ),
      for (final t in others)
        for (final spec in t.specializations)
          _specCard(t, spec, includeCoreLines: false),
    ];
  }

  Widget _specCard(
    CodexTowerEntry t,
    CodexSpecializationEntry spec, {
    required bool includeCoreLines,
  }) {
    final uiTheme = OrionUiTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: OrionSurface(
        role: OrionSurfaceRole.card,
        radius: 12,
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                OrionAtlasSprite(
                  art: OrionArt.specialization(spec.specialization),
                  size: const Size.square(34),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spec.label,
                        style: OrionTypography.readout(
                          size: 14,
                          color: uiTheme.textPrimary,
                        ),
                      ),
                      Text(
                        spec.description,
                        style: OrionTypography.microLabel(
                          size: 10,
                          color: uiTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${t.specializationCost}g',
                  style: OrionTypography.readout(
                    size: 14,
                    color: uiTheme.creditGold,
                  ),
                ),
              ],
            ),
            if (includeCoreLines)
              for (final (k, v) in _specializationCoreLines(
                spec.specializedStats,
              ))
                _line(k, v),
            for (final (k, v) in _specialtyLines(spec.specializedStats))
              _line(k, v),
          ],
        ),
      ),
    );
  }

  Widget _statBar(String label, String value, double fill, Gradient barFill) {
    final uiTheme = OrionUiTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: OrionTypography.microLabel(
                size: 10,
                color: uiTheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: orionPipEmpty,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: fill,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: barFill,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 44,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: OrionTypography.readout(
                size: 12,
                color: uiTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _secondaryLabel(TowerSecondaryMetric metric) =>
      switch (metric) {
        TowerSecondaryMetric.chainCount => 'Chain',
        TowerSecondaryMetric.pierceCount => 'Pierce',
        TowerSecondaryMetric.slowDuration => 'Slow',
        TowerSecondaryMetric.splashRadius => 'Splash',
        TowerSecondaryMetric.corrosionDamagePerSecond => 'Corrosion',
        TowerSecondaryMetric.droneDamage => 'Drones',
      };

  static String _secondaryValue(TowerSecondaryMetric metric, TowerStats s) =>
      switch (metric) {
        TowerSecondaryMetric.chainCount => '${s.chainCount}',
        TowerSecondaryMetric.pierceCount => '${s.pierceCount}',
        TowerSecondaryMetric.slowDuration => '${number(s.slowDuration)}s',
        TowerSecondaryMetric.splashRadius => number(s.splashRadius),
        TowerSecondaryMetric.corrosionDamagePerSecond =>
          '${number(s.corrosionDamagePerSecond)}/s',
        TowerSecondaryMetric.droneDamage => number(s.droneDamage),
      };

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

  Widget _enemyDetail(CodexEnemyEntry e) {
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: OrionSurface(
        role: OrionSurfaceRole.sheet,
        key: const ValueKey('codex-enemy-detail'),
        radius: 18,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              e.label.toUpperCase(),
              style: OrionTypography.readout(
                size: 20,
                color: uiTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OrionAtlasSprite(
                  art: OrionArt.previewGroup(
                    WavePreviewGroup(
                      enemyCount: 1,
                      label: e.label,
                      traits: e.traits.toSet(),
                    ),
                  ),
                  size: const Size.square(56),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    e.roleDescription,
                    style: OrionTypography.microLabel(
                      size: 10,
                      color: uiTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            if (e.traits.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  children: [for (final tr in e.traits) _badge(tr.label)],
                ),
              ),
            const SizedBox(height: 8),
            for (final (k, v) in lines) _line(k, v),
          ],
        ),
      ),
    );
  }

  Widget _stageCard(CodexStageEntry s) {
    final uiTheme = OrionUiTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: OrionSurface(
        role: OrionSurfaceRole.card,
        radius: 14,
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

class _CodexBackdrop extends StatelessWidget {
  const _CodexBackdrop();

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: uiTheme.voidBlack),
        Opacity(
          opacity: 0.35,
          child: Image.asset(
            'assets/images/reactor_rim_ui/backdrops/map-room.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            excludeFromSemantics: true,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(gradient: orionCodexScrim),
        ),
      ],
    );
  }
}

class _CodexTab extends StatefulWidget {
  const _CodexTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CodexTab> createState() => _CodexTabState();
}

class _CodexTabState extends State<_CodexTab> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() => setState(() {});

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final focused = _focusNode.hasFocus;
    return InkWell(
      focusNode: _focusNode,
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(10),
      child: Semantics(
        button: true,
        selected: widget.selected,
        inMutuallyExclusiveGroup: true,
        label: widget.label,
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: widget.selected ? orionSecondaryFill : null,
              borderRadius: BorderRadius.circular(10),
              border: focused
                  ? Border.all(color: uiTheme.systemCyan, width: 1.5)
                  : null,
              boxShadow: widget.selected
                  ? const [
                      BoxShadow(color: orionSecondaryLip, offset: Offset(0, 3)),
                    ]
                  : null,
            ),
            child: SizedBox(
              height: 48,
              child: Center(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OrionTypography.microLabel(
                    size: 10,
                    color: widget.selected
                        ? orionSecondaryInk
                        : uiTheme.textMuted,
                  ).copyWith(shadows: widget.selected ? const [] : null),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CodexTile extends StatefulWidget {
  const _CodexTile({
    required this.entry,
    required this.selected,
    required this.onSelect,
  });

  final CodexTowerEntry entry;
  final bool selected;
  final VoidCallback onSelect;

  @override
  State<_CodexTile> createState() => _CodexTileState();
}

class _CodexTileState extends State<_CodexTile> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() => setState(() {});

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final entry = widget.entry;
    final focused = _focusNode.hasFocus;
    return InkWell(
      focusNode: _focusNode,
      onTap: widget.onSelect,
      borderRadius: BorderRadius.circular(12),
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: entry.label,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            key: ValueKey('codex-tile-${entry.type.name}'),
            constraints: const BoxConstraints(minHeight: 92),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: OrionSurface(
                    role: OrionSurfaceRole.card,
                    radius: 12,
                    padding: EdgeInsets.zero,
                    child: SizedBox.expand(),
                  ),
                ),
                if (widget.selected)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: uiTheme.systemCyan,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: uiTheme.systemCyan.withValues(alpha: .35),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (focused)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: uiTheme.systemViolet,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'W${entry.unlockWave}',
                          style: OrionTypography.microLabel(
                            size: 10,
                            color: uiTheme.textDim,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: OrionAtlasSprite(
                          art: OrionArt.tower(entry.type),
                          size: const Size.square(46),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.label,
                        textAlign: TextAlign.center,
                        style: OrionTypography.microLabel(
                          size: 10,
                          color: widget.selected
                              ? uiTheme.systemCyan
                              : uiTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EnemyTile extends StatefulWidget {
  const _EnemyTile({
    required this.entry,
    required this.selected,
    required this.onSelect,
  });

  final CodexEnemyEntry entry;
  final bool selected;
  final VoidCallback onSelect;

  @override
  State<_EnemyTile> createState() => _EnemyTileState();
}

class _EnemyTileState extends State<_EnemyTile> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() => setState(() {});

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final entry = widget.entry;
    final focused = _focusNode.hasFocus;
    final traitArts = [
      for (final tr in entry.traits) OrionArt.trait(tr),
    ].nonNulls.toList();
    return InkWell(
      focusNode: _focusNode,
      onTap: widget.onSelect,
      borderRadius: BorderRadius.circular(12),
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: entry.label,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            key: ValueKey('codex-enemy-tile-${entry.archetype.name}'),
            constraints: const BoxConstraints(minHeight: 92),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: OrionSurface(
                    role: OrionSurfaceRole.card,
                    radius: 12,
                    padding: EdgeInsets.zero,
                    child: SizedBox.expand(),
                  ),
                ),
                if (widget.selected)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: uiTheme.systemCyan,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: uiTheme.systemCyan.withValues(alpha: .35),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (focused)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: uiTheme.systemViolet,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: OrionAtlasSprite(
                          art: OrionArt.previewGroup(
                            WavePreviewGroup(
                              enemyCount: 1,
                              label: entry.label,
                              traits: entry.traits.toSet(),
                            ),
                          ),
                          size: const Size.square(46),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.label,
                        textAlign: TextAlign.center,
                        style: OrionTypography.microLabel(
                          size: 10,
                          color: widget.selected
                              ? uiTheme.systemCyan
                              : uiTheme.textMuted,
                        ),
                      ),
                      if (traitArts.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 4,
                            children: [
                              for (final art in traitArts)
                                OrionAtlasSprite(
                                  art: art,
                                  size: const Size.square(14),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
