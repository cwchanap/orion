/// The Revamp board skin (scene 1a) — the mission board's ground.
///
/// 512x768 matches the board's 8x12 cell ratio exactly, so it maps to the
/// board rect without letterboxing or crop.
class GameBoardSkin {
  const GameBoardSkin._();

  static const String fileName = 'reactor_rim_ui/boards/nebula.png';
  static const String assetPath = 'assets/images/$fileName';
}
