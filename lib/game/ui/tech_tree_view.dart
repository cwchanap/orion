import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/tech_tree.dart';
import '../models/game_models.dart';
import 'orion_atlas_sprite.dart';
import 'orion_primary_button.dart';
import 'orion_scroll_view.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';

/// Full-screen panel reached from the world map: five independent tech-tree
/// upgrades over the R&D-bay backdrop (artboard 1g). Tapping a node only
/// changes which upgrade's detail is shown — the purchase/persistence rules
/// keep living in the parent shell.
class TechTreeView extends StatefulWidget {
  const TechTreeView({
    super.key,
    required this.progress,
    required this.techTree,
    this.feedback,
    this.isSavingProgress = false,
    required this.onPurchase,
    this.onBack,
    this.embeddedInMenuShell = false,
  });

  final CampaignProgress progress;
  final CampaignTechTree techTree;
  final String? feedback;

  /// When true, purchase buttons are disabled (a save is in flight).
  final bool isSavingProgress;

  /// Invoked when the user taps an affordable upgrade's Purchase button.
  final ValueChanged<CampaignTechUpgrade> onPurchase;

  /// Invoked when the user taps the back button.
  final VoidCallback? onBack;
  final bool embeddedInMenuShell;

  @override
  State<TechTreeView> createState() => _TechTreeViewState();
}

const _nodeAnchors = <CampaignTechUpgrade, (double, double)>{
  CampaignTechUpgrade.solarCapacitors: (.5, 0),
  CampaignTechUpgrade.hardenedCore: (.2667, 192),
  CampaignTechUpgrade.salvageCrew: (.7333, 192),
  CampaignTechUpgrade.laserTuning: (.2667, 346),
  CampaignTechUpgrade.cryoCoolant: (.7333, 346),
};

const _nodeWidth = 130.0;
const _nodeHeight = 138.0;
const _fieldHeight = 484.0;
const _fieldMinViewport = 100.0;
const _detailSurfaceChrome = 31.0;

/// Header, gaps and the pinned action the detail sheet cannot compress: the
/// field reservation must yield before this height is taken from the sheet.
const _detailPinnedExtent = 124.0;

Path _hexPath(Size size) {
  final w = size.width;
  final h = size.height;
  return Path()
    ..moveTo(w / 2, 0)
    ..lineTo(w, h * .25)
    ..lineTo(w, h * .75)
    ..lineTo(w / 2, h)
    ..lineTo(0, h * .75)
    ..lineTo(0, h * .25)
    ..close();
}

class _HexClipper extends CustomClipper<Path> {
  const _HexClipper();

  @override
  Path getClip(Size size) => _hexPath(size);

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class _HexEdgePainter extends CustomPainter {
  const _HexEdgePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _hexPath(size);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_HexEdgePainter old) => old.color != color;
}

class _TechConduitPainter extends CustomPainter {
  const _TechConduitPainter({required this.solid, required this.dashed});

  final Color solid;
  final Color dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final railX = size.width * .04;
    final mid = size.width / 2;
    const railTop = 60.0;
    const railBottom = 470.0;
    const spineY = 163.0;
    canvas.drawPath(
      Path()
        ..moveTo(railX, railTop)
        ..lineTo(railX, railBottom)
        ..moveTo(size.width - railX, railTop)
        ..lineTo(size.width - railX, railBottom)
        ..moveTo(railX, spineY)
        ..lineTo(size.width - railX, spineY),
      Paint()
        ..color = solid
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    final dashPaint = Paint()
      ..color = dashed
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final drops = Path()
      ..moveTo(mid, spineY)
      ..lineTo(mid, railBottom);
    for (final metric in drops.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 6).clamp(0, metric.length);
        canvas.drawPath(
          metric.extractPath(distance, end.toDouble()),
          dashPaint,
        );
        distance = end + 6;
      }
    }
  }

  @override
  bool shouldRepaint(_TechConduitPainter old) =>
      old.solid != solid || old.dashed != dashed;
}

class _TechTreeViewState extends State<TechTreeView> {
  /// Presentation-only selection: which node's detail is on screen. Never
  /// persisted and never read by the parent; real node/detail state (purchased,
  /// affordable, saving) is always derived from [TechTreeView] props on
  /// rebuild so purchases and rollbacks flow through unchanged.
  CampaignTechUpgrade? _selected;

  void _select(CampaignTechUpgrade upgrade) {
    setState(() => _selected = upgrade);
  }

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final progress = widget.progress;
    final techTree = widget.techTree;
    final earned = CampaignTechTree.totalMedalRank(progress);
    final spent = techTree.totalSpent;
    final unspent = techTree.unspentPoints(progress);

    // Fixed five-node field, positioned to echo artboard 1g: the top node,
    // a flanking pair, then two more — without any connector edges (the five
    // upgrades are independent purchases).
    return Material(
      color: uiTheme.voidBlack,
      child: Stack(
        children: [
          const Positioned.fill(
            child: _TechTreeBackdrop(key: ValueKey('tech-tree-backdrop')),
          ),
          SafeArea(
            child: Column(
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
                                'CAMPAIGN UPGRADES',
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
                                'R & D',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                color: uiTheme.textPrimary,
                              ),
                            ],
                          ),
                        ),
                        Semantics(
                          label: 'Unspent: $unspent',
                          excludeSemantics: true,
                          child: _BankChip(unspent: unspent),
                        ),
                      ],
                    ),
                  ),
                if (widget.feedback != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(
                      widget.feedback!,
                      style: OrionTypography.microLabel(
                        size: 10,
                        color: uiTheme.dangerRed,
                      ),
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, region) {
                      final fieldReserve =
                          (region.maxHeight -
                                  12 -
                                  _detailSurfaceChrome -
                                  _detailPinnedExtent)
                              .clamp(0.0, _fieldMinViewport);
                      final detailMaxHeight =
                          (region.maxHeight -
                                  12 -
                                  _detailSurfaceChrome -
                                  fieldReserve)
                              .clamp(0.0, region.maxHeight);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: OrionScrollView(
                              // Selecting a node opens its details at the top of this scrollable area.
                              key: ValueKey(_selected),
                              padding: EdgeInsets.only(
                                top: _selected == null
                                    ? (MediaQuery.sizeOf(context).height * .12)
                                          .clamp(24, 110)
                                    : 12,
                                bottom: 20,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    height: _fieldHeight,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final fieldWidth = constraints.maxWidth;
                                        return Stack(
                                          children: [
                                            Positioned.fill(
                                              child: IgnorePointer(
                                                child: ExcludeSemantics(
                                                  child: SizedBox(
                                                    key: const ValueKey(
                                                      'tech-tree-conduits',
                                                    ),
                                                    child: CustomPaint(
                                                      painter:
                                                          _TechConduitPainter(
                                                            solid: uiTheme
                                                                .systemViolet
                                                                .withValues(
                                                                  alpha: .85,
                                                                ),
                                                            dashed: uiTheme
                                                                .systemCyan
                                                                .withValues(
                                                                  alpha: .7,
                                                                ),
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            for (final entry
                                                in _nodeAnchors.entries)
                                              Positioned(
                                                left:
                                                    entry.value.$1 *
                                                        fieldWidth -
                                                    _nodeWidth / 2,
                                                top: entry.value.$2,
                                                child: _TechNode(
                                                  upgrade: entry.key,
                                                  isSelected:
                                                      entry.key == _selected,
                                                  isPurchased: techTree
                                                      .isPurchased(entry.key),
                                                  canAfford: techTree
                                                      .canPurchase(
                                                        entry.key,
                                                        progress,
                                                      ),
                                                  onSelect: () =>
                                                      _select(entry.key),
                                                ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                  if (widget.embeddedInMenuShell)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: _BankBar(
                                        unspent: unspent,
                                        earned: earned,
                                        spent: spent,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (_selected != null) ...[
                            const SizedBox(height: 12),
                            _TechDetail(
                              key: ValueKey('tech-detail-${_selected!.id}'),
                              upgrade: _selected!,
                              progress: progress,
                              techTree: techTree,
                              isSavingProgress: widget.isSavingProgress,
                              onPurchase: widget.onPurchase,
                              onClose: () => setState(() => _selected = null),
                              maxHeight: detailMaxHeight,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                if (!widget.embeddedInMenuShell)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: _BankBar(
                      unspent: unspent,
                      earned: earned,
                      spent: spent,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Approved R&D-bay scene art behind the nodes, dimmed by a readability scrim
/// so node labels stay legible. The supplied portrait art is cover-fitted.
class _TechTreeBackdrop extends StatelessWidget {
  const _TechTreeBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: uiTheme.voidBlack),
        Image.asset(
          'assets/images/reactor_rim_ui/backdrops/tech-tree-rnd-bay.png',
          key: const ValueKey('tech-tree-backdrop-art'),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
        const DecoratedBox(
          key: ValueKey('tech-tree-scrim'),
          decoration: BoxDecoration(gradient: orionTechTreeScrim),
        ),
      ],
    );
  }
}

class _BankChip extends StatelessWidget {
  const _BankChip({required this.unspent});

  final int unspent;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: uiTheme.systemViolet.withValues(alpha: .16),
        border: Border.all(color: uiTheme.systemViolet.withValues(alpha: .6)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pentagon, size: 24, color: uiTheme.systemViolet),
            const SizedBox(width: 3),
            Text(
              '$unspent',
              style: OrionTypography.readout(
                size: 24,
                color: uiTheme.systemViolet,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BankBar extends StatelessWidget {
  const _BankBar({
    required this.unspent,
    required this.earned,
    required this.spent,
  });

  final int unspent;
  final int earned;
  final int spent;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Semantics(
      label: 'Unspent: $unspent · Earned: $earned · Spent: $spent',
      excludeSemantics: true,
      child: DecoratedBox(
        key: const ValueKey('tech-bank-bar'),
        decoration: BoxDecoration(
          color: uiTheme.hullBlack.withValues(alpha: 0.92),
          border: Border.all(color: uiTheme.frameSteel),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.pentagon, size: 30, color: uiTheme.systemViolet),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Unspent: $unspent · Earned: $earned · Spent: $spent',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: MediaQuery.textScalerOf(
                    context,
                  ).clamp(maxScaleFactor: 1.15),
                  style: OrionTypography.readout(
                    size: 12,
                    color: uiTheme.textPrimary,
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

const _lockedSpriteFilter = ColorFilter.matrix([
  .36,
  .26,
  .18,
  0,
  0,
  .36,
  .26,
  .18,
  0,
  0,
  .36,
  .26,
  .18,
  0,
  0,
  0,
  0,
  0,
  .55,
  0,
]);

class _TechNode extends StatelessWidget {
  const _TechNode({
    required this.upgrade,
    required this.isSelected,
    required this.isPurchased,
    required this.canAfford,
    required this.onSelect,
  });

  final CampaignTechUpgrade upgrade;
  final bool isSelected;
  final bool isPurchased;
  final bool canAfford;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    // Purchased nodes glow green; affordable ones cyan; the rest stay muted.
    final accent = isPurchased
        ? uiTheme.naniteGreen
        : canAfford
        ? uiTheme.systemCyan
        : uiTheme.textMuted;

    final Decoration shell = BoxDecoration(
      gradient: isPurchased
          ? orionHexOwnShell
          : canAfford || isSelected
          ? orionHexAvailShell
          : null,
      color: isPurchased || canAfford || isSelected ? null : uiTheme.frameSteel,
    );
    final Decoration core = BoxDecoration(
      gradient: isPurchased
          ? orionHexOwnCore
          : canAfford || isSelected
          ? orionHexAvailCore
          : null,
      color: isPurchased || canAfford || isSelected ? null : orionHexLockCore,
    );

    return Semantics(
      button: true,
      selected: isSelected,
      label: [
        upgrade.label,
        if (isPurchased) 'Purchased',
        upgrade.effectLabel,
        'Cost ${upgrade.cost} points',
      ].join(' • '),
      onTap: onSelect,
      excludeSemantics: true,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          key: ValueKey('tech-node-${upgrade.id}'),
          width: _nodeWidth,
          height: _nodeHeight,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: (_nodeWidth - 74) / 2,
                child: SizedBox(
                  key: isSelected
                      ? ValueKey('tech-selected-ring-${upgrade.id}')
                      : null,
                  width: 74,
                  height: 82,
                  child: CustomPaint(
                    foregroundPainter: isSelected
                        ? _HexEdgePainter(uiTheme.systemCyan)
                        : null,
                    child: ClipPath(
                      clipper: const _HexClipper(),
                      child: DecoratedBox(
                        decoration: shell,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: ClipPath(
                            clipper: const _HexClipper(),
                            child: DecoratedBox(
                              decoration: core,
                              child: Center(
                                child: _nodeVisual(
                                  upgrade,
                                  accent,
                                  iconSize: 30,
                                  spriteSize: 40,
                                  locked: !isPurchased && !canAfford,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (isPurchased)
                Positioned(
                  top: 2,
                  right: 22,
                  child: DecoratedBox(
                    key: ValueKey('tech-node-purchased-${upgrade.id}'),
                    decoration: BoxDecoration(
                      color: uiTheme.systemViolet,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(
                      width: 18,
                      height: 18,
                      child: Center(
                        child: Icon(
                          Icons.check,
                          size: 11,
                          color: orionHexCheckInk,
                        ),
                      ),
                    ),
                  ),
                )
              else if (!canAfford)
                Positioned(
                  top: 4,
                  right: 24,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: orionHexLockBadge,
                      shape: BoxShape.circle,
                      border: Border.all(color: uiTheme.frameSteel),
                    ),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: Center(
                        child: Icon(
                          Icons.lock,
                          size: 10,
                          color: uiTheme.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      upgrade.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      textScaler: MediaQuery.textScalerOf(
                        context,
                      ).clamp(maxScaleFactor: 1.15),
                      // Muted-label rule forbids textPrimary here; reuse the
                      // node's own purchased/affordable/locked accent instead
                      // of collapsing to a single flat tone.
                      style: OrionTypography.microLabel(
                        size: 10,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _compactEffect(upgrade),
                        maxLines: 1,
                        textScaler: MediaQuery.textScalerOf(
                          context,
                        ).clamp(maxScaleFactor: 1.15),
                        style: OrionTypography.readout(
                          size: 13,
                          color: isPurchased || canAfford
                              ? uiTheme.naniteGreen
                              : uiTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _nodeVisual(
  CampaignTechUpgrade upgrade,
  Color iconColor, {
  required double iconSize,
  required double spriteSize,
  bool locked = false,
}) {
  final type = switch (upgrade) {
    CampaignTechUpgrade.laserTuning => TowerType.laser,
    CampaignTechUpgrade.cryoCoolant => TowerType.cryo,
    _ => null,
  };
  if (type != null) {
    final sprite = OrionAtlasSprite(
      art: OrionArt.tower(type),
      size: Size.square(spriteSize),
    );
    return locked
        ? ColorFiltered(colorFilter: _lockedSpriteFilter, child: sprite)
        : sprite;
  }
  return Icon(_nodeIcon(upgrade), size: iconSize, color: iconColor);
}

class _TechDetail extends StatelessWidget {
  const _TechDetail({
    super.key,
    required this.upgrade,
    required this.progress,
    required this.techTree,
    required this.isSavingProgress,
    required this.onPurchase,
    required this.onClose,
    required this.maxHeight,
  });

  final VoidCallback onClose;
  final CampaignTechUpgrade upgrade;
  final CampaignProgress progress;
  final CampaignTechTree techTree;
  final bool isSavingProgress;
  final ValueChanged<CampaignTechUpgrade> onPurchase;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final isPurchased = techTree.isPurchased(upgrade);
    // Single source of truth for affordability: the domain rule covers the
    // purchased and unspent-points checks; the view only adds its own
    // save-in-flight gating.
    final unspent = techTree.unspentPoints(progress);
    final canAfford = techTree.canPurchase(upgrade, progress);
    // Purchases are disabled while a save is in flight so the button never
    // presents an enabled affordance that silently no-ops (round-3 review P3).
    final canPurchase = canAfford && !isSavingProgress;
    final largeText = MediaQuery.textScalerOf(context).scale(10) > 15;
    final headerIcon = OrionSurface(
      role: OrionSurfaceRole.card,
      padding: const EdgeInsets.all(10),
      radius: 14,
      child: SizedBox(
        width: 32,
        height: 32,
        child: FittedBox(
          child: _nodeVisual(
            upgrade,
            uiTheme.systemViolet,
            iconSize: 30,
            spriteSize: 40,
          ),
        ),
      ),
    );
    final closeButton = SizedBox.square(
      dimension: 48,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: 'Close upgrade details',
        onPressed: onClose,
        icon: const Icon(Icons.close, size: 18),
      ),
    );
    final titleText = Text(
      upgrade.label,
      // Detail-panel heading for the selected node; reuses the
      // panel's own systemViolet border accent rather than the
      // screen title role (already used once above) or the
      // forbidden textPrimary. Sized as the established sub-heading
      // scale, since its own description sits directly below it.
      style: OrionTypography.microLabel(size: 11, color: uiTheme.systemViolet),
    );
    final descriptionText = Text(
      upgrade.description,
      style: OrionTypography.microLabel(size: 10, color: uiTheme.textMuted),
    );
    final effectText = Text(
      upgrade.effectLabel,
      style: OrionTypography.microLabel(size: 11, color: uiTheme.naniteGreen),
    );
    final costText = Text(
      'Cost: ${upgrade.cost} pts',
      style: OrionTypography.microLabel(size: 10, color: uiTheme.textMuted),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: OrionSurface(
        role: OrionSurfaceRole.sheet,
        padding: largeText
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 14)
            : const EdgeInsets.all(14),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (largeText)
                Row(
                  children: [
                    Expanded(child: titleText),
                    closeButton,
                  ],
                )
              else
                Row(
                  children: [
                    headerIcon,
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          titleText,
                          const SizedBox(height: 2),
                          descriptionText,
                        ],
                      ),
                    ),
                    closeButton,
                  ],
                ),
              const SizedBox(height: 10),
              Flexible(
                fit: FlexFit.loose,
                child: _TechDetailScroll(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      effectText,
                      const SizedBox(height: 2),
                      costText,
                      if (largeText && !isPurchased && !canAfford) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Need ${upgrade.cost - unspent} more points',
                          style: OrionTypography.microLabel(
                            size: 10,
                            color: uiTheme.dangerRed,
                          ),
                        ),
                      ],
                      if (largeText) ...[
                        const SizedBox(height: 6),
                        descriptionText,
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (largeText)
                _buildAction(
                  uiTheme,
                  isPurchased,
                  canPurchase,
                  canAfford,
                  unspent,
                  compactLabel: true,
                  showHint: false,
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _costColumn(uiTheme),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildAction(
                        uiTheme,
                        isPurchased,
                        canPurchase,
                        canAfford,
                        unspent,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _costColumn(OrionUiTheme uiTheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${upgrade.cost}',
          style: OrionTypography.readout(size: 22, color: uiTheme.creditGold),
        ),
        Text(
          'PTS',
          style: OrionTypography.microLabel(size: 10, color: uiTheme.textMuted),
        ),
      ],
    );
  }

  Widget _buildAction(
    OrionUiTheme uiTheme,
    bool isPurchased,
    bool canPurchase,
    bool canAfford,
    int unspent, {
    bool compactLabel = false,
    bool showHint = true,
  }) {
    if (isPurchased) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: uiTheme.naniteGreen),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, size: 14, color: uiTheme.naniteGreen),
              const SizedBox(width: 5),
              Text(
                'Purchased',
                style: OrionTypography.microLabel(
                  size: 11,
                  color: uiTheme.naniteGreen,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (!canAfford) {
      final needed = upgrade.cost - unspent;
      final button = OrionPrimaryButton(
        label: 'Research',
        icon: Icons.diamond,
        variant: OrionButtonVariant.secondary,
        height: 52,
        labelSize: compactLabel ? 10 : 13,
        onPressed: null, // disabled
      );
      if (!showHint) {
        return button;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          button,
          const SizedBox(height: 6),
          Text(
            'Need $needed more points',
            style: OrionTypography.microLabel(
              size: 10,
              color: uiTheme.dangerRed,
            ),
          ),
        ],
      );
    }
    // Affordable but a save is in flight — show a disabled Purchase button
    // rather than the "Need N more points" label, so the user sees the
    // correct reason (waiting on persistence, not lacking points).
    return OrionPrimaryButton(
      label: 'Research',
      icon: Icons.diamond,
      variant: OrionButtonVariant.secondary,
      height: 52,
      labelSize: compactLabel ? 10 : 13,
      onPressed: canPurchase
          ? () => onPurchase(upgrade)
          : null, // disabled while saving
    );
  }
}

class _TechDetailScroll extends StatefulWidget {
  const _TechDetailScroll({required this.child});

  final Widget child;

  @override
  State<_TechDetailScroll> createState() => _TechDetailScrollState();
}

class _TechDetailScrollState extends State<_TechDetailScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _controller,
        padding: const EdgeInsets.only(right: 6),
        child: widget.child,
      ),
    );
  }
}

IconData _nodeIcon(CampaignTechUpgrade upgrade) {
  switch (upgrade) {
    case CampaignTechUpgrade.solarCapacitors:
      return Icons.solar_power;
    case CampaignTechUpgrade.hardenedCore:
      return Icons.shield_rounded;
    case CampaignTechUpgrade.salvageCrew:
      return Icons.paid_rounded;
    case CampaignTechUpgrade.laserTuning:
      return Icons.bolt_rounded;
    case CampaignTechUpgrade.cryoCoolant:
      return Icons.ac_unit_rounded;
  }
}

String _compactEffect(CampaignTechUpgrade upgrade) => switch (upgrade) {
  CampaignTechUpgrade.solarCapacitors =>
    '+${GameBalance.solarCapacitorsGoldBonus} GOLD',
  CampaignTechUpgrade.hardenedCore =>
    '+${GameBalance.hardenedCoreHealthBonus} HULL',
  CampaignTechUpgrade.salvageCrew =>
    '+${(GameBalance.salvageCrewClearBonusFraction * 100).round()}% CLEAR GOLD',
  CampaignTechUpgrade.laserTuning =>
    '+${(GameBalance.laserTuningDamageFraction * 100).round()}% DAMAGE',
  CampaignTechUpgrade.cryoCoolant =>
    '+${GameBalance.cryoCoolantSlowDurationBonus.toStringAsFixed(1)}s SLOW',
};
