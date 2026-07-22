import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/tech_tree.dart';

/// Full-screen panel reached from the world map. Shows the player's medal-
/// point bank and all five purchasable tech-tree upgrades.
class TechTreeView extends StatelessWidget {
  const TechTreeView({
    super.key,
    required this.progress,
    required this.techTree,
    this.feedback,
    required this.onPurchase,
    required this.onBack,
  });

  final CampaignProgress progress;
  final CampaignTechTree techTree;
  final String? feedback;

  /// Invoked when the user taps an affordable upgrade's Purchase button.
  final ValueChanged<CampaignTechUpgrade> onPurchase;

  /// Invoked when the user taps the back button.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final earned = CampaignTechTree.totalMedalRank(progress);
    final spent = techTree.totalSpent;
    final unspent = techTree.unspentPoints(progress);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    'Campaign Tech Tree',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Unspent: $unspent · Earned: $earned · Spent: $spent',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (feedback != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  feedback!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final upgrade in CampaignTechUpgrade.values)
                    _UpgradeRow(
                      upgrade: upgrade,
                      progress: progress,
                      techTree: techTree,
                      onPurchase: onPurchase,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpgradeRow extends StatelessWidget {
  const _UpgradeRow({
    required this.upgrade,
    required this.progress,
    required this.techTree,
    required this.onPurchase,
  });

  final CampaignTechUpgrade upgrade;
  final CampaignProgress progress;
  final CampaignTechTree techTree;
  final ValueChanged<CampaignTechUpgrade> onPurchase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPurchased = techTree.isPurchased(upgrade);
    final unspent = techTree.unspentPoints(progress);
    final canAfford = !isPurchased && unspent >= upgrade.cost;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    upgrade.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(upgrade.description, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    upgrade.effectLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Cost: ${upgrade.cost} pts',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            _buildAction(theme, isPurchased, canAfford, unspent),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(
    ThemeData theme,
    bool isPurchased,
    bool canAfford,
    int unspent,
  ) {
    if (isPurchased) {
      return Chip(
        label: Text(
          'Purchased',
          style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
        ),
        backgroundColor: theme.colorScheme.primaryContainer,
      );
    }
    if (canAfford) {
      return FilledButton(
        onPressed: () => onPurchase(upgrade),
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
