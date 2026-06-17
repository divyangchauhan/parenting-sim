extends Control
## Ending — the run's final screen. A mirror, not a scoreboard.
##
## Pure view. Handed an ending Dictionary (shape per EventDeck.select_ending:
## { id, title, lines:[...], ... }) it fades the title and lines in slowly, with
## a lot of breathing room, then offers a single quiet way forward. There is
## deliberately NO score, NO stats, NO "you win" — per GAME_DESIGN the ending is
## tonal and restrained.
##
## Emits dismissed() when the player chooses to move on. Routing that to a real
## MainMenu is PR-08; for now the host (DayShift) decides what dismissal does.

## Emitted when the player takes the single quiet way forward.
signal dismissed()

## Beat held before the title fades in — let the screen sit empty a moment first.
const OPENING_HOLD := 1.0

## Slow fade for the title.
const TITLE_FADE_TIME := 1.6

## Beat held after the title, before the lines begin.
const TITLE_TO_LINES_PAUSE := 1.2

## Each line fades in over this long, with a generous pause between.
const LINE_FADE_TIME := 1.4
const LINE_PAUSE := 1.0

## Fade-in for the quiet "return" affordance once the lines have settled.
const RETURN_FADE_TIME := 1.8

@onready var _title: Label = %Title
@onready var _lines_box: VBoxContainer = %Lines
@onready var _return: Button = %ReturnButton

## True once the closing affordance is live and dismissal is allowed.
var _ready_to_dismiss := false

## True once dismissed() has fired, so it can only fire once.
var _done := false


func _ready() -> void:
	_title.modulate.a = 0.0
	_return.modulate.a = 0.0
	_return.disabled = true
	_return.pressed.connect(_on_return_pressed)


## Display `ending` and play its slow reveal. Safe to call once per instance.
func setup(ending: Dictionary) -> void:
	_title.text = String(ending.get("title", ""))
	_reveal(ending.get("lines", []))


## The whole paced reveal: hold, title, hold, lines (one by one), then the way
## forward. Lots of space by design.
func _reveal(lines: Array) -> void:
	await _wait(OPENING_HOLD)
	await _fade_in(_title, TITLE_FADE_TIME)
	await _wait(TITLE_TO_LINES_PAUSE)

	for line in lines:
		var label := _add_line_label(String(line))
		await _fade_in(label, LINE_FADE_TIME)
		await _wait(LINE_PAUSE)

	_ready_to_dismiss = true
	_return.disabled = false
	_fade_in(_return, RETURN_FADE_TIME)


## Build a line Label (starts transparent, fades in via _reveal).
func _add_line_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Themeable hook for PR-09 (the ending's body voice).
	label.theme_type_variation = &"EndingLine"
	label.modulate.a = 0.0
	_lines_box.add_child(label)
	return label


func _fade_in(node: CanvasItem, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", 1.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# ---------------------------------------------------------------------------
# Dismissing
# ---------------------------------------------------------------------------

func _on_return_pressed() -> void:
	dismiss()


## Take the single quiet way forward. Public so the headless autoplayer can
## drive it without a real press. Emits dismissed() exactly once.
func dismiss() -> void:
	if _done:
		return
	_done = true
	dismissed.emit()


## True once the closing affordance is live and dismissal is allowed.
func is_ready_to_dismiss() -> bool:
	return _ready_to_dismiss
