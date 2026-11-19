import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../rules/flare_rules.dart';
import '../util/format.dart';
import 'orion_atlas_sprite.dart';
import 'orion_menu_shell.dart';
import 'orion_primary_button.dart';
import 'orion_scroll_view.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';

/// Signal-flare recruitment destination (HPA-923 task 5, artboard 12): fire
/// one flare for a recruit or ten at once, at a fixed disclosed rank rate —
/// duplicates trade back as Scrip automatically.
///
/// The view is deliberately wallet-honest: pack affordability reads the
/// committed [scrip] only, never speculative refunds this batch might pay.
/// A fired pack's spinner lives in local state so the shared pending-save
/// flag keeps every purchase single-flight without leaking which pack went
/// first to the owner.
///
/// When [result] is set the same widget reveals the committed batch
/// (artboard 13): new-recruit hero cards, every draw tile in pull order
/// with its NEW/duplicate outcome and refund, the aggregate trade-in and
/// the resulting balance.
class FlareView extends StatefulWidget {
  const FlareView({
    super.key,
    required this.scrip,
    this.result,
    this.isSavingProgress = false,
    this.onFire,
    this.onResultDone,
    this.onOpenRoster,
    this.embeddedInMenuShell = false,
  });

  /// The committed Scrip wallet — pack affordability and the standalone
  /// balance chip read it verbatim.
  final int scrip;

  /// The committed batch to reveal; null renders the fire screen. The page
  /// only sets this after the flare write has persisted.
  final FlareBatch? result;

  /// True while a campaign write — save or reset — is in flight: both
  /// packs are single-flight, so they hold disabled (the fired one with a
  /// spinner) until the page clears the flag.
  final bool isSavingProgress;

  /// Asks the owner to buy a pack of 1 or 10 flares; the page routes it
  /// through the committed save queue. Null renders both packs disabled
  /// (previews, read-only hosts).
  final ValueChanged<int>? onFire;

  /// Dismisses the result back to the fire screen (FIRE AGAIN).
  final VoidCallback? onResultDone;

  /// Dismisses the result and asks for the Camp roster (TO ROSTER).
  final VoidCallback? onOpenRoster;

  final bool embeddedInMenuShell;

  @override
  State<FlareView> createState() => _FlareViewState();
}

class _FlareViewState extends State<FlareView> {
  /// The pack size the player last fired — which button carries the
  /// spinner while the save drains. Cleared when the write resolves.
  int? _firedCount;

  static const _rarenessOrder = [
    CharacterRank.s,
    CharacterRank.a,
    CharacterRank.b,
    CharacterRank.c,
    CharacterRank.d,
    CharacterRank.e,
  ];

  /// The artboard-12 marquee: the rarest answers a flare can draw, shown as
  /// fixed splash picks rather than live roster state.
  static const _marquee = [Character.jin, Character.hikari, Character.akane];

  @override
  void didUpdateWidget(FlareView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The write drained or a result arrived — release the fired pack's
    // spinner claim so a later unrelated busy state cannot revive it.
    if (_firedCount != null &&
        (!widget.isSavingProgress || widget.result != null)) {
      _firedCount = null;
    }
  }

  void _fire(int count) {
    if (widget.onFire == null || widget.isSavingProgress) {
      return;
    }
    setState(() => _firedCount = count);
    widget.onFire!(count);
  }

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final result = widget.result;
    return Material(
      color: uiTheme.voidBlack,
      child: Stack(
        children: [
          const Positioned.fill(child: _FlareBackdrop()),
          SafeArea(
            child: result == null
                ? _buildFireScreen(uiTheme)
                : _buildResultScreen(uiTheme, result),
          ),
        ],
      ),
    );
  }

  // --- Fire screen (artboard 12) ------------------------------------------

  Widget _buildFireScreen(OrionUiTheme uiTheme) {
    final scrip = widget.scrip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embeddedInMenuShell)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'RECRUIT SURVIVORS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: MediaQuery.textScalerOf(
                          context,
                        ).clamp(maxScaleFactor: 1.3),
                        style: OrionTypography.microLabel(
                          size: 10,
                          color: uiTheme.warningOrange,
                        ),
                      ),
                      OrionTitle(
                        'Signal Flare',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        color: uiTheme.textPrimary,
                      ),
                    ],
                  ),
                ),
                OrionResourceChip(
                  icon: Icons.payments_rounded,
                  iconColor: uiTheme.creditGold,
                  count: grouped(scrip),
                  semanticsLabel: '${grouped(scrip)} Scrip',
                ),
              ],
            ),
          ),
        Expanded(
          child: OrionScrollView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _FlareBeacon(),
                const SizedBox(height: 8),
                Text(
                  'Fire a flare over the snow. Whoever sees it walks in to '
                  'join the camp.',
                  textAlign: TextAlign.center,
                  style: OrionTypography.microLabel(
                    size: 12,
                    color: uiTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                _buildMarquee(uiTheme),
                const SizedBox(height: 14),
                _buildRatesPanel(uiTheme),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.payments_rounded,
                      size: 16,
                      color: uiTheme.creditGold,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Already in camp? Their spare dog tag is traded for '
                        'Scrip automatically.',
                        style: OrionTypography.microLabel(
                          size: 11,
                          color: uiTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _buildFireStrip(uiTheme),
      ],
    );
  }

  Widget _buildMarquee(OrionUiTheme uiTheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, character) in _marquee.indexed)
          Expanded(
            child: Padding(
              // The centre pick stands proud like the artboard's featured
              // recruit; the flanking two step down a notch.
              padding: EdgeInsets.only(
                top: index == 1 ? 0 : 14,
                left: index == 0 ? 0 : 8,
                right: index == _marquee.length - 1 ? 0 : 8,
              ),
              child: _MarqueeCard(character: character),
            ),
          ),
      ],
    );
  }

  Widget _buildRatesPanel(OrionUiTheme uiTheme) {
    return Semantics(
      label:
          'Drop rates: ${_rarenessOrder.map((rank) => '${rank.label} ${_rateLabel(rank)}').join(', ')}',
      child: OrionSurface(
        role: OrionSurfaceRole.sheet,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(width: 3, height: 12, color: uiTheme.systemCyan),
                const SizedBox(width: 8),
                Text(
                  'WHO ANSWERS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OrionTypography.microLabel(
                    size: 10,
                    color: uiTheme.systemCyan,
                  ).copyWith(letterSpacing: 1.2),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final rank in _rarenessOrder)
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RankBadge(rank: rank),
                        const SizedBox(height: 5),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _rateLabel(rank),
                            maxLines: 1,
                            style: OrionTypography.readout(
                              size: 12,
                              color: uiTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Rank odds straight from the shared 10,000-basis-point table — '0.1%',
  /// '2%', '67.4%' — with whole percents trimmed.
  static String _rateLabel(CharacterRank rank) {
    final percent = GameBalance.flareRankWeights[rank]! / 100;
    return percent % 1 == 0 ? '${percent.toInt()}%' : '$percent%';
  }

  /// The pinned purchase strip: per-pack readable gate reasons ride above
  /// their buttons (a single shared SAVING… while any write is in flight),
  /// then the two packs — single at the full 100, the ten at 1,000 with no
  /// discount.
  Widget _buildFireStrip(OrionUiTheme uiTheme) {
    final busy = widget.isSavingProgress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) _gateReason(uiTheme, 'SAVING…'),
          for (final count in FlareRules.allowedPackCounts) ...[
            if (!busy && widget.scrip < count * GameBalance.flareCost)
              _gateReason(
                uiTheme,
                'NEEDS ${grouped(count * GameBalance.flareCost)} SCRIP',
              ),
            OrionPrimaryButton(
              key: ValueKey('flare-fire-$count'),
              label: count == 1
                  ? 'FIRE FLARE · ${grouped(GameBalance.flareCost)}'
                  : 'FIRE $count · ${grouped(count * GameBalance.flareCost)}',
              icon: Icons.local_fire_department_rounded,
              onPressed:
                  widget.onFire != null &&
                      !busy &&
                      widget.scrip >= count * GameBalance.flareCost
                  ? () => _fire(count)
                  : null,
              loading: busy && _firedCount == count,
              variant: count == 1
                  ? OrionButtonVariant.primary
                  : OrionButtonVariant.secondary,
              height: 52,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _gateReason(OrionUiTheme uiTheme, String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        message,
        textAlign: TextAlign.center,
        maxLines: 2,
        style: OrionTypography.microLabel(
          size: 10,
          color: uiTheme.warningOrange,
        ),
      ),
    );
  }

  // --- Result screen (artboard 13) ----------------------------------------

  Widget _buildResultScreen(OrionUiTheme uiTheme, FlareBatch batch) {
    final draws = batch.draws;
    final recruits = [
      for (final draw in draws)
        if (draw.isNew) draw,
    ];
    final duplicates = draws.length - recruits.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${draws.length} FLARE${draws.length == 1 ? '' : 'S'} FIRED',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.3),
                style: OrionTypography.microLabel(
                  size: 10,
                  color: uiTheme.warningOrange,
                ).copyWith(letterSpacing: 1.2),
              ),
              const SizedBox(height: 2),
              OrionTitle(
                recruits.isEmpty
                    ? 'No new recruits'
                    : recruits.length == 1
                    ? 'New recruit'
                    : '${recruits.length} new recruits',
                size: 24,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                color: uiTheme.textPrimary,
              ),
            ],
          ),
        ),
        Expanded(
          child: OrionScrollView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (recruits.isNotEmpty) ...[
                  _buildHeroRow(uiTheme, recruits),
                  const SizedBox(height: 14),
                ],
                _buildDrawGrid(uiTheme, draws),
                const SizedBox(height: 14),
                _buildSummary(uiTheme, batch, duplicates),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              OrionPrimaryButton(
                key: const ValueKey('flare-again'),
                label: 'FIRE AGAIN',
                icon: Icons.replay_rounded,
                onPressed: widget.onResultDone,
                variant: OrionButtonVariant.secondary,
                height: 52,
              ),
              const SizedBox(height: 8),
              OrionPrimaryButton(
                key: const ValueKey('flare-to-roster'),
                label: 'TO ROSTER',
                icon: Icons.groups_rounded,
                onPressed: widget.onOpenRoster,
                height: 52,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The new recruits get hero cards above the grid — up to the first three
  /// in pull order, matching the artboard's showcase row. The row gives up
  /// columns rather than shrinking type: each card must stay wide enough
  /// for its name and NEW RECRUIT line at the user's text scale.
  Widget _buildHeroRow(OrionUiTheme uiTheme, List<FlareDraw> recruits) {
    final shown = recruits.take(3).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;
        const gap = 10.0;
        final minCardWidth = 104 * textScale;
        final maxCardWidth = 150 * textScale;
        final columns = math
            .min(
              shown.length,
              ((constraints.maxWidth + gap) / (minCardWidth + gap)).floor(),
            )
            .clamp(1, 3);
        final cardWidth = math.min(
          (constraints.maxWidth - (columns - 1) * gap) / columns,
          maxCardWidth,
        );
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final draw in shown)
              SizedBox(
                width: cardWidth,
                child: _HeroCard(draw: draw),
              ),
          ],
        );
      },
    );
  }

  /// Every draw in pull order: up to five across for the ten-pull grid,
  /// reflowing to fewer columns (or a single column at large text scales)
  /// so the wrapped outcome caption stays at its full font size. A lone
  /// pull keeps a centred card-sized tile.
  Widget _buildDrawGrid(OrionUiTheme uiTheme, List<FlareDraw> draws) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;
        if (draws.length == 1) {
          return Center(
            child: SizedBox(
              width: math.min(120 * textScale, constraints.maxWidth),
              child: AspectRatio(
                aspectRatio: 0.64,
                child: _DrawTile(draw: draws.single, index: 0),
              ),
            ),
          );
        }
        const gap = 8.0;
        // ~72px leaves room for a wrapped "+1,500 SCRIP" caption segment;
        // the floor scales with the user's text scale.
        final minTileWidth = 72 * textScale;
        final maxTileWidth = 130 * textScale;
        final columns = math
            .min(
              math.min(5, draws.length),
              ((constraints.maxWidth + gap) / (minTileWidth + gap)).floor(),
            )
            .clamp(1, 5);
        final tileWidth = math.min(
          (constraints.maxWidth - (columns - 1) * gap) / columns,
          maxTileWidth,
        );
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (index, draw) in draws.indexed)
              SizedBox(
                width: tileWidth,
                child: AspectRatio(
                  aspectRatio: 0.64,
                  child: _DrawTile(draw: draw, index: index),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The gold-rimmed trade-in strip: how many duplicates converted, the
  /// aggregate refund, and the committed post-pack balance.
  Widget _buildSummary(OrionUiTheme uiTheme, FlareBatch batch, int duplicates) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: uiTheme.hullBlack.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: uiTheme.creditGold, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$duplicates SPARE DOG TAG${duplicates == 1 ? '' : 'S'} '
                  'TRADED',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OrionTypography.microLabel(
                    size: 10,
                    color: uiTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.payments_rounded,
                      size: 18,
                      color: uiTheme.creditGold,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '+${grouped(batch.totalScripRefund)} Scrip',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OrionTypography.readout(
                          size: 17,
                          color: uiTheme.creditGold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'BALANCE',
                maxLines: 1,
                style: OrionTypography.microLabel(
                  size: 10,
                  color: uiTheme.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                grouped(widget.scrip),
                maxLines: 1,
                style: OrionTypography.readout(
                  size: 17,
                  color: uiTheme.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One draw tile in the result grid: portrait (desaturated when the draw
/// was a duplicate), rank badge top-left and the outcome label pinned
/// underneath — NEW for a recruit, the rank's Scrip refund for a duplicate.
class _DrawTile extends StatelessWidget {
  const _DrawTile({required this.draw, required this.index});

  final FlareDraw draw;
  final int index;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final rankColor = draw.rank.orionColor(uiTheme);
    final character = draw.character;
    return Semantics(
      label:
          '${character.displayName}, rank ${character.rank.label}, '
          '${draw.isNew ? 'new recruit' : 'duplicate, +${grouped(draw.scripRefund)} Scrip refund'}',
      child: ExcludeSemantics(
        child: Container(
          key: ValueKey('flare-draw-$index'),
          decoration: BoxDecoration(
            color: uiTheme.hullBlack,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: draw.isNew ? rankColor : orionPanelEdge,
              width: 1.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: draw.isNew
                      ? OrionAtlasSprite(
                          art: OrionArt.characterPortrait(character),
                          cacheWidth: 140,
                        )
                      : ColorFiltered(
                          colorFilter: orionLockedPortraitFilter,
                          child: OrionAtlasSprite(
                            art: OrionArt.characterPortrait(character),
                            cacheWidth: 140,
                          ),
                        ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  // The scrim covers up to two caption lines so wrapped
                  // refunds keep their contrast at large text scales.
                  height:
                      34 * (MediaQuery.textScalerOf(context).scale(11) / 11),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            uiTheme.voidBlack.withValues(alpha: 0),
                            uiTheme.voidBlack.withValues(alpha: .9),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  left: 4,
                  child: _RankBadge(rank: draw.rank, compact: true),
                ),
                Positioned(
                  left: 4,
                  right: 4,
                  bottom: 4,
                  child: Text(
                    draw.isNew ? 'NEW' : '+${grouped(draw.scripRefund)} SCRIP',
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: OrionTypography.microLabel(
                      size: 11,
                      color: draw.isNew
                          ? uiTheme.naniteGreen
                          : uiTheme.creditGold,
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

/// The artboard-13 hero card for a new recruit: full-bleed portrait, rank
/// badge, name and the green NEW RECRUIT line.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.draw});

  final FlareDraw draw;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final character = draw.character;
    final rankColor = draw.rank.orionColor(uiTheme);
    return Semantics(
      label: '${character.fullName}, rank ${character.rank.label}, new recruit',
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: 0.7,
          child: Container(
            key: ValueKey('flare-hero-${character.name}'),
            decoration: BoxDecoration(
              color: uiTheme.hullBlack,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: rankColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: rankColor.withValues(alpha: .45),
                  blurRadius: 14,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: OrionAtlasSprite(
                      art: OrionArt.characterPortrait(character),
                      cacheWidth: 260,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 74,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              uiTheme.voidBlack.withValues(alpha: 0),
                              uiTheme.voidBlack.withValues(alpha: .92),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _RankBadge(rank: draw.rank),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 7,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          character.fullName.split(',').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: OrionTypography.readout(
                            size: 13,
                            color: uiTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'NEW RECRUIT',
                          maxLines: 2,
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: OrionTypography.microLabel(
                            size: 10,
                            color: uiTheme.naniteGreen,
                          ).copyWith(letterSpacing: 1.1),
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
    );
  }
}

/// One fixed marquee pick on the fire screen — portrait, rank badge and
/// name, exactly the approved artboard's showcase trio.
class _MarqueeCard extends StatelessWidget {
  const _MarqueeCard({required this.character});

  final Character character;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final rankColor = character.rank.orionColor(uiTheme);
    return Semantics(
      label:
          '${character.fullName}, rank ${character.rank.label}, could '
          'answer the flare',
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: 0.72,
          child: Container(
            decoration: BoxDecoration(
              color: uiTheme.hullBlack,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: rankColor.withValues(alpha: .8),
                width: 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: OrionAtlasSprite(
                      art: OrionArt.characterPortrait(character),
                      cacheWidth: 220,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 40,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              uiTheme.voidBlack.withValues(alpha: 0),
                              uiTheme.voidBlack.withValues(alpha: .85),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _RankBadge(rank: character.rank),
                  ),
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 6,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        character.displayName,
                        maxLines: 1,
                        style: OrionTypography.readout(
                          size: 11,
                          color: uiTheme.textPrimary,
                        ),
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

/// The small rank chip shared by rate cells, draw tiles, marquee picks and
/// hero cards — the same coloured-box language as the Camp cards.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, this.compact = false});

  final CharacterRank rank;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final color = rank.orionColor(uiTheme);
    // microLabel's 10px floor applies at every badge size — the compact
    // tile badge only shrinks its box.
    final size = compact ? 10.0 : 11.0;
    return Container(
      constraints: BoxConstraints(
        minWidth: compact ? 16 : 22,
        minHeight: compact ? 16 : 22,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: .8), width: 1.2),
      ),
      child: Text(
        rank.label,
        style: OrionTypography.microLabel(size: size, color: color),
      ),
    );
  }
}

/// The composed flare-beacon over the copy: a rising glow trail. Painted
/// chrome, not a new asset — artboard art is owned by HPA-926.
class _FlareBeacon extends StatelessWidget {
  const _FlareBeacon();

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Semantics(
      label: 'Signal flare climbing into the night sky',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      uiTheme.creditGold,
                      uiTheme.warningOrange.withValues(alpha: .9),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: uiTheme.creditGold.withValues(alpha: .8),
                      blurRadius: 22,
                      spreadRadius: 6,
                    ),
                  ],
                ),
              ),
              Container(
                width: 3,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      uiTheme.creditGold.withValues(alpha: .85),
                      uiTheme.creditGold.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The shared Last Hearth backdrop — the camp scene the flare is fired
/// over, identical to the Camp destination's until final art lands.
class _FlareBackdrop extends StatelessWidget {
  const _FlareBackdrop();

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: uiTheme.voidBlack),
        FittedBox(
          key: const ValueKey('flare-backdrop-art'),
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: OrionAtlasSprite(
            art: OrionArt.scene(OrionSceneArt.camp),
            size: const Size.square(640),
          ),
        ),
        const DecoratedBox(
          key: ValueKey('flare-scrim'),
          decoration: BoxDecoration(gradient: orionCampScrim),
        ),
      ],
    );
  }
}
