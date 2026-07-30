import '../campaign/campaign_progress.dart';
import '../campaign/orion_campaign.dart';
import '../campaign/stage_definition.dart';
import '../campaign/stage_modifier_metadata.dart';
import '../campaign/stage_reward_label.dart';
import '../models/game_models.dart';

class CodexTowerEntry {
  const CodexTowerEntry({
    required this.type,
    required this.label,
    required this.unlockWave,
    required this.baseStats,
    required this.upgradeCost,
    required this.specializationCost,
    required this.specializations,
  });

  final TowerType type;
  final String label;
  final int unlockWave;
  final TowerStats baseStats;
  final int upgradeCost;
  final int specializationCost;
  final List<CodexSpecializationEntry> specializations;
}

class CodexSpecializationEntry {
  const CodexSpecializationEntry({
    required this.specialization,
    required this.label,
    required this.specializedStats,
    required this.description,
  });

  final TowerSpecialization specialization;
  final String label;
  final TowerStats specializedStats;
  final String description;
}

class CodexEnemyEntry {
  const CodexEnemyEntry({
    required this.archetype,
    required this.label,
    required this.stats,
    required this.traits,
    required this.roleDescription,
  });

  final EnemyArchetype archetype;
  final String label;
  final EnemyStats stats;
  final List<EnemyTrait> traits;
  final String roleDescription;
}

class CodexTraitEntry {
  const CodexTraitEntry({
    required this.trait,
    required this.label,
    required this.effect,
  });

  final EnemyTrait trait;
  final String label;
  final String effect;
}

class CodexEffectEntry {
  const CodexEffectEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.relatedSpecializations,
  });

  final String id;
  final String title;
  final String description;
  final List<TowerSpecialization> relatedSpecializations;
}

class CodexStageEntry {
  const CodexStageEntry({
    required this.stage,
    required this.status,
    required this.modifiers,
    required this.waveCount,
    required this.rewardLabel,
  });

  final StageDefinition stage;
  final StageProgressStatus status;
  final List<StageModifierMetadata> modifiers;
  final int waveCount;
  final String? rewardLabel;
}

class CodexData {
  const CodexData._();

  static List<CodexTowerEntry> get towers => [
    for (final type in TowerType.values) towerFor(type),
  ];

  static CodexTowerEntry towerFor(TowerType type) {
    final baseStats = GameBalance.towerStats(type, level: 1);
    return CodexTowerEntry(
      type: type,
      label: type.label,
      unlockWave: GameBalance.towerUnlockWave(type),
      baseStats: baseStats,
      upgradeCost: baseStats.upgradeCost,
      specializationCost: baseStats.specializationCost,
      specializations: [
        for (final spec in GameBalance.specializationsFor(type))
          CodexSpecializationEntry(
            specialization: spec,
            label: spec.label,
            specializedStats: GameBalance.towerStats(
              type,
              level: 3,
              specialization: spec,
            ),
            description: _specializationDescription(spec),
          ),
      ],
    );
  }

  static List<CodexEnemyEntry> get enemies => [
    for (final archetype in EnemyArchetype.values)
      CodexEnemyEntry(
        archetype: archetype,
        label: archetype.label,
        stats: GameBalance.enemyArchetype(archetype),
        traits: EnemyTrait.values
            .where(GameBalance.enemyArchetype(archetype).traits.contains)
            .toList(growable: false),
        roleDescription: _enemyRole(archetype),
      ),
  ];

  static List<CodexTraitEntry> get traits => [
    CodexTraitEntry(
      trait: EnemyTrait.armored,
      label: EnemyTrait.armored.label,
      effect: 'Reduces incoming damage by a flat percentage.',
    ),
    CodexTraitEntry(
      trait: EnemyTrait.shielded,
      label: EnemyTrait.shielded.label,
      effect:
          'Carries a shield that absorbs damage and recharges out of combat.',
    ),
    CodexTraitEntry(
      trait: EnemyTrait.swarm,
      label: EnemyTrait.swarm.label,
      effect: 'Fast and fragile; arrives in large numbers.',
    ),
    CodexTraitEntry(
      trait: EnemyTrait.regen,
      label: EnemyTrait.regen.label,
      effect: 'Regenerates health when not taking damage.',
    ),
    CodexTraitEntry(
      trait: EnemyTrait.heavy,
      label: EnemyTrait.heavy.label,
      effect: 'High health; slow but durable.',
    ),
  ];

  static List<CodexEffectEntry> get effects => [
    CodexEffectEntry(
      id: 'slow',
      title: 'Slow',
      description:
          'Reduces enemy move speed. The strongest slow in play takes '
          'effect — slows do not stack additively.',
      relatedSpecializations: _specsWhere((s) => s.slowMultiplier < 1),
    ),
    CodexEffectEntry(
      id: 'corrosion',
      title: 'Corrosion',
      description:
          'Applies damage over time on hit and shreds armor for the duration.',
      relatedSpecializations: _specsWhere(
        (s) => s.corrosionDamagePerSecond > 0,
      ),
    ),
    CodexEffectEntry(
      id: 'armorShred',
      title: 'Armor Shred',
      description:
          'Permanently strips a fraction of an armored enemy\'s damage reduction per hit.',
      relatedSpecializations: _specsWhere((s) => s.armorShred > 0),
    ),
    CodexEffectEntry(
      id: 'shieldDamage',
      title: 'Shield Damage',
      description:
          'A damage multiplier applied only against shielded enemies\' shields.',
      relatedSpecializations: _specsWhere((s) => s.shieldDamageMultiplier != 1),
    ),
    CodexEffectEntry(
      id: 'pierce',
      title: 'Pierce',
      description: 'A projectile passes through multiple enemies in a line.',
      relatedSpecializations: _specsWhere((s) => s.pierceCount > 0),
    ),
    CodexEffectEntry(
      id: 'chain',
      title: 'Chain Lightning',
      description:
          'Lightning jumps from the primary target to nearby enemies, '
          'with falloff on each jump.',
      relatedSpecializations: _specsWhere((s) => s.chainCount > 0),
    ),
    CodexEffectEntry(
      id: 'splash',
      title: 'Splash',
      description:
          'Area damage around the impact point hits every enemy in radius.',
      relatedSpecializations: _specsWhere((s) => s.splashRadius > 0),
    ),
    CodexEffectEntry(
      id: 'drones',
      title: 'Drones',
      description:
          'The tower launches autonomous drones that engage targets until they expire '
          '(up to a per-bay active cap).',
      relatedSpecializations: _specsWhere((s) => s.droneCount > 0),
    ),
    CodexEffectEntry(
      id: 'gravityField',
      title: 'Gravity Field',
      description:
          'A persistent field ticks damage on enemies inside for its duration '
          'and may also slow them.',
      relatedSpecializations: _specsWhere((s) => s.fieldRadius > 0),
    ),
  ];

  static List<CodexStageEntry> stagesFor(CampaignProgress progress) {
    return [
      for (final stage in OrionCampaign.stages)
        CodexStageEntry(
          stage: stage,
          status: progress.statusFor(stage),
          modifiers: stage.modifiers.isEmpty
              ? const [StageModifierMetadata.standardConditions]
              : [
                  for (final m in stage.modifiers)
                    StageModifierMetadata.forModifier(m),
                ],
          waveCount: stage.waves.length,
          rewardLabel: stageRewardLabel(
            stage,
            isCleared: progress.isCleared(stage.id),
          ),
        ),
    ];
  }

  // --- authored prose (grounded in specializedStats; no tuning literals) ---

  static List<TowerSpecialization> _specsWhere(
    bool Function(TowerStats) predicate,
  ) {
    return [
      for (final spec in TowerSpecialization.values)
        if (predicate(
          GameBalance.towerStats(spec.type, level: 3, specialization: spec),
        ))
          spec,
    ];
  }

  static String _specializationDescription(TowerSpecialization spec) {
    return switch (spec) {
      TowerSpecialization.pulseLaser =>
        'Maximized fire rate for concentrated single-target damage.',
      TowerSpecialization.prismLaser =>
        'Each shot splits to nearby targets at reduced damage.',
      TowerSpecialization.siegeRocket =>
        'Heaviest single hit with the largest splash radius.',
      TowerSpecialization.clusterRocket =>
        'Detonates into clustered sub-explosions across the impact area.',
      TowerSpecialization.deepFreeze =>
        'The strongest, longest slow; locks enemies down at the cost of raw damage.',
      TowerSpecialization.frostbite =>
        'Balanced slow that deals bonus damage to already-slowed enemies.',
      TowerSpecialization.lanceRailgun =>
        'Maximum pierce — punches through the most targets in a line.',
      TowerSpecialization.magneticRailgun =>
        'Trades pierce for bonus damage versus armored enemies.',
      TowerSpecialization.stormRelay =>
        'The longest chain lightning, jumping to the most targets.',
      TowerSpecialization.overloadRelay =>
        'Trades chain count for bonus damage versus shielded enemies.',
      TowerSpecialization.dissolverNanites =>
        'Peak corrosion and armor shred to strip the heaviest plating.',
      TowerSpecialization.replicatorNanites =>
        'Balanced corrosion stream with sustained damage and lighter shred.',
      TowerSpecialization.singularityWell =>
        'The largest, longest-lasting field — also slows enemies caught inside.',
      TowerSpecialization.crushWell =>
        'A tighter, concentrated field for a focused kill zone.',
      TowerSpecialization.interceptorBay =>
        'More, faster-firing drones for broad interception.',
      TowerSpecialization.hunterBay =>
        'Fewer, harder-hitting drones that persist longer.',
    };
  }

  static String _enemyRole(EnemyArchetype archetype) {
    return switch (archetype) {
      EnemyArchetype.basicDrone =>
        'Standard fodder — modest health and no defenses.',
      EnemyArchetype.basicEliteDrone =>
        'A tougher baseline drone with notably more health.',
      EnemyArchetype.armoredDrone =>
        'Reduces incoming damage via armor; favors high single hits.',
      EnemyArchetype.shieldedDrone =>
        'Absorbs hits with a shield that recharges out of combat.',
      EnemyArchetype.swarmDrone => 'Fast, fragile, and numerous.',
      EnemyArchetype.regenDrone =>
        'Heals itself over time when not under fire.',
      EnemyArchetype.heavyDrone => 'A slow, high-health bruiser.',
      EnemyArchetype.armoredHeavyDrone =>
        'A heavy frame with armor — extremely durable.',
      EnemyArchetype.regenHeavyDrone =>
        'A heavy frame that regenerates health.',
    };
  }
}
