You are working in /home/viridjan/Projects/videogame on Summit, a Godot 4 pixel platformer with a level/world editor. Fix the concrete issues below, then evaluate the listed optimization candidates.

Read AGENTS.md first. This review was run on 2026-10-25 with Godot 4.7.2, at HEAD 2f01697 plus existing uncommitted work. Re-read the current code because it may have changed. Preserve all unrelated edits; do not reset, stash, regenerate the story, or overwrite other work. Do not commit or push unless the user asks.

Preserve 60 Hz physics, the pixel movement model, movement tuning, authored story layout, the Ape's side-view design, and Nori's brown/gray hair behavior. Do not redesign gameplay to make tests pass.

For each bug, reproduce it, add a meaningful regression test, implement the smallest fix, and rerun the relevant suite. Report what you fixed, what you could not reproduce, and remaining warnings. Do not report success from exit code alone: Godot can return zero after parse/runtime errors.

Evidence is in reports/code-review-2026-10-25/. The reproduction script uses disposable levels and must be run with isolated user data:
    XDG_DATA_HOME=/tmp/summit-claude-review godot --headless --path . --script reports/code-review-2026-10-25/reproduce.gd

CONFIRMED BUGS, IN PRIORITY ORDER

1. Chase path cache reuses an invalid route after the level/configuration changes.
   Location: scripts/entities.gd, ApeChase.update(), around line 1925, and static _plans.
   Key is only w.star_key("") plus Ape x/y. It omits world identity, level geometry, endpoint, effective movement tuning, and relevant simulation settings. Outside adventure, star_key("") is empty for all levels.
   Reproduced in one process with two otherwise identical standalone levels:
     first chase end=200: 90 frames, final feet=(212,224)
     second chase end=350: same 90 frames, same final feet=(212,224)
   The second chase should continue to its own endpoint, but instead stops on the first cached route. Editing a level and playtesting again or switching worlds with matching room names can reuse stale paths.
   Fix cache identity/invalidation for the actual inputs used by the planner. Bound/clear the cache at an appropriate lifecycle point. Avoid hashing full terrain every physics frame.
   Tests: different endpoints, changed terrain at same spawn, distinct levels/worlds, tuning changes, and valid reuse of identical inputs.

2. Benchmark scene fails to compile.
   Location: tests/bench.gd:33, BenchWorld._build().
   Override declares _build() but scripts/world.gd now declares _build(keep_player := false).
   Repro:
     XDG_DATA_HOME=/tmp/summit-claude-bench BENCH_RUNS=1 BENCH_TICKS=5 BENCH_ONLY=normal godot --headless --path . res://tests/bench.tscn --quit-after 120
   Error: "The function signature doesn't match the parent. Parent signature is _build(bool = <default>) -> void".
   The audited process returned exit 0 despite the parse error.
   Match the signature, forward the argument correctly, preserve benchmark Bot behavior, and prove the benchmark actually emits timing results. A quit-after exit is not proof it ran.

3. Missing tuning directory logs errors on a fresh installation.
   Location: scripts/tuning.gd:199, list_presets(); scripts/debug_panel.gd:_fill_presets().
   Opening the debug panel before any tuning preset has been saved calls DirAccess.get_files_at("user://tuning/") on a nonexistent directory.
   Fresh-user smoke run logged this error twice:
     Couldn't open directory at path "user://tuning/".
   Guard the read or create the directory at the appropriate time. Return an empty list cleanly when no presets exist. Do not hide genuine permission/read failures indiscriminately.
   Test fresh user data with no tuning directory, then save/list/delete a disposable preset.

4. Save restoration accepts malformed coordinates and impossible numeric state.
   Location: scripts/adventure.gd:173, restore_run(); scripts/world.gd:_build() consumes run.spawn.
   It validates only spawn array length and top-level exact types, not element types, finite values, or numeric bounds.
   Reproduced input:
     {"room":"room", "spawn":["bad",{}], "blocks":-20, "energy":99999.0}
   Output retains all those values. _build() later constructs Vector2(spawn[0],spawn[1]); malformed coordinates cannot be used safely, and negative blocks produce impossible maximum energy.
   Normalize invalid fields using existing game rules: finite numeric coordinates, valid block count, energy within valid limits, valid counters and collection entries. Decide and test backward-compatible int/float handling instead of blindly rejecting equivalent numeric types. Preserve valid saves.
   Test malformed spawn values, NaN/infinite numbers where supported, negative/oversized energy and blocks, valid legacy saves, and actually constructing a World from the restored run.

5. Ape run-frame cache is inconsistent with its image builder.
   Location: scripts/ape_art.gd:12-15 and build()'s run swing calculation.
   texture() caches by frame % 4 but passes the original unbounded frame into build().
   build() also uses frame % 3 for arm swing, so build("run",0) != build("run",4), even though texture() maps both to the same key.
   Current renderer passes int(clock * 10), so which image gets stored depends on when the Ape first becomes visible. A prior boss/chase can seed images for a later one.
   Define a coherent animation period and canonicalize before both cache lookup and building, or author a consistent four-frame sequence. Normalize equivalent static poses too, where useful.
   Test cold caches first accessed at different clocks and verify equal canonical frames yield equal images. Inspect the loop visually; do not merely change a hash assertion.

TEST-HARNESS RELIABILITY

6. A passing label/exit code currently masks engine errors.
   tests/smoke.gd printed SMOKE OK and exited zero while logging the missing tuning directory errors.
   tests/bench.tscn exited zero after its parse failure.
   Add a practical verification entry point or equivalent mechanism that fails on parse errors, SCRIPT ERROR, failed script loads, and unexpected runtime ERROR lines, while also requiring each runner's success output or actual benchmark result.
   Audit teardown warnings separately: physics logged 41 ObjectDB leaks; smoke logged CanvasItem, texture, text and font RID leaks plus 128 ObjectDB leaks. Counts vary, so do not assert exact counts or assume these are all gameplay leaks. Attribute ownership using --verbose and distinguish test teardown, app-owned resources, and engine/addon behavior. Do not broadly suppress all errors.
   Python unittest discovery passed 12 tests but tools/check_entrances.py emits ResourceWarning for unclosed files; close files with context managers.
   The SFX pool test calls play("jump") 50 times in one synchronous loop, but the 35 ms per-key cooldown rejects nearly all calls. Add a meaningful saturation test with distinct admitted effects / controlled timing and assert actual active voice behavior. Keep tests about behavior rather than source strings.

MEASURED OPTIMIZATION CANDIDATE

7. First sound blocks on full synchronous synthesis.
   Location: scripts/game.gd:get_sfx(), Game.button(); scripts/sfx.gd:_ready().
   get_sfx() constructs the service lazily and _ready() generates all effects, the cave roar and both Ape screams on the main thread before the requested effect starts.
   Measured cold initialization: 187.406 ms in the disposable probe (another run ~190 ms). This can stall the first menu click or action, even when only a UI click is needed.
   Measure again on the current build. Move cost to an explicit loading phase, generate/cache offline using the existing authoring workflow, or stage synthesis without introducing audio/threading hazards. Preserve sound design, independent volume controls, bounded playback, and the left-biased cave roar. Do not silently lower sample quality.
   Report before/after cold and warm timings. Avoid a fragile machine-specific timing assertion in the unit suite.

FURTHER OPTIMIZATION / LOGIC CHECKS — INVESTIGATE, NOT YET PROVEN USER-VISIBLE BUGS

- ApeChase.plan() runs synchronously inside update(): up to 6*7*5 parameter trials, each up to 3600 simulated player frames. Profile an unplannable or difficult edited level, not just the successful story route. If path is empty it only warns, enters chase, and remains stationary. Provide a bounded, explicit fallback without changing authored chase behavior.
- scripts/ape_art.gd rasterizes each polygon by testing every pixel. First-use pose generation happens from Ape.draw(), which also calls load() each draw. Godot may cache that script resource; do not claim disk I/O every frame. Measure cold-pose stalls, canonicalize duplicate poses, then consider prewarming/baking or scanning polygon bounds.
- scripts/world.gd:_near_solid() returns the first matching neighbouring room's tile, whereas Adventure.room_at() prefers open cells in overlapping irregular room bounds. Construct a minimal overlap case and check whether neighbour order incorrectly blocks a valid transition before changing collision rules.
- The chase planner simulates the smaller player footprint while the Ape renders at 32px with a 24px contact box. Determine whether any current route visibly clips the Ape through ceilings/obstacles; keep intentional chase design and physical collision requirements separate. Do not assume route validity for a small runner proves clearance for the Ape.

VALIDATION BASELINE AND REQUIRED FINAL CHECKS

At audit time:
- physics: 0 failure(s), with shutdown ObjectDB warnings.
- smoke: SMOKE OK, but missing-directory errors and shutdown resource leaks.
- SFX, roar, music, environment music, Ape art and character-style scripts: success output; several report teardown warnings.
- Python: 12 tests passed, with unclosed-file warnings.
- benchmark: parse failure, despite exit 0.

Use isolated user data for all checks to avoid touching personal settings, saves or levels. Run commands sequentially or give concurrent processes different XDG_DATA_HOME directories:
    XDG_DATA_HOME=/tmp/summit-claude-check godot --headless --path . res://tests/test.tscn
    XDG_DATA_HOME=/tmp/summit-claude-check godot --headless --path . res://tests/smoke.tscn
    XDG_DATA_HOME=/tmp/summit-claude-check godot --headless --path . --script tests/sfx.gd
    XDG_DATA_HOME=/tmp/summit-claude-check godot --headless --path . --script tests/roar.gd
    XDG_DATA_HOME=/tmp/summit-claude-check godot --headless --path . --script tests/music.gd
    XDG_DATA_HOME=/tmp/summit-claude-check godot --headless --path . --script tests/environment_music.gd
    XDG_DATA_HOME=/tmp/summit-claude-check godot --headless --path . --script tests/ape_art.gd
    XDG_DATA_HOME=/tmp/summit-claude-check godot --headless --path . --script tests/character_style.gd
    python3 -m unittest discover -s tests -p 'test_*.py'
    XDG_DATA_HOME=/tmp/summit-claude-check BENCH_RUNS=1 BENCH_TICKS=120 BENCH_ONLY=normal godot --headless --path . res://tests/bench.tscn
    git diff --check

Also run your new regressions and the disposable reproduction script. After fixes, the probe should show independent chase endpoints and normalized save values; update/remove diagnostic assumptions if the public API changes, without weakening regression coverage. Inspect the Ape animation and smoke scenes on a working display if available. Report limitations explicitly.

Deliver a concise change summary, test results including unexpected engine logs, measured performance changes, and unresolved findings. Do not expand this into a general rewrite.
