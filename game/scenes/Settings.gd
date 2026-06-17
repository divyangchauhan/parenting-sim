extends Control
## Settings — calm, considered options screen. Reusable from the MainMenu and the
## in-game Pause overlay.
##
## Every control reads its initial value from SaveManager and writes back through
## SaveManager.set_setting() (which persists immediately and applies live). The
## screen holds no state of its own — SaveManager is the single source of truth.
##
## Emits closed() when the player backs out; the host (MainMenu / Pause) decides
## what that means. "Erase progress" wipes the run save behind a quiet confirm.
##
## Lives under a CanvasLayer when used by Pause so it draws above the paused game;
## as a MainMenu sub-scene it is just a full-rect Control. Its process_mode is set
## to ALWAYS so its controls stay interactive while the tree is paused.

## Emitted when the player backs out of the screen.
signal closed()

## Text-size choices -> text_scale multipliers. Order matches the OptionButton.
const TEXT_SCALE_CHOICES := [
	{"label": "Small", "scale": 0.85},
	{"label": "Normal", "scale": 1.0},
	{"label": "Large", "scale": 1.25},
]

@onready var _master_slider: HSlider = %MasterSlider
@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _haptics_check: CheckButton = %HapticsCheck
@onready var _reduce_motion_check: CheckButton = %ReduceMotionCheck
@onready var _text_size_option: OptionButton = %TextSizeOption
@onready var _back_button: Button = %BackButton
@onready var _erase_button: Button = %EraseButton
@onready var _confirm_dialog: ConfirmationDialog = %ConfirmEraseDialog


func _ready() -> void:
	# Stay live while the game is paused (Pause overlay reuses this screen).
	process_mode = Node.PROCESS_MODE_ALWAYS

	_populate_text_size_options()
	_load_from_settings()
	_wire_controls()


# ---------------------------------------------------------------------------
# Initial population
# ---------------------------------------------------------------------------

func _populate_text_size_options() -> void:
	_text_size_option.clear()
	for choice in TEXT_SCALE_CHOICES:
		_text_size_option.add_item(String(choice["label"]))


## Mirror the persisted settings into every control without triggering writes.
func _load_from_settings() -> void:
	_master_slider.set_value_no_signal(float(SaveManager.get_setting(SaveManager.KEY_MASTER_VOLUME, 1.0)))
	_music_slider.set_value_no_signal(float(SaveManager.get_setting(SaveManager.KEY_MUSIC_VOLUME, 0.8)))
	_sfx_slider.set_value_no_signal(float(SaveManager.get_setting(SaveManager.KEY_SFX_VOLUME, 0.9)))
	_haptics_check.set_pressed_no_signal(bool(SaveManager.get_setting(SaveManager.KEY_HAPTICS, true)))
	_reduce_motion_check.set_pressed_no_signal(bool(SaveManager.get_setting(SaveManager.KEY_REDUCE_MOTION, false)))
	_text_size_option.select(_index_for_text_scale(float(SaveManager.get_setting(SaveManager.KEY_TEXT_SCALE, 1.0))))
	_refresh_erase_button()


## Closest text-size index for a stored scale (defaults to Normal if no match).
func _index_for_text_scale(scale: float) -> int:
	var best := 1
	var best_diff := INF
	for i in TEXT_SCALE_CHOICES.size():
		var diff: float = absf(float(TEXT_SCALE_CHOICES[i]["scale"]) - scale)
		if diff < best_diff:
			best_diff = diff
			best = i
	return best


# ---------------------------------------------------------------------------
# Wiring
# ---------------------------------------------------------------------------

func _wire_controls() -> void:
	_master_slider.value_changed.connect(_on_master_changed)
	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_haptics_check.toggled.connect(_on_haptics_toggled)
	_reduce_motion_check.toggled.connect(_on_reduce_motion_toggled)
	_text_size_option.item_selected.connect(_on_text_size_selected)
	_back_button.pressed.connect(_on_back_pressed)
	_erase_button.pressed.connect(_on_erase_pressed)
	_confirm_dialog.confirmed.connect(_on_erase_confirmed)


# ---------------------------------------------------------------------------
# Control handlers (each persists immediately + applies live via SaveManager)
# ---------------------------------------------------------------------------

func _on_master_changed(value: float) -> void:
	SaveManager.set_setting(SaveManager.KEY_MASTER_VOLUME, value)


func _on_music_changed(value: float) -> void:
	SaveManager.set_setting(SaveManager.KEY_MUSIC_VOLUME, value)


func _on_sfx_changed(value: float) -> void:
	SaveManager.set_setting(SaveManager.KEY_SFX_VOLUME, value)


func _on_haptics_toggled(pressed: bool) -> void:
	SaveManager.set_setting(SaveManager.KEY_HAPTICS, pressed)


func _on_reduce_motion_toggled(pressed: bool) -> void:
	SaveManager.set_setting(SaveManager.KEY_REDUCE_MOTION, pressed)


func _on_text_size_selected(index: int) -> void:
	var i := clampi(index, 0, TEXT_SCALE_CHOICES.size() - 1)
	SaveManager.set_setting(SaveManager.KEY_TEXT_SCALE, float(TEXT_SCALE_CHOICES[i]["scale"]))


func _on_back_pressed() -> void:
	closed.emit()


# ---------------------------------------------------------------------------
# Erase progress (quiet confirm)
# ---------------------------------------------------------------------------

func _on_erase_pressed() -> void:
	_confirm_dialog.popup_centered()


func _on_erase_confirmed() -> void:
	SaveManager.erase_save()
	_refresh_erase_button()


## Erase is only meaningful when a run save exists.
func _refresh_erase_button() -> void:
	_erase_button.disabled = not SaveManager.has_save()
