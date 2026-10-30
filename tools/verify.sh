#!/bin/sh
# Verification orchestrator: uses disposable user data, checks success markers and engine error logs, and runs gameplay, audio, art, benchmark and Python checks. Shutdown resource warnings are reported separately.
# Reading help: docs/CODE_GUIDE.md.

# Runs every test runner with throwaway user data. A runner passes only if it prints its success line
# AND logs no parse/script/load errors or unexpected ERROR lines (Godot exits 0 after those).
# Shutdown leak warnings ("leaked at exit", ObjectDB) are reported as counts, not failures.
# Usage: sh tools/verify.sh
cd "$(dirname "$0")/.." || exit 1
DATA=$(mktemp -d /tmp/summit-verify-XXXXXX)
trap 'rm -rf "$DATA"' EXIT
fails=0
# Run one Godot check, requiring its expected success output and rejecting unexpected engine errors.
run() {  # run <success regex> <godot args...>
	want=$1; shift
	out=$(XDG_DATA_HOME="$DATA" timeout 900 godot --headless --path . "$@" 2>&1)
	bad=$(printf '%s\n' "$out" | grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|^ERROR:|^FAIL' | grep -vE 'leaked at exit|ObjectDB|resources still in use')
	leaks=$(printf '%s\n' "$out" | grep -cE 'leaked at exit|ObjectDB instances leaked')
	if printf '%s\n' "$out" | grep -qE "$want" && [ -z "$bad" ]; then
		echo "ok    $* ($leaks leak warnings)"
	else
		echo "FAIL  $*"; printf '%s\n' "$bad" | head -20; fails=$((fails + 1))
	fi
}
run '^0 failure\(s\)' res://tests/test.tscn
run '^SMOKE OK' res://tests/smoke.tscn
run '^WEB MENU OK' res://tests/web_menu.tscn
run '^SFX OK' --script tests/sfx.gd
run '^ROAR OK' --script tests/roar.gd
run '^MUSIC OK' --script tests/music.gd
run '^ENVIRONMENT MUSIC OK' --script tests/environment_music.gd
run '^APE ART OK' --script tests/ape_art.gd
run '^DISCOVERIES OK' --script tests/discoveries.gd
run '^PROGRESSION EDITOR OK' res://tests/progression_editor.tscn
run '^APE RETURN BARRIER OK' res://tests/ape_return_barrier.tscn
run '^EDITOR PLAYTEST OK' res://tests/editor_playtest.tscn
run '^EDITOR SCROLL OK' res://tests/editor_scroll.tscn
run '^EDITOR NAVIGATION OK' res://tests/editor_navigation.tscn
run '^ISLAND ROUTES OK' res://tests/island_routes.tscn
run '^CHARACTER STYLE OK' --script tests/character_style.gd
export BENCH_RUNS=1 BENCH_TICKS=120 BENCH_ONLY=normal
run 'physics med [0-9]' res://tests/bench.tscn
python3 -X dev -m unittest discover -s tests -p 'test_*.py' 2>&1 | grep -qE '^OK$' && echo "ok    python unittest" || { echo "FAIL  python unittest"; fails=$((fails + 1)); }
git diff --check >/dev/null && echo "ok    git diff --check" || { echo "FAIL  git diff --check"; fails=$((fails + 1)); }
echo "$fails failing"
exit "$fails"
