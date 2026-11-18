import '../campaign/campaign_progress.dart';
import '../campaign/orion_campaign.dart';
import '../campaign/stage_definition.dart';
import '../campaign/stage_modifier_metadata.dart';
import '../campaign/stage_reward_label.dart';
import '../models/game_models.dart';

/// One playable roster member in the Codex. Identity comes from
/// [Character]; combat numbers come from the member's internal style.
class CodexCharacterEntry {
  const CodexCharacterEntry({
    required this.character,
    required this.label,
    required this.baseStats,
    required this.deployCost,
    required this.upgradeCost,
    required this.signatureCost,
    required this.signature,
  });

  final Character character;
  final String label;
  final TowerStats baseStats;
  final int deployCost;
  final int upgradeCost;
  final int signatureCost;
  final CodexSignatureEntry signature;

  /// Authored text a search can hit: the member's names and role, the
  /// internal style label and the fixed signature's names and role
  /// sentence. The style/signature labels are playable-only aliases — they
  /// still appear on inspector and module surfaces, so queries like
  /// "Cryo" or "Deep Freeze" must resolve to the members that field them
  /// without ever advertising an unused combat variant.
  Iterable<String> get searchTerms => [
    label,
    character.fullName,
    character.role,
    character.style.label,
    character.signatureName,
    signature.label,
    signature.specialization.label,
    signature.description,
  ];
}

/// A member's one fixed tier-3 signature — there is no specialization
/// picker, so the Codex exposes exactly this entry per member.
class CodexSignatureEntry {
  const CodexSignatureEntry({
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

  /// Authored text a search can hit: label, role sentence, trait labels.
  Iterable<String> get searchTerms => [
    label,
    roleDescription,
    ...traits.map((t) => t.label),
  ];
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

  /// Authored text a search can hit.
  Iterable<String> get searchTerms => [label, effect];
}

class CodexEffectEntry {
  const CodexEffectEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.relatedCharacters,
  });

  final String id;
  final String title;
  final String description;

  /// The playable members whose fixed signature produces this effect,
  /// deduplicated in [Character.values] order. Derived from the roster —
  /// never from `TowerSpecialization.values`, which holds combat variants
  /// with no playable member.
  final List<Character> relatedCharacters;

  /// Authored text a search can hit: title, description, related member
  /// names and signature names.
  Iterable<String> get searchTerms => [
    title,
    description,
    for (final member in relatedCharacters) ...[
      member.displayName,
      member.signatureName,
    ],
  ];
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

  /// Authored text a search can hit. Dynamic data — status, wave count,
  /// reward label — deliberately stays out of search terms.
  Iterable<String> get searchTerms => [
    stage.name,
    stage.mapLabel,
    stage.description,
    for (final m in modifiers) ...[m.title, m.description],
  ];
}

class CodexData {
  const CodexData._();

  static List<CodexCharacterEntry> get characters => [
    for (final member in Character.values) characterFor(member),
  ];

  static CodexCharacterEntry characterFor(Character character) {
    // The catalog's declared reference level is the member's level-1
    // baseline: apply the same rank+level damage-channel scaling
    // TowerStatsResolver applies in battle and Camp, so the entry shows
    // the member's real deploy numbers (S-rank Hikari reads damage 24,
    // not the raw style's 12). Costs stay style-based — scaling only
    // touches damage channels.
    final factor = GameBalance.characterScalingFactor(character.rank, 1);
    final baseStats = GameBalance.towerStats(
      character.style,
      level: 1,
    ).scaleDamageChannels(factor);
    return CodexCharacterEntry(
      character: character,
      label: character.displayName,
      baseStats: baseStats,
      deployCost: baseStats.cost,
      upgradeCost: baseStats.upgradeCost,
      signatureCost: baseStats.specializationCost,
      signature: CodexSignatureEntry(
        specialization: character.signature,
        label: character.signatureName,
        specializedStats: GameBalance.towerStats(
          character.style,
          level: 3,
          specialization: character.signature,
        ).scaleDamageChannels(factor),
        description: character.signature.role,
      ),
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
          'Carries a shield that absorbs damage before health. Shield recharge is not inherent — it only occurs on stages whose modifier profile grants it.',
    ),
    CodexTraitEntry(
      trait: EnemyTrait.swarm,
      label: EnemyTrait.swarm.label,
      effect: 'Fast and fragile; arrives in large numbers.',
    ),
    CodexTraitEntry(
      trait: EnemyTrait.regen,
      label: EnemyTrait.regen.label,
      effect:
          'Regenerates health continuously. Corrosion suppresses regeneration while it lasts.',
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
      relatedCharacters: _membersWhere((s) => s.slowMultiplier < 1),
    ),
    CodexEffectEntry(
      id: 'corrosion',
      title: 'Corrosion',
      description:
          'Applies damage over time on hit and shreds armor for the duration.',
      relatedCharacters: _membersWhere((s) => s.corrosionDamagePerSecond > 0),
    ),
    CodexEffectEntry(
      id: 'armorShred',
      title: 'Armor Shred',
      description:
          'Temporarily reduces an armored enemy\'s damage reduction while corrosion is active. A stronger application overrides a weaker one rather than stacking, and the reduction resets when corrosion expires.',
      relatedCharacters: _membersWhere((s) => s.armorShred > 0),
    ),
    CodexEffectEntry(
      id: 'shieldDamage',
      title: 'Shield Damage',
      description:
          'A damage multiplier applied only against shielded enemies\' shields.',
      relatedCharacters: _membersWhere((s) => s.shieldDamageMultiplier != 1),
    ),
    CodexEffectEntry(
      id: 'pierce',
      title: 'Pierce',
      description: 'A projectile passes through multiple enemies in a line.',
      relatedCharacters: _membersWhere((s) => s.pierceCount > 0),
    ),
    CodexEffectEntry(
      id: 'chain',
      title: 'Chain Lightning',
      description:
          'Lightning jumps from the primary target to nearby enemies, '
          'with falloff on each jump.',
      relatedCharacters: _membersWhere((s) => s.chainCount > 0),
    ),
    CodexEffectEntry(
      id: 'splash',
      title: 'Splash',
      description:
          'Area damage around the impact point hits every enemy in radius.',
      relatedCharacters: _membersWhere((s) => s.splashRadius > 0),
    ),
    CodexEffectEntry(
      id: 'drones',
      title: 'Drones',
      description:
          'The member launches autonomous drones that engage targets until they expire '
          '(up to a per-bay active cap).',
      relatedCharacters: _membersWhere((s) => s.droneCount > 0),
    ),
    CodexEffectEntry(
      id: 'gravityField',
      title: 'Gravity Field',
      description:
          'A persistent field ticks damage on enemies inside for its duration '
          'and may also slow them.',
      relatedCharacters: _membersWhere((s) => s.fieldRadius > 0),
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

  /// The roster members whose fixed signature's specialized stats satisfy
  /// [predicate], in [Character.values] order. Scanning
  /// `TowerSpecialization.values` here advertised combat variants with no
  /// playable member (Hunter Bay, Overload Relay, Replicator Nanites,
  /// Crush Well) in the Effects view.
  static List<Character> _membersWhere(bool Function(TowerStats) predicate) {
    return [
      for (final member in Character.values)
        if (predicate(
          GameBalance.towerStats(
            member.style,
            level: 3,
            specialization: member.signature,
          ),
        ))
          member,
    ];
  }

  static String _enemyRole(EnemyArchetype archetype) {
    return switch (archetype) {
      EnemyArchetype.basicDrone =>
        'Standard fodder — modest health and no defenses.',
      EnemyArchetype.basicEliteDrone =>
        'A tougher baseline drone with notably more health.',
      EnemyArchetype.armoredDrone =>
        'Reduces incoming damage by a flat percentage. Counter with armor shred or members that deal bonus damage versus armored enemies.',
      EnemyArchetype.shieldedDrone =>
        'Absorbs hits with a shield before health. Recharge only happens on stages that grant it.',
      EnemyArchetype.swarmDrone => 'Fast, fragile, and numerous.',
      EnemyArchetype.regenDrone =>
        'Heals itself over time; corrosion pauses the regeneration.',
      EnemyArchetype.heavyDrone => 'A slow, high-health bruiser.',
      EnemyArchetype.armoredHeavyDrone =>
        'A heavy frame with armor — extremely durable.',
      EnemyArchetype.regenHeavyDrone =>
        'A heavy frame that regenerates health.',
    };
  }
}

/// Pure codex search predicate: an empty (or whitespace-only) query matches
/// everything; otherwise the whole query must occur inside one of [terms],
/// case-insensitively.
bool codexMatches(String query, Iterable<String> terms) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return terms.any((t) => t.trim().toLowerCase().contains(q));
}
