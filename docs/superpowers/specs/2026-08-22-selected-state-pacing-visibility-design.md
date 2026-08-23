# Selected-State Pacing Visibility Design

## Problem

`MissionPacingStrip` is currently rendered above every `MissionCommandDock` state. When a cell or tower is selected, the pacing strip extends the build rail or tower inspector farther into the board. Its Pause, speed, and Auto controls consume taps, so board cells underneath those controls cannot be selected even though the pacing frame forwards taps from its non-control space.

## Behavior

Show the pacing strip only when neither a cell nor a tower is selected. Selecting any cell or tower hides the strip and leaves the build rail or tower inspector as the sole bottom command surface. Clearing the selection restores the pacing strip. This applies in every game phase.

The pacing controls and tap-forwarding behavior remain unchanged while the strip is visible.

## Implementation

Keep state selection inside `MissionCommandDock` unchanged. In `OrionGamePage`, conditionally render the pacing strip and its following vertical gap only when both `snapshot.selectedCell` and `snapshot.selectedTower` are null.

This keeps pacing placement in the page-level overlay, avoids adding pacing callbacks to the dock, and restores the pre-redesign replacement behavior with the smallest change.

## Testing

Add widget regression coverage that verifies:

- the pacing strip is present when no cell or tower is selected;
- the pacing strip is absent and the build rail is present when a cell is selected;
- the pacing strip is absent and the tower inspector is present when a tower is selected.

Retain the existing tap-forwarding test because it still covers pacing-frame dead space in the idle state.

## Scope

No game-state, pacing callback, scanner, dock-content, or board-tap arbitration behavior changes are included.
