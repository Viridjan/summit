extends Node
# Small entry point attached to the root scene in main.tscn.
# Registers this root as Game.main, then opens the menu. Other screens are children of this root.
# Reading help: docs/CODE_GUIDE.md.

# Root node. Holds whichever screen (menu / world / editor) is active.

# Register this root as the screen host and ask Game to create the main menu.
func _ready() -> void:
	Game.main = self
	Game.goto("menu")
