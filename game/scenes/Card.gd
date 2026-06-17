extends PanelContainer
## Card — a single request card with its response buttons.
##
## Per ARCHITECTURE.md this node holds NO business logic. It renders the card
## Dictionary it is handed and emits the player's *intent* — which response was
## chosen, or that the card was deferred. Resolving that intent (spending cost,
## applying effects, queue management) is DayShift's / GameState's job.
##
## The only state it consults is GameState's gating queries, used purely to
## decide whether a response button is shown disabled. A gated-but-visible warm
## option is deliberate: the player should *see* the kind choice they can't
## currently afford.
##
## Visuals are minimal/neutral now (PR-09 brings the Theme). Nodes are named and
## response buttons carry a `tone`/`source` hint via meta + theme_type_variation
## so they can be themed later without code changes.

## Emitted when the player picks a response. Payload is the raw response Dict.
signal chosen(response: Dictionary)

## Emitted when the player defers the card ("Not now").
signal deferred()

## Enter/exit animation tunables (subtle juice; DayShift awaits play_exit()).
## Effective durations are divided by `_anim_speed`, so a tired (slower) speed
## stretches them — the card literally moves slower when the player is depleted.
const ENTER_TIME := 0.18
const EXIT_TIME := 0.16
const ENTER_OFFSET := 24.0

## Terser "defer" affordance label per fatigue level (0 fresh .. 3 burnt out).
## UI chrome only (not authored story); index is clamped to the array.
const DEFER_TEXT_BY_FATIGUE := ["Not now", "Not now", "Later", "No"]

## Quiet, non-punitive subtext appended to a warm option locked by low reserve —
## "present, not punitive". Shown only for fatigue-gated (not merely unaffordable)
## warm/attentive options.
const UNAVAILABLE_HINT := "  —not right now"

@onready var _source_tag: Label = %SourceTag
@onready var _prompt: Label = %Prompt
@onready var _responses_box: VBoxContainer = %Responses
@onready var _defer_button: Button = %DeferButton

## Animation-speed multiplier handed down from DayShift (1.0 = normal, < 1.0 =
## slower). Set before setup()/play_enter(); defaults to normal speed.
var _anim_speed: float = 1.0


func _ready() -> void:
	_defer_button.pressed.connect(_on_defer_pressed)


## Set the animation-speed multiplier (from FatigueFX via DayShift). Lower =
## slower transitions. Called before setup()/play_enter().
func set_anim_speed(speed: float) -> void:
	_anim_speed = maxf(speed, 0.01)


## Render `card` (shape per content/schema.md) and build its response buttons.
func setup(card: Dictionary) -> void:
	var source := String(card.get("source", ""))
	_source_tag.text = source.to_upper()
	# Themeable-by-source hook: PR-09 can style per source via this variation.
	_source_tag.theme_type_variation = &"SourceTag_%s" % source

	_prompt.text = String(card.get("prompt", ""))

	# Terser defer affordance as fatigue rises (display-only chrome).
	var level := clampi(GameState.fatigue_level(), 0, DEFER_TEXT_BY_FATIGUE.size() - 1)
	_defer_button.text = DEFER_TEXT_BY_FATIGUE[level]

	for child in _responses_box.get_children():
		child.queue_free()

	var responses: Array = card.get("responses", [])
	for response in responses:
		_responses_box.add_child(_build_response_button(response))


## Build one response button, disabled (greyed, non-interactive) when the
## response is gated or unaffordable so the option stays visibly present.
func _build_response_button(response: Dictionary) -> Button:
	var button := Button.new()
	button.text = String(response.get("text", ""))
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE

	# Themeable-by-tone hook for PR-09.
	var tone := String(response.get("tone", "neutral"))
	button.theme_type_variation = &"ResponseButton_%s" % tone
	button.set_meta("tone", tone)
	button.set_meta("response", response)

	var gated := GameState.is_response_gated(response.get("gated_by", {}))
	var unaffordable := not GameState.can_afford(response.get("cost", {}))
	button.disabled = gated or unaffordable

	# When a warm/attentive option is locked specifically by low reserve (fatigue
	# gating), append a small, quiet reason — present, not punitive. Unaffordable
	# (out of time/resource) options stay bare; this hint is about "not in you".
	if gated and tone == "warm":
		button.text += UNAVAILABLE_HINT

	# Intent only — DayShift resolves it.
	button.pressed.connect(func() -> void: chosen.emit(response))
	return button


## Returns true if every response button is disabled — a fully blocked card the
## player can only defer. DayShift uses this to avoid dead-ends.
func all_responses_disabled() -> bool:
	for child in _responses_box.get_children():
		if child is Button and not child.disabled:
			return false
	return true


# ---------------------------------------------------------------------------
# Enter / exit animation hooks
# ---------------------------------------------------------------------------

## Subtle slide+fade in. Called by DayShift after the card is added. Duration is
## stretched by lower _anim_speed so it visibly slows when the player is tired.
func play_enter() -> void:
	var enter_time := ENTER_TIME / _anim_speed
	modulate.a = 0.0
	position.y += ENTER_OFFSET
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, enter_time)
	tween.tween_property(self, "position:y", position.y - ENTER_OFFSET, enter_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Subtle fade out. Awaited by DayShift before presenting the next card. Duration
## is stretched by lower _anim_speed (tireder = slower).
func play_exit() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, EXIT_TIME / _anim_speed) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished


func _on_defer_pressed() -> void:
	deferred.emit()
