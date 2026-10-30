extends Node
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
class OnlineMenu extends "res://scripts/menu.gd":
	func _is_web() -> bool: return true
func _ready() -> void:
	var menu := OnlineMenu.new()
	add_child(menu)
	await get_tree().process_frame
	var labels: Array = []
	for child in menu.body.get_children():
		if child is Button: labels.append(child.text)
	for name in ["World Editor", "Monsters", "Art", "Music Studio"]:
		check(not labels.has(name), name + " is absent from the online menu")
	for name in ["Adventure", "Options", "Credits"]:
		check(labels.has(name), name + " remains available online")
	print("WEB MENU OK" if failures == 0 else "WEB MENU FAILED")
	Game.quit_game(failures)
