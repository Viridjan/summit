extends ColorRect
# Title screen, level select, options, credits.

const OptionsPanel := preload("res://scripts/options.gd")
const Bestiary := preload("res://scripts/bestiary.gd")

var body: VBoxContainer
var hint: Label

func _ready() -> void:
	color = Color("141433")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Game.theme
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	body = VBoxContainer.new()
	body.custom_minimum_size = Vector2(520, 0)
	body.add_theme_constant_override("separation", 10)
	center.add_child(body)
	hint = Game.label("", 18)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -40
	hint.modulate = Color(1, 1, 1, 0.6)
	add_child(hint)
	_main()

func _clear() -> void:
	for c in body.get_children():
		c.queue_free()

func _main() -> void:
	_clear()
	hint.text = "Arrows: move    %s / Enter: select    %s / Esc: back" % [Game.key_name("jump"), Game.key_name("dash")]
	body.add_child(Game.label("SUMMIT", 72))
	body.add_child(Game.label("a mountain-climbing platformer", 20))
	body.add_child(HSeparator.new())
	var play := Game.button("Adventure", _adventure)
	body.add_child(play)
	if OS.has_feature("editor"):  # the world files live in res://, writable only from source
		body.add_child(Game.button("World Editor", func(): Game.goto("world_editor")))
	body.add_child(Game.button("Monsters", _monsters))
	body.add_child(Game.button("Music Studio", func(): Game.goto("music_studio")))
	body.add_child(Game.button("Options", _options))
	body.add_child(Game.button("Credits", _credits))
	body.add_child(Game.button("Quit", func(): get_tree().quit()))
	play.grab_focus()

func _adventure() -> void:
	_clear()
	body.add_child(Game.label("Adventure", 44))
	var worlds: Array = Game.world_list()
	var wi := maxi(0, worlds.map(func(w): return w[1]).find(Game.world_path))
	var pick := Game.button("World:  %s  >" % worlds[wi][0], func():
		var nxt: Array = worlds[(wi + 1) % worlds.size()]
		Game.world_path = nxt[1]
		Game.settings.world = "" if nxt[1] == Game.ADVENTURE_DIR + "world.json" else nxt[1]
		Game.save_settings()
		_adventure())
	pick.visible = worlds.size() > 1
	body.add_child(pick)
	var first: Button = null
	if Game.has_adventure_save():
		first = Game.button("Continue", func(): Game.start_adventure(false))
		body.add_child(first)
	var fresh := Game.button("New Game", func(): Game.start_adventure(true))
	body.add_child(fresh)
	var back := Game.button("Back", _main)
	body.add_child(back)
	(first if first else fresh).grab_focus()

func _options() -> void:
	var o := OptionsPanel.new()
	add_child(o)
	o.closed.connect(_main)

func _monsters() -> void:
	_clear()
	body.add_child(Game.label("Monsters", 44))
	var b := Bestiary.new()
	b.custom_minimum_size = Vector2(860, 505)
	body.add_child(b)
	var back := Game.button("Back", _main)
	body.add_child(back)
	back.grab_focus()

func _credits() -> void:
	_clear()
	body.add_child(Game.label("Credits", 44))
	body.add_child(Game.label("Player physics ported from Celeste's Player.cs\n(MIT, Maddy Makes Games - github.com/NoelFB/Celeste)\n\nArt: Paper Pixels by VEXED (v3x3d.itch.io), CC0.\nExtra effects and code: original.\nCeleste is a trademark of Maddy Makes Games.\nThis is an unaffiliated fan project.", 20))
	var back := Game.button("Back", _main)
	body.add_child(back)
	back.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_main()
