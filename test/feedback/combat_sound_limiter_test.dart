import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/feedback/combat_sound_limiter.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('CombatSoundLimiter', () {
    test('admits two distinct families at the same timestamp', () {
      final limiter = CombatSoundLimiter();
      expect(limiter.admit(CombatSoundCue.laserFire, nowMs: 0), isTrue);
      expect(limiter.admit(CombatSoundCue.cryoFire, nowMs: 0), isTrue);
      // Shared budget is full, so even a fresh family is denied.
      expect(limiter.admit(CombatSoundCue.rocketFire, nowMs: 0), isFalse);
    });

    test('same family fire inside the 120 ms cooldown is denied', () {
      final limiter = CombatSoundLimiter();
      expect(limiter.admit(CombatSoundCue.laserFire, nowMs: 0), isTrue);
      expect(limiter.admit(CombatSoundCue.laserFire, nowMs: 119), isFalse);
      expect(limiter.admit(CombatSoundCue.laserFire, nowMs: 120), isTrue);
    });

    test('impact per-cue cooldown is 180 ms', () {
      final limiter = CombatSoundLimiter();
      expect(limiter.admit(CombatSoundCue.splashImpact, nowMs: 0), isTrue);
      expect(limiter.admit(CombatSoundCue.splashImpact, nowMs: 179), isFalse);
      expect(limiter.admit(CombatSoundCue.splashImpact, nowMs: 180), isTrue);
    });

    test('shared budget denies a third fire or impact start of any kind', () {
      final limiter = CombatSoundLimiter();
      expect(limiter.admit(CombatSoundCue.laserFire, nowMs: 0), isTrue);
      expect(limiter.admit(CombatSoundCue.splashImpact, nowMs: 10), isTrue);
      // Mixed families and impacts compete for the same two slots.
      expect(limiter.admit(CombatSoundCue.chainImpact, nowMs: 20), isFalse);
      expect(limiter.admit(CombatSoundCue.droneBayFire, nowMs: 30), isFalse);
    });

    test('shared budget rolls at exactly 500 ms', () {
      final limiter = CombatSoundLimiter();
      expect(limiter.admit(CombatSoundCue.laserFire, nowMs: 0), isTrue);
      expect(limiter.admit(CombatSoundCue.cryoFire, nowMs: 0), isTrue);
      // Both entries are still inside the window at 499 ms.
      expect(limiter.admit(CombatSoundCue.rocketFire, nowMs: 499), isFalse);
      // Entries are at least 500 ms old and are pruned.
      expect(limiter.admit(CombatSoundCue.rocketFire, nowMs: 500), isTrue);
      expect(limiter.admit(CombatSoundCue.railgunFire, nowMs: 500), isTrue);
      expect(limiter.admit(CombatSoundCue.naniteFire, nowMs: 500), isFalse);
    });

    test(
      'enemy destroyed and core hit are admitted while the fire budget is full',
      () {
        final limiter = CombatSoundLimiter();
        expect(limiter.admit(CombatSoundCue.laserFire, nowMs: 0), isTrue);
        expect(limiter.admit(CombatSoundCue.cryoFire, nowMs: 0), isTrue);
        expect(limiter.admit(CombatSoundCue.enemyDestroyed, nowMs: 1), isTrue);
        expect(limiter.admit(CombatSoundCue.coreHit, nowMs: 1), isTrue);
        // They never consume the shared budget, and their own intervals hold.
        expect(limiter.admit(CombatSoundCue.enemyDestroyed, nowMs: 2), isFalse);
        expect(limiter.admit(CombatSoundCue.coreHit, nowMs: 251), isTrue);
        expect(limiter.admit(CombatSoundCue.coreHit, nowMs: 400), isFalse);
      },
    );

    test('enemy destroyed cooldown is 500 ms', () {
      final limiter = CombatSoundLimiter();
      expect(limiter.admit(CombatSoundCue.enemyDestroyed, nowMs: 0), isTrue);
      expect(limiter.admit(CombatSoundCue.enemyDestroyed, nowMs: 499), isFalse);
      expect(limiter.admit(CombatSoundCue.enemyDestroyed, nowMs: 500), isTrue);
    });

    test('core hit cooldown is 250 ms', () {
      final limiter = CombatSoundLimiter();
      expect(limiter.admit(CombatSoundCue.coreHit, nowMs: 0), isTrue);
      expect(limiter.admit(CombatSoundCue.coreHit, nowMs: 249), isFalse);
      expect(limiter.admit(CombatSoundCue.coreHit, nowMs: 250), isTrue);
      expect(limiter.admit(CombatSoundCue.coreHit, nowMs: 499), isFalse);
      expect(limiter.admit(CombatSoundCue.coreHit, nowMs: 500), isTrue);
    });

    test(
      'at most five high-frequency starts are admitted per rolling 500 ms',
      () {
        // Theoretical maximum: 2 shared fire/impact + 1 enemy destroyed
        // + 2 core hits in any 500 ms window.
        final limiter = CombatSoundLimiter();
        var admitted = 0;
        for (var nowMs = 0; nowMs < 500; nowMs += 10) {
          for (final cue in CombatSoundCue.values) {
            if (limiter.admit(cue, nowMs: nowMs)) {
              admitted++;
            }
          }
        }
        expect(admitted, 5);
      },
    );

    test('limits hold when requests arrive 3x faster', () {
      final slow = CombatSoundLimiter();
      var slowAdmitted = 0;
      for (var nowMs = 0; nowMs < 500; nowMs += 10) {
        for (final cue in CombatSoundCue.values) {
          if (slow.admit(cue, nowMs: nowMs)) {
            slowAdmitted++;
          }
        }
      }
      // 3x game speed compresses the same request stream into a third of
      // the injected wall-clock time.
      final fast = CombatSoundLimiter();
      var fastAdmitted = 0;
      for (var nowMs = 0; nowMs < 500; nowMs += 3) {
        for (final cue in CombatSoundCue.values) {
          if (fast.admit(cue, nowMs: nowMs)) {
            fastAdmitted++;
          }
        }
      }
      expect(slowAdmitted, 5);
      expect(fastAdmitted, slowAdmitted);
    });

    test('denied cues drop without catch-up', () {
      final limiter = CombatSoundLimiter();
      expect(limiter.admit(CombatSoundCue.laserFire, nowMs: 0), isTrue);
      expect(limiter.admit(CombatSoundCue.cryoFire, nowMs: 0), isTrue);
      // Denied requests accumulate no debt and never release timestamps.
      expect(limiter.admit(CombatSoundCue.rocketFire, nowMs: 100), isFalse);
      expect(limiter.admit(CombatSoundCue.rocketFire, nowMs: 200), isFalse);
      expect(limiter.admit(CombatSoundCue.rocketFire, nowMs: 300), isFalse);
      expect(limiter.admit(CombatSoundCue.rocketFire, nowMs: 400), isFalse);
      // When the window frees, exactly one new start is admitted; the
      // dropped requests do not come back.
      expect(limiter.admit(CombatSoundCue.rocketFire, nowMs: 500), isTrue);
      expect(limiter.admit(CombatSoundCue.railgunFire, nowMs: 500), isTrue);
      expect(limiter.admit(CombatSoundCue.naniteFire, nowMs: 500), isFalse);
    });
  });

  group('combat sound mapping', () {
    test('every high-frequency cue maps to its exact asset filename', () {
      final expected = {
        CombatSoundCue.laserFire: 'fire_laser.wav',
        CombatSoundCue.rocketFire: 'fire_rocket.wav',
        CombatSoundCue.cryoFire: 'fire_cryo.wav',
        CombatSoundCue.railgunFire: 'fire_railgun.wav',
        CombatSoundCue.ionChainFire: 'fire_ion_chain.wav',
        CombatSoundCue.naniteFire: 'fire_nanite.wav',
        CombatSoundCue.gravityWellFire: 'fire_gravity_well.wav',
        CombatSoundCue.droneBayFire: 'fire_drone_bay.wav',
        CombatSoundCue.splashImpact: 'impact_splash.wav',
        CombatSoundCue.chainImpact: 'impact_chain.wav',
        CombatSoundCue.pierceImpact: 'impact_pierce.wav',
        CombatSoundCue.enemyDestroyed: 'enemy_destroyed.wav',
        CombatSoundCue.coreHit: 'core_hit.wav',
      };
      for (final cue in CombatSoundCue.values) {
        expect(cue.filename, expected[cue], reason: '$cue filename');
      }
    });

    test('tower families map to their fire cues', () {
      final expected = {
        TowerType.laser: CombatSoundCue.laserFire,
        TowerType.rocket: CombatSoundCue.rocketFire,
        TowerType.cryo: CombatSoundCue.cryoFire,
        TowerType.railgun: CombatSoundCue.railgunFire,
        TowerType.ionChain: CombatSoundCue.ionChainFire,
        TowerType.nanite: CombatSoundCue.naniteFire,
        TowerType.gravityWell: CombatSoundCue.gravityWellFire,
        TowerType.droneBay: CombatSoundCue.droneBayFire,
      };
      for (final type in TowerType.values) {
        expect(
          CombatSoundCue.fireCueFor(type),
          expected[type],
          reason: '$type cue',
        );
      }
    });

    test('rare transition cues bypass the limiter with fixed filenames', () {
      expect(CombatSoundCue.values, hasLength(13));
      expect(waveStartedSound, 'wave_start.wav');
      expect(bossArrivalSound, 'boss_arrival.wav');
      expect(bossDefeatedSound, 'boss_defeated.wav');
      expect(towerSoldSound, 'tower_sold.wav');
    });
  });
}
