extends Control
## MainMenu — the quiet front door. Title + a short column of calm choices.
##
## Continue is only offered when a run save exists; New starts a fresh run (and
## confirms first if it would overwrite an existing save). Settings opens the
## shared Settings screen as an overlay; Quit leaves the game. Per GAME_DESIGN
## the menu is restrained — no splashy art, no score, just a few considered
## affordances.
##
## Routing target is DayShift; this scene owns the Boot -> MainMenu -> DayShift
## handoff for normal play (Boot routes straight here on a normal launch).

const DAYSHIFT_SCENE := "res://scenes/DayShift.tscn"
const SETTINGS_SCENE := preload("res://scenes/Settings.tscn")

@onready var _continue_button: Button = %ContinueButton
@onready var _new_button: Button = %NewButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _overlay_layer: CanvasLayer = %OverlayLayer
@onready var _confirm_new_dialog: ConfirmationDialog = %ConfirmNewDialog

## The live Settings overlay instance, if open (null otherwise).
var _settings_panel: Control = null


func _ready() -> void:
	_continue_button.pressed.connect(_on_continue_pressed)
	_new_button.pressed.connect(_on_new_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_confirm_new_dialog.confirmed.connect(_start_new_run)

	_refresh_buttons()

	# The quiet front door: the sparse piano motif over a faint room bed. Fades
	# in; guarded so a missing AudioManager / headless boot is simply silent.
	var am := _audio()
	if am != null:
		am.play_room_ambient(2.0)
		am.play_menu_music(2.0)


## Continue is only enabled when there's a save to resume.
func _refresh_buttons() -> void:
	_continue_button.disabled = not SaveManager.has_save()


# ---------------------------------------------------------------------------
# Continue / New
# ---------------------------------------------------------------------------

func _on_continue_pressed() -> void:
	if not SaveManager.load_run():
		# Save vanished or was corrupt; fall back to a fresh run rather than break.
		GameState.new_run()
	_go_to_dayshift()


func _on_new_pressed() -> void:
	# Confirm before clobbering an existing run.
	if SaveManager.has_save():
		_confirm_new_dialog.popup_centered()
	else:
		_start_new_run()


func _start_new_run() -> void:
	GameState.new_run()
	# The fresh run isn't persisted until the first day-boundary autosave; that's
	# fine — Continue stays meaningful (the prior save) until then.
	_go_to_dayshift()


func _go_to_dayshift() -> void:
	# Let the menu motif fade out as we step into the day; DayShift owns the bed
	# from here. A press feedback tap keeps the affordance tactile.
	var am := _audio()
	if am != null:
		am.play_sfx("confirm")
		am.stop_music(0.6)
	var haptics := _haptics()
	if haptics != null:
		haptics.light()
	get_tree().change_scene_to_file(DAYSHIFT_SCENE)


## Resolve the AudioManager autoload defensively (null in bare tests).
func _audio() -> Object:
	return get_node_or_null("/root/AudioManager")


## Resolve the Haptics autoload defensively (null in bare tests).
func _haptics() -> Object:
	return get_node_or_null("/root/Haptics")


# ---------------------------------------------------------------------------
# Settings overlay
# ---------------------------------------------------------------------------

func _on_settings_pressed() -> void:
	if _settings_panel != null:
		return
	_settings_panel = SETTINGS_SCENE.instantiate()
	_settings_panel.closed.connect(_on_settings_closed)
	_overlay_layer.add_child(_settings_panel)


func _on_settings_closed() -> void:
	if _settings_panel != null:
		_settings_panel.queue_free()
		_settings_panel = null
	# Erasing a save inside Settings can flip Continue's availability.
	_refresh_buttons()


# ---------------------------------------------------------------------------
# Quit
# ---------------------------------------------------------------------------

func _on_quit_pressed() -> void:
	get_tree().quit(0)
