extends SceneTree
# Checks the requested Nori hair cues: brown with available dash, gray when spent and brown again after refill.
# Reading help: docs/CODE_GUIDE.md.


var failures := 0

# Record a failed expectation with its explanation so the runner can report failures and return an appropriate exit code.
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

# Godot calls this SceneTree entry point at startup; begin or schedule the standalone runner workload.
func _initialize() -> void:
	call_deferred("run")

# Execute this standalone regression workload and quit with its accumulated failure count.
func run() -> void:
	var art = load("res://scripts/character_art.gd")
	var player = load("res://scripts/player.gd").new(null, Vector2.ZERO)
	player.dashes = 1
	var brown: Color = player.hair_color()
	check(brown.r > brown.g and brown.g > brown.b and brown.r < 0.4, "Ready hair is dark brown")
	player.dashes = 0
	var gray: Color = player.hair_color()
	check(absf(gray.r-gray.g) < 0.025 and absf(gray.g-gray.b) < 0.025, "Spent dash makes hair gray")
	for shade in art.hair_shades(gray).values():
		check(absf(shade.r-shade.g) < 0.025 and absf(shade.g-shade.b) < 0.025, "Gray hair highlights and shadows stay neutral")
	player.dashes = 1
	check(player.hair_color() == brown, "Dash refill restores brown hair")
	print("CHARACTER STYLE OK" if failures == 0 else "CHARACTER STYLE FAILED")
	quit(failures)
