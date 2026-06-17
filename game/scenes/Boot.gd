extends Control
## Boot — temporary launch screen. Confirms the project boots and autoloads load,
## then starts a real run by switching to DayShift. Replaced by the full
## Boot -> MainMenu flow in PR-08.
##
## Three launch modes:
##   - AUTOPLAY=1 headless : start a run and let Autoplayer drive it end to end.
##   - plain headless (CI) : print boot OK and quit 0 WITHOUT autoplaying.
##   - normal (display)    : go to the MainMenu (Continue / New / Settings / Quit).

const DAYSHIFT_SCENE := "res://scenes/DayShift.tscn"
const MAIN_MENU_SCENE := "res://scenes/MainMenu.tscn"
const AUTOPLAYER_SCRIPT := preload("res://scenes/Autoplayer.gd")


func _ready() -> void:
	print("Enough — boot OK. Autoloads: GameState, EventDeck, SaveManager, AudioManager, Haptics.")

	if OS.get_environment("AUTOPLAY") == "1":
		await _start_autoplay()
		return

	# Headless CI smoke: clean import + ready, then quit. No autoplay.
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		get_tree().quit(0)
		return

	# Normal play: hand off to the MainMenu (Continue / New / Settings / Quit).
	# Wait a frame first so we never swap scenes while the tree is still busy
	# building Boot's own subtree (avoids a "parent busy adding/removing" error).
	await get_tree().process_frame
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## Drive the real DayShift + Card + autoloads headlessly to completion.
func _start_autoplay() -> void:
	# Wait one frame so the root is no longer busy setting up Boot's subtree
	# before we parent the harness nodes onto it.
	await get_tree().process_frame

	GameState.new_run()

	var dayshift: Node = load(DAYSHIFT_SCENE).instantiate()
	var autoplayer: Node = AUTOPLAYER_SCRIPT.new()
	# Add the autoplayer first, then wire it to DayShift's signals BEFORE
	# DayShift enters the tree, so we catch the very first card it presents.
	get_tree().root.add_child(autoplayer)
	autoplayer.start_pending(dayshift)
	get_tree().root.add_child(dayshift)
