import 'package:flutter/material.dart';

import '../models/game_models.dart';
import 'orion_atlas_sprite.dart';
import 'orion_menu_shell.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';

/// Camp roster destination (HPA-922) reached from the bottom navigation —
/// the character counterpart of the removed R&D lab, reusing its bay
/// backdrop until HPA-926 ships final art.
///
/// This is the lightweight Task-2 view: a read-only roster grid covering all
/// twelve [Character] entries with owned levels, locked entries dimmed and
/// the saved squad marked. The full Camp (selection, character sheet,
/// squad picker) arrives with Task 6.
class CampView extends StatelessWidget {
  const CampView({
    super.key,
    required this.ownedLevels,
    required this.squad,
    this.onBack,
    this.embeddedInMenuShell = false,
  });

  /// Owned characters mapped to their persistent level; absent entries are
  /// shown as locked.
  final Map<Character, int> ownedLevels;

  /// The saved squad roster — members carry the SQUAD marker.
  final List<Character> squad;

  final VoidCallback? onBack;
  final bool embeddedInMenuShell;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Material(
      color: uiTheme.voidBlack,
      child: Stack(
        children: [
          const Positioned.fill(child: _CampBackdrop()),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!embeddedInMenuShell)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      onBack == null ? 12 : 4,
                      4,
                      12,
                      0,
                    ),
                    child: Row(
                      children: [
                        if (onBack != null)
                          IconButton(
                            tooltip: 'Back',
                            onPressed: onBack,
                            icon: const Icon(Icons.arrow_back),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'CHARACTER ROSTER',
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
                                'Camp',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                color: uiTheme.textPrimary,
                              ),
                            ],
                          ),
                        ),
                        Semantics(
                          label:
                              '${ownedLevels.length} of '
                              '${Character.values.length} characters recruited',
                          child: OrionResourceChip(
                            icon: Icons.groups_rounded,
                            iconColor: uiTheme.systemViolet,
                            count:
                                '${ownedLevels.length}/${Character.values.length}',
                            semanticsLabel:
                                '${ownedLevels.length} of '
                                '${Character.values.length} characters recruited',
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 210,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.02,
                        ),
                    itemCount: Character.values.length,
                    itemBuilder: (context, index) {
                      final character = Character.values[index];
                      return _CharacterCard(
                        character: character,
                        level: ownedLevels[character],
                        inSquad: squad.contains(character),
                      );
                    },
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

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.character,
    required this.level,
    required this.inSquad,
  });

  final Character character;
  final int? level;
  final bool inSquad;

  Color _rankColor(OrionUiTheme uiTheme) => switch (character.rank) {
    CharacterRank.s => uiTheme.creditGold,
    CharacterRank.a => uiTheme.systemViolet,
    CharacterRank.b => uiTheme.systemCyan,
    CharacterRank.c => uiTheme.naniteGreen,
    CharacterRank.d => uiTheme.medalSilver,
    CharacterRank.e => uiTheme.medalBronze,
  };

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final owned = level != null;
    final rankColor = _rankColor(uiTheme);
    return Semantics(
      label:
          '${character.displayName}, rank ${character.rank.label}, '
          '${owned ? 'level $level' : 'locked'}'
          '${inSquad ? ', squad member' : ''}',
      child: Opacity(
        opacity: owned ? 1 : 0.55,
        child: OrionSurface(
          key: ValueKey('camp-card-${character.name}'),
          role: OrionSurfaceRole.card,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: rankColor.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: rankColor.withValues(alpha: .7),
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      character.rank.label,
                      style: OrionTypography.microLabel(
                        size: 11,
                        color: rankColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (inSquad)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'SQUAD',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OrionTypography.microLabel(
                            size: 10,
                            color: uiTheme.systemViolet,
                          ).copyWith(letterSpacing: 1.1),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                ],
              ),
              const SizedBox(height: 8),
              OrionTitle(
                character.displayName,
                size: 15,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                color: uiTheme.textPrimary,
              ),
              const SizedBox(height: 2),
              Text(
                owned ? 'Lv $level' : 'LOCKED',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: OrionTypography.readout(
                  size: 11,
                  color: owned ? uiTheme.creditGold : uiTheme.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  character.role,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: OrionTypography.microLabel(
                    size: 10,
                    color: uiTheme.textMuted,
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

/// The former R&D bay backdrop (artboard 1g) is intentionally reused as the
/// Camp backdrop until HPA-926 ships final Last Hearth art.
class _CampBackdrop extends StatelessWidget {
  const _CampBackdrop();

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: uiTheme.voidBlack),
        FittedBox(
          key: const ValueKey('camp-backdrop-art'),
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: OrionAtlasSprite(
            art: OrionArt.scene(OrionSceneArt.camp),
            size: const Size.square(640),
          ),
        ),
        const DecoratedBox(
          key: ValueKey('camp-scrim'),
          decoration: BoxDecoration(gradient: orionCampScrim),
        ),
      ],
    );
  }
}
