# sokoban.koplugin

A Sokoban plugin for [KOReader](https://github.com/koreader/koreader).

## Concept

Push all crates onto their target squares. You can only push (never pull) a
crate, and you cannot push two crates at once. Think before you move — a wrong
push can make the puzzle unsolvable!

## Planned Features

- **Bundled level packs** — classic XSokoban 90 levels + community packs
- **Custom levels** — load `.xsb` / `.slc` level files from the device
- **Level browser** — sorted by difficulty with completion status
- **Unlimited undo** — step back any number of moves
- **Move and push counters** — track efficiency
- **Best scores** — minimum moves/pushes stored per level
- **Step replay** — replay your solution move by move
- **Landscape support** — wider grid layout in landscape orientation

## Controls

| Action | How |
|--------|-----|
| Move the player | Tap the destination cell or use arrow buttons |
| Undo last move | Tap **Undo** |
| Restart level | Tap **Restart** |
| Next / previous level | Tap **›** / **‹** |
| Open level browser | Tap **Levels** |

## Why e-ink friendly?

Sokoban is turn-based with one screen update per move.
The top-down grid renders cleanly as simple tile glyphs on any resolution.

## License

GPL-3.0
