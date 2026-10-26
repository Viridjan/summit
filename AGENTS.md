# Repository Guidelines

## Project Structure & Module Organization

Summit is a Godot 4 platformer with a built-in level editor. `project.godot` configures the application; `main.tscn` is its entry scene. Gameplay and UI live in `scripts/`: `player.gd` handles movement, `world.gd` manages the level, `entities.gd` implements interactive objects, and `editor.gd` provides level editing. `game.gd` is the `Game` autoload. Rendering helpers live in `art.gd`; menu and options screens have separate scripts.

`assets/paper-pixels/` contains sprites and their license. `tests/` contains runnable test scenes and GDScript runners. Consult `README.md` for controls and `TODO.md` for planned work.

## Build, Test, and Development Commands

Run commands from the repository root with Godot 4 installed; the README records testing on 4.4.1 and 4.7.2.

```sh
godot --path . --import                        # Import assets on first setup.
godot --path .                                 # Run the game.
godot -e --path .                              # Open the Godot editor.
godot --headless --path . res://tests/test.tscn # Run physics checks.
godot --headless --path . res://tests/smoke.tscn # Exercise screens and entities.
```

There is no separate build script or configured lint/format command.

## Coding Style & Naming Conventions

Follow existing GDScript conventions: tabs for indentation, `snake_case` for files, functions, and variables, and `UPPER_SNAKE_CASE` for constants. Use explicit parameter and return types where practical and `:=` for inferred local values. Keep changes within the responsible script. Preserve the pixel-based movement model and the configured 60 Hz physics timestep unless deliberately changing gameplay.

## Testing Guidelines

Tests use custom Godot runners, without an external framework or coverage threshold. Add deterministic movement and interaction assertions to `tests/test_runner.gd` using `check(condition, "descriptive behavior")`; its exit code equals the failure count. Extend `tests/smoke.gd` for screen transitions and editor workflows. Run both scenes before submitting gameplay changes, and manually inspect visual changes in the running game.

## Commit & Pull Request Guidelines

Git history is unavailable in this checkout, so no existing commit convention can be verified. Use concise, imperative subjects such as `Fix dash refill after landing`. Describe the behavior changed, reproduction steps, and test results in pull requests. Link relevant issues and include screenshots for UI or art changes.

## Assets & Local Data

Preserve sprite license files and Celeste movement-code attribution. Editor levels save under `user://levels/`; use disposable levels for manual testing and keep personal runtime data out of contributions.

## Story content direction

New optional discoveries must be interactable entities (energy fragments,
characters, or encounters/minibosses), rather than new passive stars. Existing
stars are legacy content being replaced gradually. Three energy fragments grant
one capacity upgrade. Keep most ordinary rooms compact so tall climbs and boss
arenas remain exceptional; preserve safe passages when changing room heights.
