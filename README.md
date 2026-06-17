# Enough — a parenting sim *(working title)*

A short, mechanically simple game in the *Papers, Please* mold. Not about winning or
optimizing a child's stats — about evoking the **texture of parenting**: a relentless
stream of small competing demands, never enough time or energy, trade-offs with no clean
answer, and the mix of exhaustion, guilt, and love underneath.

> You triage a day's worth of incoming needs — your child's, your partner's, your work's,
> your own — with finite time, energy, and patience. Every choice spends something. None of
> them are right. As you burn down, the kind option gets harder to reach.

## Platform & stack
- **Engine:** Godot 4.3 (GDScript) — free, no royalties, native mobile export.
- **Target:** Android first (portrait, touch-first). iOS later if Android succeeds.
- **Model:** premium paid game, small scope, high polish.

## Repo layout
| Path | What |
|------|------|
| `docs/` | PRD, game design, architecture, features |
| `tasks.md` | Project board — PRs and their status |
| `game/` | Godot project (`project.godot` lives here) |
| `game/content/` | Data-driven event/request content (writers edit here) |

## Docs
- [Product Requirements (PRD)](docs/PRD.md)
- [Game Design](docs/GAME_DESIGN.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Features](docs/FEATURES.md)
- [Task board](tasks.md)

## Dev
```bash
# Run the game (needs Godot 4.3+ on PATH)
godot --path game

# Headless import / CI check
godot --headless --path game --quit
```
