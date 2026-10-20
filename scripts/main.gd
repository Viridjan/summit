extends Node
# Root node. Holds whichever screen (menu / world / editor) is active.

func _ready() -> void:
	Game.main = self
	Game.goto("menu")
