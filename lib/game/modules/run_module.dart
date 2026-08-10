/// Compatibility re-export. Salvage module data and balance configuration
/// (`RunModuleId`, `RunModuleAffinity`, `RunModuleDefinition`,
/// `runModuleCatalog`, `runModuleDefinition`, `RunModuleOffer`) now live in
/// `lib/game/models/game_models.dart`, the single source of truth for game
/// data and tuning. This file re-exports them so existing imports keep
/// compiling; new code should import `game_models.dart` directly.
library;

export '../models/game_models.dart'
    show
        RunModuleId,
        RunModuleAffinity,
        RunModuleDefinition,
        runModuleCatalog,
        runModuleDefinition,
        RunModuleOffer;
