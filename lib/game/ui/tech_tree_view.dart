import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/tech_tree.dart';
import '../models/game_models.dart';
import 'orion_atlas_sprite.dart';
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
    required this.onBack,
  });

  final CampaignProgress progress;
  final CampaignTechTree techTree;
  final String? feedback;

  /// When true, purchase buttons are disabled (a save is in flight).
  final bool isSavingProgress;

  /// Invoked when the user taps an affordable upgrade's Purchase button.
  final ValueChanged<CampaignTechUpgrade> onPurchase;

  /// Invoked when the user taps the back button.
  final VoidCallback onBack;

  @override
  State<TechTreeView> createState() => _TechTreeViewState();
}

class _TechTreeViewState extends State<TechTreeView> {
  /// Presentation-only selection: which node's detail is on screen. Never
  /// persisted and never read by the parent; real node/detail state (purchased,
  /// affordable, saving) is always derived from [TechTreeView] props on
  /// rebuild so purchases and rollbacks flow through unchanged.
  CampaignTechUpgrade? _selected;

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
    const rows = [
      [CampaignTechUpgrade.solarCapacitors],
      [CampaignTechUpgrade.hardenedCore, CampaignTechUpgrade.salvageCrew],
      [CampaignTechUpgrade.laserTuning],
      [CampaignTechUpgrade.cryoCoolant],
    ];

    return Scaffold(
      backgroundColor: uiTheme.voidBlack,
      body: Stack(
        children: [
          const Positioned.fill(
            child: _TechTreeBackdrop(key: ValueKey('tech-tree-backdrop')),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: widget.onBack,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Expanded(
                        child: OrionTitle(
                          'R & d',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          color: uiTheme.textPrimary,
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
                        size: 9,
                        color: uiTheme.dangerRed,
                      ),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    // Selecting a node opens its details at the top of this scrollable area.
                    key: ValueKey(_selected),
                    padding: EdgeInsets.only(
                      top: _selected == null
                          ? (MediaQuery.sizeOf(context).height * .12).clamp(
                              24,
                              110,
                            )
                          : 12,
                      bottom: 20,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selected != null)
                          _TechDetail(
                            key: ValueKey('tech-detail-${_selected!.id}'),
                            upgrade: _selected!,
                            progress: progress,
                            techTree: techTree,
                            isSavingProgress: widget.isSavingProgress,
                            onPurchase: widget.onPurchase,
                            onClose: () => setState(() => _selected = null),
                          ),
                        if (_selected != null) const SizedBox(height: 20),
                        for (var i = 0; i < rows.length; i++) ...[
                          if (i > 0) const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var j = 0; j < rows[i].length; j++) ...[
                                if (j > 0)
                                  SizedBox(
                                    width:
                                        (MediaQuery.sizeOf(context).width * .15)
                                            .clamp(16, 68),
                                  ),
                                _TechNode(
                                  upgrade: rows[i][j],
                                  isSelected: rows[i][j] == _selected,
                                  isPurchased: techTree.isPurchased(rows[i][j]),
                                  canAfford: techTree.canPurchase(
                                    rows[i][j],
                                    progress,
                                  ),
                                  onSelect: () =>
                                      setState(() => _selected = rows[i][j]),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
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
        ),
        const DecoratedBox(
          key: ValueKey('tech-tree-scrim'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x5505080D),
                Color(0x2205080D),
                Color(0x6605080D),
                Color(0xCC05080D),
              ],
              stops: [0, 0.28, 0.72, 1],
            ),
          ),
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
                  'GOLD MEDALS EARN 3',
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

    return Semantics(
      button: true,
      selected: isSelected,
      label: [
        upgrade.label,
        if (isPurchased) 'Purchased',
        upgrade.effectLabel,
        'Cost ${upgrade.cost} points',
      ].join(' • '),
      excludeSemantics: true,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          key: ValueKey('tech-node-${upgrade.id}'),
          width: (MediaQuery.sizeOf(context).width * .27).clamp(96, 120),
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  key: isSelected
                      ? ValueKey('tech-selected-ring-${upgrade.id}')
                      : null,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        isPurchased
                            ? uiTheme.systemViolet.withValues(alpha: .5)
                            : uiTheme.panelBlue.withValues(alpha: .85),
                        uiTheme.hullBlack.withValues(alpha: .9),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? uiTheme.systemViolet
                          : uiTheme.frameSteel,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: uiTheme.systemViolet.withValues(
                                alpha: 0.4,
                              ),
                              blurRadius: 14,
                              spreadRadius: 1,
                            ),
                          ]
                        : const [],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (upgrade == CampaignTechUpgrade.laserTuning ||
                        upgrade == CampaignTechUpgrade.cryoCoolant)
                      OrionAtlasSprite(
                        art: OrionArt.tower(
                          upgrade == CampaignTechUpgrade.laserTuning
                              ? TowerType.laser
                              : TowerType.cryo,
                        ),
                        size: const Size.square(36),
                      )
                    else
                      Icon(_nodeIcon(upgrade), size: 36, color: accent),
                    const SizedBox(height: 5),
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
                    Text(
                      _compactEffect(upgrade),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: MediaQuery.textScalerOf(
                        context,
                      ).clamp(maxScaleFactor: 1.15),
                      style: OrionTypography.readout(
                        size: 14,
                        color: isPurchased || canAfford
                            ? uiTheme.naniteGreen
                            : uiTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.pentagon,
                          size: 12,
                          color: uiTheme.systemViolet,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${upgrade.cost}',
                          style: OrionTypography.readout(
                            size: 11,
                            color: uiTheme.creditGold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isPurchased)
                Positioned(
                  top: 5,
                  right: 5,
                  child: Icon(
                    Icons.check_circle,
                    key: ValueKey('tech-node-purchased-${upgrade.id}'),
                    size: 17,
                    color: uiTheme.naniteGreen,
                    shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
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
  });

  final VoidCallback onClose;
  final CampaignTechUpgrade upgrade;
  final CampaignProgress progress;
  final CampaignTechTree techTree;
  final bool isSavingProgress;
  final ValueChanged<CampaignTechUpgrade> onPurchase;

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: uiTheme.panelBlue.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: uiTheme.systemViolet.withValues(alpha: 0.55),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    upgrade.label,
                    // Detail-panel heading for the selected node; reuses the
                    // panel's own systemViolet border accent rather than the
                    // screen title role (already used once above) or the
                    // forbidden textPrimary. Sized as the established sub-heading
                    // scale, since its own description sits directly below it.
                    style: OrionTypography.microLabel(
                      size: 11,
                      color: uiTheme.systemViolet,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close upgrade details',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              upgrade.description,
              style: OrionTypography.microLabel(
                size: 9,
                color: uiTheme.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              upgrade.effectLabel,
              style: OrionTypography.microLabel(
                size: 11,
                color: uiTheme.naniteGreen,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Cost: ${upgrade.cost} pts',
              style: OrionTypography.microLabel(
                size: 9,
                color: uiTheme.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            _buildAction(uiTheme, isPurchased, canPurchase, canAfford, unspent),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(
    OrionUiTheme uiTheme,
    bool isPurchased,
    bool canPurchase,
    bool canAfford,
    int unspent,
  ) {
    if (isPurchased) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: uiTheme.naniteGreen),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
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
    if (canPurchase) {
      return FilledButton(
        onPressed: () => onPurchase(upgrade),
        child: const Text('Purchase'),
      );
    }
    // Affordable but a save is in flight — show a disabled Purchase button
    // rather than the "Need N more points" label, so the user sees the
    // correct reason (waiting on persistence, not lacking points).
    if (canAfford) {
      return FilledButton(
        onPressed: null, // disabled while saving
        child: const Text('Purchase'),
      );
    }
    final needed = upgrade.cost - unspent;
    return FilledButton(
      onPressed: null, // disabled
      child: Text('Need $needed more points'),
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
    '+${GameBalance.solarCapacitorsGoldBonus} CR',
  CampaignTechUpgrade.hardenedCore =>
    '+${GameBalance.hardenedCoreHealthBonus} HULL',
  CampaignTechUpgrade.salvageCrew =>
    '+${(GameBalance.salvageCrewClearBonusFraction * 100).round()}%',
  CampaignTechUpgrade.laserTuning =>
    '+${(GameBalance.laserTuningDamageFraction * 100).round()}%',
  CampaignTechUpgrade.cryoCoolant =>
    '+${GameBalance.cryoCoolantSlowDurationBonus.toStringAsFixed(1)}s',
};
