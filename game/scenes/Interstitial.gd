extends Control
## Interstitial — a quiet narrative beat shown between days.
##
## Pure view. It is handed an interstitial Dictionary (shape per
## EventDeck.select_interstitial) and reveals its lines one at a time with a
## calm type-on, then offers a quiet "tap anywhere to continue" affordance. It
## holds no game logic; DayShift's flow owns when to show it and what comes next.
##
## An `ArtSlot` node is left as a named placeholder; real art arrives in PR-09.
##
## Lifecycle: setup(interstitial) -> the beat plays -> finished() emits when the
## player advances (or, in headless autoplay, when advance() is called).

## Emitted once the player advances past the beat (or advance() is called).
signal finished()

## Per-character type-on cadence (seconds). Multiplied up when tired so a
## depleted player reads at a slower, heavier pace.
const TYPE_INTERVAL := 0.028

## Pause held after a line finishes typing before the next line fades in.
const LINE_PAUSE := 0.7

## Fade-in duration for each freshly added line.
const LINE_FADE_TIME := 0.5

## Fade-in duration for the "tap to continue" hint once all lines have landed.
const HINT_FADE_TIME := 0.9

## Extra slowdown applied to the type-on per fatigue level (0 fresh .. 3 burnt
## out): a multiplier on TYPE_INTERVAL/LINE_PAUSE. Tireder = slower reveal.
const PACE_BY_FATIGUE := [1.0, 1.15, 1.4, 1.7]

@onready var _lines_box: VBoxContainer = %Lines
@onready var _hint: Label = %ContinueHint
@onready var _art_slot: Control = %ArtSlot

## True once every line has finished revealing and the beat can be advanced.
var _ready_to_advance := false

## True once finished() has fired, so a stray tap can't emit it twice.
var _done := false


func _ready() -> void:
	_hint.modulate.a = 0.0


## Display `interstitial` (shape: { id, lines:[...], art, ... }) and begin the
## type-on reveal. Safe to call once per instance.
func setup(interstitial: Dictionary) -> void:
	var art := String(interstitial.get("art", ""))
	# Hand the art key to the placeholder so PR-09 can resolve it to a real image.
	_art_slot.set_meta("art_key", art)
	if _art_slot.has_node("ArtLabel"):
		(_art_slot.get_node("ArtLabel") as Label).text = "[%s]" % art if not art.is_empty() else ""

	var lines: Array = interstitial.get("lines", [])
	_reveal_lines(lines)


## Reveal each line in turn, then surface the continue hint. The await chain is
## the whole pacing of the beat.
func _reveal_lines(lines: Array) -> void:
	# Accessibility: reduce_motion shows each line at once (no fade, no type-on).
	if _reduce_motion():
		for line in lines:
			var label := _add_line_label()
			label.text = String(line)
			label.modulate.a = 1.0
		_ready_to_advance = true
		_hint.modulate.a = 1.0
		return

	var pace: float = PACE_BY_FATIGUE[clampi(_fatigue_level(), 0, PACE_BY_FATIGUE.size() - 1)]

	for line in lines:
		var label := _add_line_label()
		await _fade_in(label, LINE_FADE_TIME * pace)
		await _type_on(label, String(line), pace)
		await _wait(LINE_PAUSE * pace)

	_ready_to_advance = true
	_fade_in(_hint, HINT_FADE_TIME)


## Build and append an empty, transparent line Label ready to be typed into.
func _add_line_label() -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Themeable hook for PR-09 (the body voice of the beat).
	label.theme_type_variation = &"InterstitialLine"
	label.modulate.a = 0.0
	_lines_box.add_child(label)
	return label


## Type `text` into `label` one character at a time. The cadence is stretched by
## `pace` (tireder = slower).
func _type_on(label: Label, text: String, pace: float) -> void:
	var interval := TYPE_INTERVAL * pace
	for i in text.length():
		label.text = text.substr(0, i + 1)
		await _wait(interval)


func _fade_in(node: CanvasItem, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", 1.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# ---------------------------------------------------------------------------
# Advancing
# ---------------------------------------------------------------------------

## A tap anywhere advances the beat, but only once the lines have all landed so
## the player can't skip the reveal mid-type.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_try_advance()
	elif event is InputEventMouseButton and event.pressed:
		_try_advance()


func _try_advance() -> void:
	if not _ready_to_advance:
		return
	advance()


## Advance past the beat. Public so the headless autoplayer can drive it without
## a real tap. Emits finished() exactly once.
func advance() -> void:
	if _done:
		return
	_done = true
	finished.emit()


## True once the lines are fully revealed and the beat will accept an advance.
func is_ready_to_advance() -> bool:
	return _ready_to_advance


# ---------------------------------------------------------------------------
# Fatigue feel
# ---------------------------------------------------------------------------

## Read the current fatigue level via the GameState autoload, defensively (so a
## bare instantiation without autoloads still works at level 0).
func _fatigue_level() -> int:
	var gs: Object = get_node_or_null("/root/GameState")
	if gs != null:
		return int(gs.fatigue_level())
	return 0


## Accessibility accessor: honor reduce_motion via SaveManager, defensively.
func _reduce_motion() -> bool:
	var sm: Object = get_node_or_null("/root/SaveManager")
	if sm != null:
		return bool(sm.get_setting("reduce_motion", false))
	return false
