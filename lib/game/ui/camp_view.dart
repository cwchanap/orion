import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../util/format.dart';
import 'orion_atlas_sprite.dart';
import 'orion_menu_shell.dart';
import 'orion_scroll_view.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';
import 'tower_stat_scale.dart';

/// Width of [data] laid out in [style] under the ambient text scaler. The
/// badge strip and the roster grid use it so SQUAD-tag placement follows
/// real font metrics at every text scale instead of a hard-coded width.
double _measureLabel(BuildContext context, String data, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: data, style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Camp roster destination (HPA-922) reached from the bottom navigation —
/// the character counterpart of the removed R&D lab, reusing its bay
/// backdrop until HPA-926 ships final art.
///
/// Task-6 view (artboard 10): all twelve [Character] entries in roster order
/// as portrait cards — owned cards show rank, level and the SQUAD tag while
/// locked cards read as silhouettes. Tapping an owned card opens the
/// read-only character sheet (artboard 11) in place; the sheet carries no
/// level-up or R&D affordances.
class CampView extends StatefulWidget {
  const CampView({
    super.key,
    required this.ownedLevels,
    required this.squad,
    this.onBack,
    this.embeddedInMenuShell = false,
  });

  /// Owned characters mapped to their persistent level; absent entries are
  /// shown as locked.
  final Map<Character, int> ownedLevels;

  /// The saved squad roster — members carry the SQUAD marker.
  final List<Character> squad;

  final VoidCallback? onBack;
  final bool embeddedInMenuShell;

  @override
  State<CampView> createState() => _CampViewState();
}

class _CampViewState extends State<CampView> {
  /// The character whose sheet is open — null returns to the roster grid.
  Character? _sheet;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final sheet = _sheet;
    // A sheet can only be open for an owned member — guard against the roster
    // shrinking underneath an open sheet.
    final sheetLevel = sheet == null ? null : widget.ownedLevels[sheet];
    final sheetOpen = sheet != null && sheetLevel != null;
    return PopScope(
      canPop: !sheetOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          setState(() => _sheet = null);
        }
      },
      child: Material(
        color: uiTheme.voidBlack,
        child: Stack(
          children: [
            const Positioned.fill(child: _CampBackdrop()),
            SafeArea(
              child: sheetOpen
                  ? _CharacterSheet(
                      character: sheet,
                      level: sheetLevel,
                      onBack: () => setState(() => _sheet = null),
                    )
                  : _buildRoster(uiTheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoster(OrionUiTheme uiTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embeddedInMenuShell)
          Padding(
            padding: EdgeInsets.fromLTRB(
              widget.onBack == null ? 12 : 4,
              4,
              12,
              0,
            ),
            child: Row(
              children: [
                if (widget.onBack != null)
                  IconButton(
                    tooltip: 'Back',
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'CHARACTER ROSTER',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: MediaQuery.textScalerOf(
                          context,
                        ).clamp(maxScaleFactor: 1.3),
                        style: OrionTypography.microLabel(
                          size: 10,
                          color: uiTheme.systemViolet,
                        ),
                      ),
                      OrionTitle(
                        'Camp',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        color: uiTheme.textPrimary,
                      ),
                    ],
                  ),
                ),
                OrionResourceChip(
                  icon: Icons.groups_rounded,
                  iconColor: uiTheme.systemViolet,
                  count:
                      '${widget.ownedLevels.length}/${Character.values.length}',
                  semanticsLabel:
                      '${widget.ownedLevels.length} of '
                      '${Character.values.length} characters recruited',
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.ownedLevels.length} OF ${Character.values.length} '
                  'RECRUITED',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OrionTypography.microLabel(
                    size: 10,
                    color: uiTheme.textMuted,
                  ),
                ),
              ),
              Text(
                'SQUAD ${widget.squad.length}/${GameBalance.squadMaxSize}',
                maxLines: 1,
                style: OrionTypography.microLabel(
                  size: 10,
                  color: uiTheme.systemViolet,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Three columns at the 390 product width, matching artboard 10
              // — but only while a card can still host the SQUAD pill. Under
              // large text the pill can outgrow a ~91px card, so the grid
              // drops columns (e.g. two at 320 with 2x text) rather than
              // shrinking accessible text or clipping the tag.
              final pillWidth =
                  _measureLabel(
                    context,
                    'SQUAD',
                    OrionTypography.microLabel(
                      size: 10,
                      color: uiTheme.systemViolet,
                    ),
                  ) +
                  10;
              final crossAxis = math.max(0.0, constraints.maxWidth - 28);
              final relaxed = math.max(1, (crossAxis / 128).ceil());
              final columns = ((crossAxis + 10) / (pillWidth + 24))
                  .floor()
                  .clamp(1, relaxed);
              final tileWidth = (crossAxis - (columns - 1) * 10) / columns;
              final portraitCacheWidth = math.max(
                1,
                (tileWidth * MediaQuery.devicePixelRatioOf(context)).round(),
              );
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.68,
                ),
                itemCount: Character.values.length,
                itemBuilder: (context, index) {
                  final character = Character.values[index];
                  final level = widget.ownedLevels[character];
                  return _CharacterCard(
                    character: character,
                    level: level,
                    inSquad: widget.squad.contains(character),
                    portraitCacheWidth: portraitCacheWidth,
                    onTap: level == null
                        ? null
                        : () => setState(() => _sheet = character),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One roster card (artboard 10): portrait art under a bottom scrim, rank
/// badge top-left, SQUAD tag top-right for drafted members, and name + level
/// (or ??? + NOT RECRUITED) pinned to the bottom. Owned cards are tappable
/// and open the character sheet.
class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.character,
    required this.level,
    required this.inSquad,
    required this.portraitCacheWidth,
    required this.onTap,
  });

  final Character character;
  final int? level;
  final bool inSquad;
  final int portraitCacheWidth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final owned = level != null;
    final rankColor = character.rank.orionColor(uiTheme);
    final nameLine = Text(
      owned ? character.displayName : '???',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: OrionTypography.readout(
        size: 13,
        color: owned ? uiTheme.textPrimary : uiTheme.textMuted,
      ),
    );
    final levelLine = Text(
      owned ? 'Lv $level' : 'NOT RECRUITED',
      maxLines: 2,
      style: OrionTypography.microLabel(
        size: 10,
        color: owned ? uiTheme.creditGold : uiTheme.textMuted,
      ),
    );
    return Semantics(
      label: owned
          ? '${character.displayName}, rank ${character.rank.label}, '
                'level $level${inSquad ? ', squad member' : ''}'
          : 'Locked character, rank ${character.rank.label}, not recruited',
      button: owned,
      onTap: onTap,
      excludeSemantics: true,
      child: Opacity(
        opacity: owned ? 1 : 0.55,
        child: OrionSurface(
          key: ValueKey('camp-card-${character.name}'),
          role: OrionSurfaceRole.card,
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Locked members read as muted silhouettes: the shared
                // filter keeps the art's luminance so shapes stay
                // discernible — srcIn instead flattened these opaque
                // portraits into an invisible black slab.
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: owned
                        ? OrionAtlasSprite(
                            art: OrionArt.characterPortrait(character),
                            cacheWidth: portraitCacheWidth,
                          )
                        : ColorFiltered(
                            colorFilter: orionLockedPortraitFilter,
                            child: OrionAtlasSprite(
                              art: OrionArt.characterPortrait(character),
                              cacheWidth: portraitCacheWidth,
                            ),
                          ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 54,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(12),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            uiTheme.voidBlack.withValues(alpha: 0),
                            uiTheme.voidBlack.withValues(alpha: 0.88),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  left: 6,
                  right: 6,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Rank badge grows with the ambient text scaler so the
                      // glyph stays painted at 2x instead of clipping inside
                      // a fixed 20px box.
                      final rankStyle = OrionTypography.microLabel(
                        size: 11,
                        color: rankColor,
                      );
                      final rankBadge = Container(
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: rankColor.withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: rankColor.withValues(alpha: .7),
                            width: 1.2,
                          ),
                        ),
                        child: Text(character.rank.label, style: rankStyle),
                      );
                      if (!inSquad) {
                        return Row(children: [rankBadge]);
                      }
                      final squadStyle = OrionTypography.microLabel(
                        size: 10,
                        color: uiTheme.systemViolet,
                      );
                      final squadBadge = DecoratedBox(
                        decoration: BoxDecoration(
                          color: uiTheme.systemViolet.withValues(alpha: .22),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: uiTheme.systemViolet.withValues(alpha: .7),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          // Inherits the ambient text scaler: large-text
                          // users get a larger tag.
                          child: Text('SQUAD', maxLines: 1, style: squadStyle),
                        ),
                      );
                      // Rank + pill sit side by side only while the row can
                      // hold both at their real measured widths; below that
                      // the pill drops to its own right-aligned row instead
                      // of clipping or ellipsizing.
                      final rankGlyphWidth = _measureLabel(
                        context,
                        character.rank.label,
                        rankStyle,
                      );
                      final rankWidth = rankGlyphWidth + 6 < 20
                          ? 20.0
                          : rankGlyphWidth + 6;
                      final pillWidth =
                          _measureLabel(context, 'SQUAD', squadStyle) + 10;
                      if (constraints.maxWidth >= rankWidth + pillWidth + 4) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [rankBadge, squadBadge],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: rankBadge,
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: squadBadge,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 7,
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [nameLine, levelLine],
                    ),
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

/// The read-only character sheet (artboard 11): portrait hero, rank + full
/// name + role, persistent level against the 40-level cap, the fixed
/// signature panel, bio, and combat stat bars derived from the shared
/// balance/stat scale. No level-up or currency affordances by design.
class _CharacterSheet extends StatelessWidget {
  const _CharacterSheet({
    required this.character,
    required this.level,
    required this.onBack,
  });

  final Character character;
  final int level;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final stats = GameBalance.towerStats(character.style, level: 1)
        .scaleDamageChannels(
          GameBalance.characterScalingFactor(character.rank, level),
        );
    final scale = TowerStatScale.forType(character.style);
    final rankColor = character.rank.orionColor(uiTheme);
    final levelFill = (level / GameBalance.characterMaxLevel).clamp(0.0, 1.0);

    return KeyedSubtree(
      key: const ValueKey('character-sheet'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    'CHARACTER SHEET',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: MediaQuery.textScalerOf(
                      context,
                    ).clamp(maxScaleFactor: 1.3),
                    style: OrionTypography.microLabel(
                      size: 10,
                      color: uiTheme.systemViolet,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: OrionScrollView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 220,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          OrionAtlasSprite(
                            art: OrionArt.characterPortrait(character),
                            cacheWidth: math.max(
                              1,
                              (220 *
                                      (2 / 3) *
                                      MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 90,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      uiTheme.voidBlack.withValues(alpha: 0),
                                      uiTheme.voidBlack.withValues(alpha: 0.85),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            bottom: 10,
                            right: 10,
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: rankColor.withValues(alpha: .18),
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(
                                      color: rankColor.withValues(alpha: .7),
                                      width: 1.4,
                                    ),
                                  ),
                                  child: Text(
                                    character.rank.label,
                                    style: OrionTypography.readout(
                                      size: 15,
                                      color: rankColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      OrionTitle(
                                        character.fullName,
                                        size: 17,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        color: uiTheme.textPrimary,
                                      ),
                                      Text(
                                        character.role,
                                        maxLines: 2,
                                        style: OrionTypography.microLabel(
                                          size: 10,
                                          color: uiTheme.systemCyan,
                                        ),
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'LV $level / ${GameBalance.characterMaxLevel}',
                        style: OrionTypography.readout(
                          size: 12,
                          color: uiTheme.creditGold,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: orionPipEmpty,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: levelFill,
                                heightFactor: 1,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: uiTheme.creditGold,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SheetStatBar(
                    label: 'DAMAGE',
                    value: number(stats.damage),
                    fill: scale.damageFill(stats),
                    barFill: orionBarDamage,
                  ),
                  _SheetStatBar(
                    label: 'FIRE',
                    value: '${cadence(stats.fireInterval)}s',
                    fill: scale.fireFill(stats),
                    barFill: orionBarFire,
                  ),
                  _SheetStatBar(
                    label: 'RANGE',
                    value: number(stats.range),
                    fill: scale.rangeFill(stats),
                    barFill: orionBarRange,
                  ),
                  if (scale.secondaryMetric case final metric?)
                    _SheetStatBar(
                      label: _sheetSecondaryLabel(metric),
                      value: _sheetSecondaryValue(metric, stats),
                      fill: scale.secondaryFill(stats) ?? 0,
                      barFill: orionBarSecondary,
                    ),
                  const SizedBox(height: 14),
                  OrionSurface(
                    role: OrionSurfaceRole.card,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Builder(
                          builder: (context) {
                            final heading = Text(
                              'SIGNATURE SKILL',
                              style: OrionTypography.microLabel(
                                size: 10,
                                color: uiTheme.systemViolet,
                              ),
                            );
                            final chip = DecoratedBox(
                              decoration: BoxDecoration(
                                color: uiTheme.systemViolet.withValues(
                                  alpha: .18,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: uiTheme.systemViolet.withValues(
                                    alpha: .7,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                child: Text(
                                  'BATTLE TIER 3',
                                  maxLines: 1,
                                  style: OrionTypography.microLabel(
                                    size: 10,
                                    color: uiTheme.systemViolet,
                                  ),
                                ),
                              ),
                            );
                            if (MediaQuery.textScalerOf(context).scale(1) >
                                1.5) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  heading,
                                  const SizedBox(height: 4),
                                  chip,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: heading),
                                chip,
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          character.signatureName,
                          style: OrionTypography.readout(
                            size: 14,
                            color: uiTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          character.signature.role,
                          style: OrionTypography.microLabel(
                            size: 10,
                            color: uiTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    character.bio,
                    style: OrionTypography.microLabel(
                      size: 11,
                      color: uiTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One combat stat row on the sheet, mirroring the Codex/inspector bars so a
/// character's numbers read on the same scale as its deployed tower.
class _SheetStatBar extends StatelessWidget {
  const _SheetStatBar({
    required this.label,
    required this.value,
    required this.fill,
    required this.barFill,
  });

  final String label;
  final String value;
  final double fill;
  final Gradient barFill;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final labelWidget = Text(
      label,
      style: OrionTypography.microLabel(size: 10, color: uiTheme.textMuted),
    );
    final valueWidget = Text(
      value,
      textAlign: TextAlign.end,
      style: OrionTypography.readout(size: 12, color: uiTheme.textPrimary),
    );
    final bar = SizedBox(
      height: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: orionPipEmpty,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            key: ValueKey('sheet-stat-fill-$label'),
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
    );
    if (MediaQuery.textScalerOf(context).scale(1) > 1.5) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: labelWidget),
                const SizedBox(width: 8),
                valueWidget,
              ],
            ),
            const SizedBox(height: 4),
            bar,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 78, child: labelWidget),
          Expanded(child: bar),
          const SizedBox(width: 10),
          SizedBox(width: 44, child: valueWidget),
        ],
      ),
    );
  }
}

String _sheetSecondaryLabel(TowerSecondaryMetric metric) => switch (metric) {
  TowerSecondaryMetric.chainCount => 'CHAIN',
  TowerSecondaryMetric.pierceCount => 'PIERCE',
  TowerSecondaryMetric.slowDuration => 'SLOW',
  TowerSecondaryMetric.splashRadius => 'SPLASH',
  TowerSecondaryMetric.corrosionDamagePerSecond => 'CORROSION',
  TowerSecondaryMetric.droneDamage => 'DRONES',
};

String _sheetSecondaryValue(TowerSecondaryMetric metric, TowerStats stats) {
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

/// The former R&D bay backdrop (artboard 1g) is intentionally reused as the
/// Camp backdrop until HPA-926 ships final Last Hearth art.
class _CampBackdrop extends StatelessWidget {
  const _CampBackdrop();

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: uiTheme.voidBlack),
        FittedBox(
          key: const ValueKey('camp-backdrop-art'),
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: OrionAtlasSprite(
            art: OrionArt.scene(OrionSceneArt.camp),
            size: const Size.square(640),
          ),
        ),
        const DecoratedBox(
          key: ValueKey('camp-scrim'),
          decoration: BoxDecoration(gradient: orionCampScrim),
        ),
      ],
    );
  }
}
