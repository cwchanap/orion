import 'package:orion/game/models/game_models.dart';

/// Filenames for the four always-audible rare transition cues (HPA-385
/// assets). They bypass [CombatSoundLimiter] entirely.
const String waveStartedSound = 'wave_start.wav';
const String bossArrivalSound = 'boss_arrival.wav';
const String bossDefeatedSound = 'boss_defeated.wav';
const String towerSoldSound = 'tower_sold.wav';

/// The 13 high-frequency combat cues that pass through
/// [CombatSoundLimiter]: eight tower-family fire cues, three impact kinds,
/// ordinary enemy destruction, and nonlethal core hits.
///
/// Rare transition cues ([waveStartedSound], [bossArrivalSound],
/// [bossDefeatedSound], [towerSoldSound]) are deliberately not part of this
/// enum so they can never consume admission budget.
enum CombatSoundCue {
  laserFire,
  rocketFire,
  cryoFire,
  railgunFire,
  ionChainFire,
  naniteFire,
  gravityWellFire,
  droneBayFire,
  splashImpact,
  chainImpact,
  pierceImpact,
  enemyDestroyed,
  coreHit;

  /// The HPA-385 WAV filename for this cue. All combat clips are ≤ 500 ms
  /// by asset contract, so the limiter needs no duration tracking.
  String get filename => switch (this) {
    laserFire => 'fire_laser.wav',
    rocketFire => 'fire_rocket.wav',
    cryoFire => 'fire_cryo.wav',
    railgunFire => 'fire_railgun.wav',
    ionChainFire => 'fire_ion_chain.wav',
    naniteFire => 'fire_nanite.wav',
    gravityWellFire => 'fire_gravity_well.wav',
    droneBayFire => 'fire_drone_bay.wav',
    splashImpact => 'impact_splash.wav',
    chainImpact => 'impact_chain.wav',
    pierceImpact => 'impact_pierce.wav',
    enemyDestroyed => 'enemy_destroyed.wav',
    coreHit => 'core_hit.wav',
  };

  /// Minimum milliseconds between two admitted starts of this same cue.
  int get cooldownMs => switch (this) {
    laserFire ||
    rocketFire ||
    cryoFire ||
    railgunFire ||
    ionChainFire ||
    naniteFire ||
    gravityWellFire ||
    droneBayFire => 120,
    splashImpact || chainImpact || pierceImpact => 180,
    enemyDestroyed => 500,
    coreHit => 250,
  };

  /// Whether this cue also consumes the one shared 2-starts-per-500 ms
  /// budget. Enemy destruction and core hits never do, so tower fire cannot
  /// starve them.
  bool get sharesBudget => switch (this) {
    enemyDestroyed || coreHit => false,
    _ => true,
  };

  /// The fire cue for a tower family. Exhaustive so adding a [TowerType]
  /// forces an explicit filename and cue decision.
  static CombatSoundCue fireCueFor(TowerType type) => switch (type) {
    TowerType.laser => laserFire,
    TowerType.rocket => rocketFire,
    TowerType.cryo => cryoFire,
    TowerType.railgun => railgunFire,
    TowerType.ionChain => ionChainFire,
    TowerType.nanite => naniteFire,
    TowerType.gravityWell => gravityWellFire,
    TowerType.droneBay => droneBayFire,
  };
}

/// Pure, synchronous admission control for the 13 high-frequency combat
/// sound cues.
///
/// The caller injects a monotonic wall-clock `nowMs` (the platform backend
/// uses `Stopwatch.elapsedMilliseconds`, tests use a fake clock — never
/// Flame's speed-scaled time). Admission records the timestamp immediately;
/// denied cues are dropped with no catch-up, and there is no
/// reservation/release machinery: an admitted start keeps its timestamp
/// until it naturally expires, so playback errors cannot release budget.
final class CombatSoundLimiter {
  /// Maximum admitted starts across all 11 fire/impact cues in any rolling
  /// [sharedBudgetWindowMs].
  static const int sharedBudgetMaxStarts = 2;

  /// Width of the rolling shared budget window.
  static const int sharedBudgetWindowMs = 500;

  final _lastAdmittedMs = <CombatSoundCue, int>{};
  final _sharedAdmissionMs = <int>[];

  /// Returns whether a start of [cue] at [nowMs] is admitted.
  bool admit(CombatSoundCue cue, {required int nowMs}) {
    final last = _lastAdmittedMs[cue];
    if (last != null && nowMs - last < cue.cooldownMs) {
      return false;
    }
    if (cue.sharesBudget) {
      _sharedAdmissionMs.removeWhere(
        (admittedMs) => nowMs - admittedMs >= sharedBudgetWindowMs,
      );
      if (_sharedAdmissionMs.length >= sharedBudgetMaxStarts) {
        return false;
      }
      _sharedAdmissionMs.add(nowMs);
    }
    _lastAdmittedMs[cue] = nowMs;
    return true;
  }
}
