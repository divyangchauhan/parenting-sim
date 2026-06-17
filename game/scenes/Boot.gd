extends Control
## Boot — temporary launch screen. Confirms the project boots and autoloads load.
## Replaced by the real Boot → MainMenu flow in PR-08.

func _ready() -> void:
	print("Enough — boot OK. Autoloads: GameState, EventDeck, SaveManager, AudioManager, Haptics.")
	# In headless/CI we just want a clean import + ready, then quit gracefully.
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		get_tree().quit(0)
