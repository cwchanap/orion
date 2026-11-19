import 'package:orion/game/models/game_models.dart';

enum CampaignReward { bonusGold, bonusHealth, challengeBadge }

class StageDefinition {
  StageDefinition({
    required this.id,
    required this.name,
    required this.mapLabel,
    required this.description,
    required List<GridPosition> pathCells,
    required List<WaveDefinition> waves,
    List<String> unlockDependencies = const [],
    this.isMainPath = true,
    this.mainPathOrder,
    this.reward,
    this.blueprint,
    this.firstClearScrip = 0,
    this.replayScrip = 0,
    required this.mapColumn,
    required this.mapRow,
    List<StageModifier> modifiers = const [],
  }) : pathCells = List.unmodifiable(pathCells),
       waves = List.unmodifiable(waves),
       unlockDependencies = List.unmodifiable(unlockDependencies),
       modifiers = List.unmodifiable(modifiers);

  final String id;
  final String name;
  final String mapLabel;
  final String description;
  final List<GridPosition> pathCells;
  final List<WaveDefinition> waves;
  final List<String> unlockDependencies;
  final bool isMainPath;
  final int? mainPathOrder;
  final CampaignReward? reward;

  /// Boss blueprint module recovered from this stage's first committed clear;
  /// null for lightweight test stages with no blueprint reward.
  final RunModuleId? blueprint;

  /// One-time Scrip bonus paid on this stage's first successful mission
  /// clear (HPA-923); zero for lightweight test fixtures outside campaign
  /// validation.
  final int firstClearScrip;

  /// Medal-scaled Scrip base paid on every successful mission clear,
  /// including the first; zero for lightweight test fixtures outside
  /// campaign validation.
  final int replayScrip;
  final int mapColumn;
  final int mapRow;
  final List<StageModifier> modifiers;
}
