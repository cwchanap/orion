import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('Character catalog', () {
    test('defines exactly the 12 approved roster entries in Camp order', () {
      expect(Character.values.map((character) => character.name), [
        'hikari',
        'jin',
        'akane',
        'ren',
        'elena',
        'shiori',
        'rin',
        'kaito',
        'sayo',
        'tetsuo',
        'haruto',
        'mio',
      ]);
    });

    test(
      'every entry matches the approved rank, name, signature and skill',
      () {
        const expectedRoster =
            <
              Character,
              ({
                CharacterRank rank,
                String fullName,
                TowerSpecialization signature,
                String signatureName,
                TowerType style,
              })
            >{
              Character.hikari: (
                rank: CharacterRank.s,
                fullName: 'Hikari Amatsu, Dawnbringer',
                signature: TowerSpecialization.prismLaser,
                signatureName: 'Dawnbreak',
                style: TowerType.laser,
              ),
              Character.jin: (
                rank: CharacterRank.s,
                fullName: 'Jin Kamishiro, the Thawed One',
                signature: TowerSpecialization.deepFreeze,
                signatureName: 'Absolute Zero',
                style: TowerType.cryo,
              ),
              Character.akane: (
                rank: CharacterRank.a,
                fullName: 'Akane Hinomori',
                signature: TowerSpecialization.siegeRocket,
                signatureName: 'Hearthfire',
                style: TowerType.rocket,
              ),
              Character.ren: (
                rank: CharacterRank.a,
                fullName: 'Ren Kurosawa',
                signature: TowerSpecialization.singularityWell,
                signatureName: 'Crushing Field',
                style: TowerType.gravityWell,
              ),
              Character.elena: (
                rank: CharacterRank.b,
                fullName: 'Elena Volkova',
                signature: TowerSpecialization.magneticRailgun,
                signatureName: 'Heat Sight',
                style: TowerType.railgun,
              ),
              Character.shiori: (
                rank: CharacterRank.b,
                fullName: 'Dr. Shiori Kusanagi',
                signature: TowerSpecialization.dissolverNanites,
                signatureName: 'Dissolving Serum',
                style: TowerType.nanite,
              ),
              Character.rin: (
                rank: CharacterRank.c,
                fullName: 'Rin Fuyutsuki',
                signature: TowerSpecialization.frostbite,
                signatureName: 'Frostbite',
                style: TowerType.cryo,
              ),
              Character.kaito: (
                rank: CharacterRank.c,
                fullName: 'Kaito Narumi',
                signature: TowerSpecialization.stormRelay,
                signatureName: 'Live Wire',
                style: TowerType.ionChain,
              ),
              Character.sayo: (
                rank: CharacterRank.d,
                fullName: 'Sayo Kitami',
                signature: TowerSpecialization.lanceRailgun,
                signatureName: 'Through Shot',
                style: TowerType.railgun,
              ),
              Character.tetsuo: (
                rank: CharacterRank.d,
                fullName: 'Tetsuo Kanda',
                signature: TowerSpecialization.interceptorBay,
                signatureName: 'Scrap Swarm',
                style: TowerType.droneBay,
              ),
              Character.haruto: (
                rank: CharacterRank.e,
                fullName: 'Haruto Sakaki',
                signature: TowerSpecialization.pulseLaser,
                signatureName: 'Steady Volley',
                style: TowerType.laser,
              ),
              Character.mio: (
                rank: CharacterRank.e,
                fullName: 'Mio Tachibana',
                signature: TowerSpecialization.clusterRocket,
                signatureName: 'Kitchen Fire',
                style: TowerType.rocket,
              ),
            };

        expect(Character.values, hasLength(expectedRoster.length));
        for (final character in Character.values) {
          final expected = expectedRoster[character];
          expect(
            expected,
            isNotNull,
            reason: '${character.name} missing from expected roster',
          );
          expect(character.rank, expected!.rank, reason: character.name);
          expect(character.fullName, expected.fullName, reason: character.name);
          expect(
            character.signature,
            expected.signature,
            reason: character.name,
          );
          expect(
            character.signatureName,
            expected.signatureName,
            reason: character.name,
          );
          expect(character.style, expected.style, reason: character.name);
        }
      },
    );

    test('style is derived from the fixed signature type', () {
      for (final character in Character.values) {
        expect(character.style, character.signature.type);
        expect(
          GameBalance.specializationsFor(character.style),
          contains(character.signature),
          reason: '${character.name} signature must belong to its style',
        );
      }
    });

    test('signatures are unique across the roster', () {
      final signatures = Character.values.map(
        (character) => character.signature,
      );
      expect(signatures.toSet(), hasLength(Character.values.length));
    });

    test('roster styles cover all eight combat types', () {
      expect(
        Character.values.map((character) => character.style).toSet(),
        TowerType.values.toSet(),
      );
    });

    test('the two starters are the E-rank entries', () {
      expect(Character.haruto.rank, CharacterRank.e);
      expect(Character.mio.rank, CharacterRank.e);
    });

    test('every entry has non-empty role, bio and signature name', () {
      for (final character in Character.values) {
        expect(character.role, isNotEmpty, reason: character.name);
        expect(character.bio, isNotEmpty, reason: character.name);
        expect(character.signatureName, isNotEmpty, reason: character.name);
      }
    });

    test('displayName is the capitalized stable save key', () {
      for (final character in Character.values) {
        expect(character.displayName, isNotEmpty, reason: character.name);
        expect(
          character.displayName,
          character.name[0].toUpperCase() + character.name.substring(1),
          reason: character.name,
        );
      }
      expect(Character.shiori.displayName, 'Shiori');
    });

    test('name keys round-trip through asNameMap for persistence', () {
      final byName = Character.values.asNameMap();
      for (final character in Character.values) {
        expect(byName[character.name], same(character));
      }
    });

    test('every CharacterRank has an uppercase label', () {
      for (final rank in CharacterRank.values) {
        expect(rank.label, rank.name.toUpperCase());
      }
      expect(CharacterRank.values, [
        CharacterRank.e,
        CharacterRank.d,
        CharacterRank.c,
        CharacterRank.b,
        CharacterRank.a,
        CharacterRank.s,
      ]);
    });
  });
}
