import '../util/format.dart';

enum RunModuleId {
  heavyCaliber,
  overclockRelay,
  longSight,
  emergencySalvage,
  cryoReservoir,
  rocketFusing,
}

enum RunModuleAffinity {
  universal('Universal'),
  cryo('Cryo'),
  rocket('Rocket');

  const RunModuleAffinity(this.label);
  final String label;
}

final class RunModuleDefinition {
  const RunModuleDefinition({
    required this.id,
    required this.title,
    required this.affinity,
    this.damageMultiplier = 1,
    this.fireIntervalMultiplier = 1,
    this.rangeMultiplier = 1,
    this.splashRadiusMultiplier = 1,
    this.slowDurationBonus = 0,
    this.immediateGold = 0,
  });

  final RunModuleId id;
  final String title;
  final RunModuleAffinity affinity;
  final double damageMultiplier;
  final double fireIntervalMultiplier;
  final double rangeMultiplier;
  final double splashRadiusMultiplier;
  final double slowDurationBonus;
  final int immediateGold;

  String get effectText => switch (id) {
    RunModuleId.heavyCaliber =>
      'All tower damage rises ${percent(damageMultiplier - 1)}; '
          'attack interval rises ${percent(fireIntervalMultiplier - 1)}.',
    RunModuleId.overclockRelay =>
      'Attack interval drops ${percent(1 - fireIntervalMultiplier)}; '
          'all tower damage drops ${percent(1 - damageMultiplier)}.',
    RunModuleId.longSight =>
      'All towers gain ${percent(rangeMultiplier - 1)} range.',
    RunModuleId.emergencySalvage => 'Gain $immediateGold gold immediately.',
    RunModuleId.cryoReservoir =>
      'Cryo slows last ${number(slowDurationBonus)} seconds longer.',
    RunModuleId.rocketFusing =>
      'Rocket splash grows ${percent(splashRadiusMultiplier - 1)}; '
          'damage drops ${percent(1 - damageMultiplier)}.',
  };
}

const runModuleCatalog = <RunModuleDefinition>[
  RunModuleDefinition(
    id: RunModuleId.heavyCaliber,
    title: 'Heavy Caliber',
    affinity: RunModuleAffinity.universal,
    damageMultiplier: 1.20,
    fireIntervalMultiplier: 1.10,
  ),
  RunModuleDefinition(
    id: RunModuleId.overclockRelay,
    title: 'Overclock Relay',
    affinity: RunModuleAffinity.universal,
    fireIntervalMultiplier: 0.85,
    damageMultiplier: 0.92,
  ),
  RunModuleDefinition(
    id: RunModuleId.longSight,
    title: 'Long Sight',
    affinity: RunModuleAffinity.universal,
    rangeMultiplier: 1.15,
  ),
  RunModuleDefinition(
    id: RunModuleId.emergencySalvage,
    title: 'Emergency Salvage',
    affinity: RunModuleAffinity.universal,
    immediateGold: 90,
  ),
  RunModuleDefinition(
    id: RunModuleId.cryoReservoir,
    title: 'Cryo Reservoir',
    affinity: RunModuleAffinity.cryo,
    slowDurationBonus: 0.60,
  ),
  RunModuleDefinition(
    id: RunModuleId.rocketFusing,
    title: 'Rocket Fusing',
    affinity: RunModuleAffinity.rocket,
    splashRadiusMultiplier: 1.25,
    damageMultiplier: 0.90,
  ),
];

RunModuleDefinition runModuleDefinition(RunModuleId id) =>
    runModuleCatalog.firstWhere((definition) => definition.id == id);

final class RunModuleOffer {
  RunModuleOffer({
    required this.offerId,
    required this.draftNumber,
    required List<RunModuleId> moduleIds,
  }) : moduleIds = List.unmodifiable(moduleIds);

  final int offerId;
  final int draftNumber;
  final List<RunModuleId> moduleIds;
}
