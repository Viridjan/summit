extends Node
# Reproducible performance benchmarks on disposable in-memory levels (nothing is saved).
#   godot --headless --path . res://tests/bench.tscn   # CPU: physics tick + _draw recording
#   godot --path . res://tests/bench.tscn              # rendered: also whole-frame + render times
# Env: BENCH_OUT=/path/out.json  BENCH_RUNS=3  BENCH_TICKS=600  BENCH_ONLY=normal,dense,...
# Fixed seeds, fixed scripted input. Vsync is turned off in-memory (settings file untouched).

const E := preload("res://scripts/entities.gd")
const WARM := 60
const SEED := 12345

class Bot extends "res://scripts/player.gd":
	var hold := {}
	var tap := {}
	func _init(world, spawn: Vector2) -> void:
		super(world, spawn)
	func _read_input(dt: float) -> void:
		in_x = int(hold.has("right")) - int(hold.has("left"))
		in_y = int(hold.has("down")) - int(hold.has("up"))
		aim_raw = Vector2(in_x, in_y).normalized()
		jump_buf -= dt
		dash_buf -= dt
		if tap.has("jump"): jump_buf = INPUT_BUFFER
		if tap.has("dash"): dash_buf = INPUT_BUFFER
		tap.clear()
		jump_check = hold.has("jump")
		grab_check = hold.has("grab")

class BenchWorld extends "res://scripts/world.gd":
	var draw_us: Array = []
	var counting := false
	var counts := {}
	func _build() -> void:
		super()
		player = Bot.new(self, spawn)
	func _draw() -> void:
		var t := Time.get_ticks_usec()
		super()
		draw_us.append(Time.get_ticks_usec() - t)
	func _count(k: String, scanned: int) -> void:
		if counting:
			counts[k] = counts.get(k, 0) + 1
			counts[k + "_scan"] = counts.get(k + "_scan", 0) + scanned
	func collide_solid(r: Rect2i, ignore = null, skip_dream := false):
		_count("solid", solids.size())
		return super(r, ignore, skip_dream)
	func collide_jumpthru_outside(r_at: Rect2i, r_now: Rect2i):
		_count("jumpthru_outside", jumpthrus.size())
		return super(r_at, r_now)
	func collide_jumpthru(r: Rect2i):
		_count("jumpthru", jumpthrus.size())
		return super(r)
	func collide_dream(r: Rect2i):
		_count("dream", dreams.size())
		return super(r)
	func touching_spikes(r: Rect2i) -> bool:
		_count("spikes", spikes.size())
		return super(r)
	func player_touch(p) -> void:
		_count("touch", touchables.size())
		super(p)

class BenchEditor extends "res://scripts/editor.gd":
	var draw_us: Array = []
	func _draw() -> void:
		var t := Time.get_ticks_usec()
		super()
		draw_us.append(Time.get_ticks_usec() - t)

var rendered := false
var results := {}
var frame_us: Array = []
var render_cpu: Array = []
var render_gpu: Array = []
var last_frame := 0
var vp_rid: RID

func _ready() -> void:
	rendered = DisplayServer.get_name() != "headless"
	Game.main = self
	Game.playtest = true  # never submit records
	for k in ["infinite_stamina", "invincible"]:
		Game.settings[k] = false
	Game.settings.air_dashes = 0
	Game.settings.game_speed = 1.0
	Game.settings.shake = true
	if rendered:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		vp_rid = get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	var runs := int(OS.get_environment("BENCH_RUNS")) if OS.get_environment("BENCH_RUNS") != "" else 3
	var ticks := int(OS.get_environment("BENCH_TICKS")) if OS.get_environment("BENCH_TICKS") != "" else 600
	var only := OS.get_environment("BENCH_ONLY").split(",", false)
	results.meta = {
		"engine": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(),
		"video_adapter": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name(),
		"cpu": OS.get_processor_name(), "os": OS.get_name(), "cores": OS.get_processor_count(),
		"viewport": get_viewport().get_visible_rect().size, "runs": runs, "ticks": ticks, "warmup": WARM,
		"seed": SEED, "time": Time.get_datetime_string_from_system(),
	}
	for sc in ["normal", "dense", "moving", "large_blocks"]:
		if only.is_empty() or sc in only:
			await _world_bench(sc, runs, ticks)
	if only.is_empty() or "editor" in only:
		await _editor_bench()
	var out := OS.get_environment("BENCH_OUT")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(results, "\t"))
	print(JSON.stringify(results, "\t"))
	get_tree().quit()

# ---------------- stats ----------------
static func stats(a: Array) -> Dictionary:
	if a.is_empty():
		return {}
	var s := a.duplicate()
	s.sort()
	var n := s.size()
	var med: float = s[n / 2] if n % 2 == 1 else (s[n / 2 - 1] + s[n / 2]) / 2.0
	return {"median": med, "p95": s[clampi(ceili(0.95 * n) - 1, 0, n - 1)], "max": s[n - 1], "n": n}

func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	if last_frame > 0:
		frame_us.append(now - last_frame)
	last_frame = now
	if rendered:
		render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) * 1000.0)
		render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp_rid) * 1000.0)

func _reset_frames() -> void:
	frame_us.clear(); render_cpu.clear(); render_gpu.clear()
	last_frame = 0

# ---------------- levels ----------------
static func _fill(d: Dictionary, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		var row: String = d.tiles[y]
		d.tiles[y] = row.substr(0, x0) + "1".repeat(x1 - x0 + 1) + row.substr(x1 + 1)

static func level(sc: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var d: Dictionary
	match sc:
		"normal":  # the smoke-test room: every non-goal type once
			d = Game.new_level("bench_normal", 60, 30)
			for pl in [[3, 22, 10, 26], [14, 18, 20, 20], [24, 24, 30, 27], [33, 12, 34, 27]]:
				_fill(d, pl[0], pl[1], pl[2], pl[3])
			d.entities = [{"t": "spawn", "x": 16, "y": 27 * 8}]
			var x := 24
			for t in E.TYPES:
				if t != "goal" and t != "spawn":
					d.entities.append({"t": t, "x": x, "y": 120, "w": 16, "h": 16, "tx": x, "ty": 60})
				x += 24
		"dense":  # 2500 entities above a long corridor
			d = Game.new_level("bench_dense", 240, 40)
			d.entities = [{"t": "spawn", "x": 16, "y": 37 * 8}]
			var touch := ["spikes_up", "refill", "refill_two", "strawberry", "spring_up", "booster", "bumper", "feather"]
			for i in 1500:
				d.entities.append({"t": touch[i % touch.size()], "x": rng.randi_range(2, 237) * 8, "y": rng.randi_range(2, 24) * 8})
			for i in 1000:
				var t: String = ["crumble", "crumble", "jumpthru", "dream"][i % 4]
				d.entities.append({"t": t, "x": rng.randi_range(2, 235) * 8, "y": rng.randi_range(2, 24) * 8, "w": 16 + 8 * (i % 2), "h": 8 if t != "dream" else 16})
		"moving":  # 100 zip movers (kept triggered) + 100 falling blocks (released at start)
			d = Game.new_level("bench_moving", 120, 200)
			d.entities = [{"t": "spawn", "x": 16, "y": 197 * 8}]
			for i in 100:
				var x := rng.randi_range(2, 112) * 8
				var y := rng.randi_range(20, 150) * 8
				d.entities.append({"t": "zip", "x": x, "y": y, "w": 24, "h": 8, "tx": x + rng.randi_range(-8, 8) * 8, "ty": y + rng.randi_range(-8, 8) * 8})
			for i in 100:
				d.entities.append({"t": "falling", "x": rng.randi_range(2, 115) * 8, "y": rng.randi_range(4, 15) * 8, "w": 16, "h": 16})
		"large_blocks":  # 32 blocks of 24x24 tiles; crumble/falling draw per cell, dream draws ~900 stars
			d = Game.new_level("bench_large", 400, 80)
			d.entities = [{"t": "spawn", "x": 16, "y": 77 * 8}]
			var types := ["crumble", "falling", "dream", "zip"]
			for i in 32:
				var x := 16 + (i % 16) * 200
				var y := 16 + (i / 16) * 220
				d.entities.append({"t": types[i % 4], "x": x, "y": y, "w": 192, "h": 192, "tx": x, "ty": y})
		"editor":  # 400x400 random terrain, 3000 entities
			d = Game.new_level("bench_editor", 400, 400)
			for y in range(1, 398):
				var row := "1"
				for x in range(1, 399):
					row += "1" if rng.randf() < 0.3 else "0"
				d.tiles[y] = row + "1"
			var types := E.TYPES.keys()
			types.erase("spawn")
			for i in 3000:
				var t: String = types[rng.randi() % types.size()]
				var e := {"t": t, "x": rng.randi_range(1, 390) * 8, "y": rng.randi_range(1, 390) * 8}
				if E.TYPES[t][1]:
					e.w = rng.randi_range(1, 6) * 8
					e.h = 8 if t == "jumpthru" else rng.randi_range(1, 6) * 8
				if t == "zip":
					e.tx = e.x + 32
					e.ty = e.y
				d.entities.append(e)
	return d

static func input_for(b, tick: int) -> void:
	b.hold = {"right": true} if tick % 240 < 120 else {"left": true}
	if tick % 50 < 15:
		b.hold.jump = true
	if tick % 50 == 0:
		b.tap.jump = true
	if tick % 97 == 0:
		b.tap.dash = true
		b.hold.up = true

# ---------------- world scenarios ----------------
func _world_bench(sc: String, runs: int, ticks: int) -> void:
	var r := {"runs": []}
	var pooled := {"physics_us": [], "draw_us": [], "frame_us": [], "render_cpu_us": [], "render_gpu_us": []}
	for run in runs + 1:  # last pass only counts queries (counting adds overhead)
		var counting := run == runs
		seed(SEED)
		Game.level = level(sc)
		var w := BenchWorld.new()
		add_child(w)
		w.set_physics_process(false)
		if run == 0:
			r.entities = w.ents.size()
			r.size = [w.gw, w.gh]
			r.lists = {"solids": w.solids.size(), "jumpthrus": w.jumpthrus.size(), "touchables": w.touchables.size(), "spikes": w.spikes.size()}
		if sc == "moving":
			for e in w.ents:
				if e is E.FallingBlock:
					e.st = 1
					e.timer = 0.2
		var phys: Array = []
		for tick in WARM + ticks:
			if tick == WARM:
				w.draw_us.clear()
				_reset_frames()
				w.counting = counting
			await get_tree().process_frame
			input_for(w.player, tick)
			if sc == "moving":
				for e in w.ents:
					if e is E.ZipMover and e.st == 0:
						e.st = 1
						e.timer = 0.1
			var t0 := Time.get_ticks_usec()
			w._physics_process(w.DT)
			if tick >= WARM:
				phys.append(Time.get_ticks_usec() - t0)
		await get_tree().process_frame
		if counting:
			var c := {}
			for k in w.counts:
				c[k + "_per_tick"] = snappedf(float(w.counts[k]) / ticks, 0.01)
			r.counts = c
			r.player_end = [w.player.pos, w.player.dead, w.deaths]
		else:
			var run_r := {"physics_us": stats(phys), "draw_us": stats(w.draw_us), "frame_us": stats(frame_us)}
			pooled.physics_us += phys
			pooled.draw_us += w.draw_us
			pooled.frame_us += frame_us
			if rendered:
				run_r.render_cpu_us = stats(render_cpu)
				run_r.render_gpu_us = stats(render_gpu)
				pooled.render_cpu_us += render_cpu
				pooled.render_gpu_us += render_gpu
			# respawn/level build cost
			var b: Array = []
			for i in 10:
				var t0 := Time.get_ticks_usec()
				w._build()
				b.append(Time.get_ticks_usec() - t0)
			run_r.build_us = stats(b)
			r.runs.append(run_r)
		w.queue_free()
		await get_tree().process_frame
	for k in pooled:
		if not pooled[k].is_empty():
			r[k] = stats(pooled[k])
	results[sc] = r
	print("%s physics med %s p95 %s | draw med %s p95 %s" % [sc, r.physics_us.median, r.physics_us.p95, r.draw_us.get("median"), r.draw_us.get("p95")])

# ---------------- editor ----------------
func _time(f: Callable, n: int) -> Dictionary:
	var a: Array = []
	for i in n:
		var t0 := Time.get_ticks_usec()
		f.call(i)
		a.append(Time.get_ticks_usec() - t0)
	return stats(a)

func _editor_bench() -> void:
	seed(SEED)
	var r := {}
	Game.editor_level = level("editor")
	var ed := BenchEditor.new()
	add_child(ed)
	await get_tree().process_frame
	r.size = [ed.level.w, ed.level.h]
	r.entities = ed.level.entities.size()
	r.refresh_us = _time(func(_i): ed._refresh(), 10)
	r.push_undo_us = _time(func(_i): ed._push_undo(), 20)
	ed.undo_stack.clear()
	r.snapshot_bytes = var_to_bytes(ed.level).size()
	var m0 := Performance.get_monitor(Performance.MEMORY_STATIC)
	for i in ed.MAX_UNDO:
		ed._push_undo()
	r.undo_stack_static_mem_bytes = Performance.get_monitor(Performance.MEMORY_STATIC) - m0
	r.undo_us = _time(func(_i): ed._undo(), 20)
	ed.tool = "refill"
	r.place_point_us = _time(func(i): ed._place_point(Vector2i(5 + i * 3, 3)), 20)
	ed.tool = "crumble"
	r.place_rect_us = _time(func(i): ed._place_rect(Vector2i(5 + i * 3, 9), Vector2i(6 + i * 3, 10)), 20)
	r.erase_entity_us = _time(func(_i): ed._erase_entity(ed.level.entities.size() - 1), 20)
	ed.tool = "tile"
	# full-width row strokes alternate fill/clear, so every stroke changes cells
	r.paint_row_us = _time(func(i): ed._paint_line(Vector2i(0, 200), Vector2i(399, 200), i % 2 == 0), 20)
	r.paint_diag_us = _time(func(i): ed._paint_line(Vector2i(0, 0), Vector2i(399, 399), i % 2 == 0), 10)
	# a drag: 400 motion events each painting one new cell along a row
	r.drag_event_us = _time(func(i): ed._paint_line(Vector2i(maxi(i - 1, 0), 150), Vector2i(i, 150), true), 400)
	r.status_process_us = _time(func(_i): ed._process(0.0), 1000)
	r.tiles_hash = ed.level.tiles.hash()
	# drawing at three camera setups
	for cfg in [["zoom3", 3.0], ["zoom2", 2.0], ["zoom0_5", 0.5]]:
		ed.cam.zoom = Vector2(cfg[1], cfg[1])
		ed.cam.position = Vector2(200, 200) * 8
		for i in 10:
			ed.queue_redraw()
			await get_tree().process_frame
		ed.draw_us.clear()
		_reset_frames()
		for i in 120:
			ed.cam.position.x += 1
			ed.queue_redraw()
			await get_tree().process_frame
		r["draw_" + cfg[0] + "_us"] = stats(ed.draw_us)
		r["frame_" + cfg[0] + "_us"] = stats(frame_us)
		if rendered:
			r["render_cpu_" + cfg[0] + "_us"] = stats(render_cpu)
			r["render_gpu_" + cfg[0] + "_us"] = stats(render_gpu)
	ed.queue_free()
	results.editor = r
	print("editor refresh med %s place_point med %s paint_row med %s" % [r.refresh_us.median, r.place_point_us.median, r.paint_row_us.median])
