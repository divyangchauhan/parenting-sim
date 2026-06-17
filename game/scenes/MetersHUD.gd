extends Control
## MetersHUD — pure view of the run's visible resources.
##
## Shows Time (a clock/countdown readout) plus Energy and Patience as labeled
## bars. Subscribes to GameState.resources_changed and reflects it; it holds no
## game state of its own and exposes no API beyond being a passive view.
##
## Visuals are intentionally minimal/neutral now — the real Theme arrives in
## PR-09. Every meaningful node is named so it can be themed later without
## touching this script.

## Duration of the smooth fill tween when a bar changes (seconds). Subtle juice.
const BAR_TWEEN_TIME := 0.25

@onready var _time_value: Label = %TimeValue
@onready var _energy_bar: ProgressBar = %EnergyBar
@onready var _patience_bar: ProgressBar = %PatienceBar
@onready var _energy_value: Label = %EnergyValue
@onready var _patience_value: Label = %PatienceValue

## Active tweens kept so a rapid second change cancels the first cleanly.
var _energy_tween: Tween
var _patience_tween: Tween


func _ready() -> void:
	_energy_bar.max_value = GameState.MAX_ENERGY
	_patience_bar.max_value = GameState.MAX_PATIENCE

	GameState.resources_changed.connect(_on_resources_changed)

	# Reflect the current state immediately (we may have missed the first emit).
	_on_resources_changed(GameState.time, GameState.energy, GameState.patience)


func _on_resources_changed(time: int, energy: int, patience: int) -> void:
	_time_value.text = "%d:00" % time

	_energy_value.text = "%d / %d" % [energy, GameState.MAX_ENERGY]
	_patience_value.text = "%d / %d" % [patience, GameState.MAX_PATIENCE]

	_energy_tween = _tween_bar(_energy_bar, _energy_tween, energy)
	_patience_tween = _tween_bar(_patience_bar, _patience_tween, patience)


## Smoothly animate `bar` to `target`, replacing any in-flight tween.
func _tween_bar(bar: ProgressBar, existing: Tween, target: float) -> Tween:
	if existing != null and existing.is_valid():
		existing.kill()
	var tween := create_tween()
	tween.tween_property(bar, "value", target, BAR_TWEEN_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return tween
