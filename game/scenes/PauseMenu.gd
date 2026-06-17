extends CanvasLayer
## PauseMenu — the in-game pause overlay (Resume / Settings / Quit to Menu).
##
## DayShift instantiates one of these and shows it on demand. Opening it pauses
## the tree (get_tree().paused = true); Resume unpauses. The overlay and all its
## controls run with PROCESS_MODE_ALWAYS so they stay interactive while the rest
## of the game is frozen.
##
## It reuses the shared Settings screen (same one the MainMenu uses) as a nested
## overlay. Quit to Menu autosaves the run and routes back to the MainMenu — this
## node emits quit_to_menu() and lets DayShift own the actual scene change so the
## flow stays in one place.

## Emitted when the player chooses Quit to Menu (DayShift performs the routing).
signal quit_to_menu()

const SETTINGS_SCENE := preload("res://scenes/Settings.tscn")

@onready var _panel: Control = %Panel
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _menu_button: Button = %QuitToMenuButton

## The live Settings overlay instance while open (null otherwise).
var _settings_panel: Control = null


func _ready() -> void:
	# Stay interactive while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_resume_button.pressed.connect(_on_resume_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)


# ---------------------------------------------------------------------------
# Open / close
# ---------------------------------------------------------------------------

## Show the overlay and pause the game.
func open() -> void:
	visible = true
	get_tree().paused = true


## Hide the overlay and resume the game. Closes any nested Settings first.
func close() -> void:
	_close_settings()
	visible = false
	get_tree().paused = false


func is_open() -> bool:
	return visible


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------

func _on_resume_pressed() -> void:
	close()


func _on_settings_pressed() -> void:
	if _settings_panel != null:
		return
	_settings_panel = SETTINGS_SCENE.instantiate()
	_settings_panel.closed.connect(_close_settings)
	add_child(_settings_panel)
	_panel.visible = false


func _close_settings() -> void:
	if _settings_panel != null:
		_settings_panel.queue_free()
		_settings_panel = null
	_panel.visible = true


func _on_menu_pressed() -> void:
	# Unpause before leaving so the next scene isn't frozen; autosave + routing
	# are DayShift's job (it owns GameState + the scene change).
	get_tree().paused = false
	quit_to_menu.emit()
