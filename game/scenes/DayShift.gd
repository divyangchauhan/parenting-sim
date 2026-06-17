extends Control
## DayShift — the core loop screen. Owns the live day queue.
##
## On start it asks GameState to open the day and EventDeck for the day's
## eligible cards, then presents them one at a time. It is the *only* owner of
## the runtime queue: consumption, deferral re-surfacing, and inserting deferred
## consequence follow-ups all happen here. Cards render data and emit intent;
## GameState resolves the numbers. DayShift sits between them.
##
## The day ends when the clock runs out (GameState.time <= 0) or the queue
## empties. Routing to the interstitial / ending screens is a later PR — there
## is a clearly marked TODO hook for that transition.

## Emitted once the day's loop has finished and GameState.end_day() has run.
signal day_finished(day: int)

## Emitted each time a Card is presented, with the live Card node. The headless
## autoplayer connects to this to drive choices; normal play ignores it.
signal card_presented(card_node)

## Emitted when a between-day Interstitial overlay is presented, with the live
## Interstitial node. A driver (the autoplayer) connects to auto-advance it; the
## flow itself awaits the node's finished() either way.
signal interstitial_shown(interstitial_node)

## Emitted when the final Ending screen is presented, with the live Ending node.
## A driver connects to assert completion / auto-dismiss; normal play just shows
## it and waits for the player.
signal ending_shown(ending_node)

## How many slots ahead of the front a follow-up consequence is inserted.
const FOLLOWUP_INSERT_OFFSET := 2

## A card may be deferred at most this many times; after that it is forced to
## the front and must be answered, so deferral can never loop forever.
const MAX_DEFERS_PER_CARD := 2

const CARD_SCENE := preload("res://scenes/Card.tscn")
const INTERSTITIAL_SCENE := preload("res://scenes/Interstitial.tscn")
const ENDING_SCENE := preload("res://scenes/Ending.tscn")
const FATIGUE_FX_SCRIPT := preload("res://scenes/FatigueFX.gd")

## CanvasLayer the narrative overlays (Interstitial / Ending) draw on. Above the
## fatigue FX (layer 1) but below the HUD (layer 2) — though the HUD is hidden
## during these beats anyway via _set_chrome_visible().
const OVERLAY_CANVAS_LAYER := 3

## Day-1 = Monday weekday labels for the day-open frame line.
const WEEKDAYS := ["Monday", "Tuesday", "Wednesday", "Thursday",
	"Friday", "Saturday", "Sunday"]

## Terser day-open frame line per fatigue level (0 fresh .. 3 burnt out). As the
## player tires the chrome gets shorter and flatter. Kept in code (UI chrome, not
## authored story); "%s" takes the weekday, "%d" the day index. Index is clamped.
const DAY_FRAME_BY_FATIGUE := [
	"Day %d. %s. A fresh start.",
	"Day %d. %s.",
	"Day %d. %s. Again.",
	"%s. Again.",
]

@onready var _day_label: Label = %DayLabel
@onready var _card_container: Control = %CardContainer
@onready var _hud_layer: CanvasLayer = $HUDLayer

## The hosted post-effect node; also the source of the shared anim_speed factor.
var _fatigue_fx: Node = null

## Holds the narrative overlays (Interstitial / Ending), lazily created.
var _overlay_layer: CanvasLayer = null

## Set true once GameState.run_ended() fires. end_day() emits it synchronously,
## so the flow can read this flag immediately after calling end_day().
var _run_ended := false

## Live queue of card Dictionaries for the current day (front = next up).
var _queue: Array = []

## Card ids already seen/answered this day (so follow-ups don't re-fire).
var _seen_ids: Dictionary = {}

## Card ids currently sitting in _queue (cheap membership / dedup check).
var _queued_ids: Dictionary = {}

## id -> times deferred this day, to enforce MAX_DEFERS_PER_CARD.
var _defer_counts: Dictionary = {}

## The card node on screen right now (null between cards).
var _current_card: Node = null

## Guards re-entrancy while a card is animating out / the next is spawning.
var _advancing := false

var _day_over := false


func _ready() -> void:
	# Host the fatigue post-effect. Its CanvasLayer (layer 1) sits above the card
	# UI; the MetersHUD lives on HUDLayer (layer 2) above it, so the HUD stays
	# full-colour and readable while the card world desaturates and dims.
	_fatigue_fx = FATIGUE_FX_SCRIPT.new()
	_fatigue_fx.name = "FatigueFX"
	add_child(_fatigue_fx)

	GameState.run_ended.connect(_on_run_ended)
	start_shift()


## Current animation-speed multiplier from the fatigue FX (1.0 when fresh, lower
## when tired). Defensive default of 1.0 if the FX isn't up yet.
func _anim_speed() -> float:
	if _fatigue_fx != null:
		return float(_fatigue_fx.anim_speed)
	return 1.0


## Open the day and begin presenting its queue. Public so a future menu / the
## autoplay harness can (re)start a shift explicitly.
func start_shift() -> void:
	GameState.start_day()

	_queue = EventDeck.build_day_queue(GameState.day)
	_seen_ids.clear()
	_queued_ids.clear()
	_defer_counts.clear()
	_day_over = false
	_run_ended = false

	for card in _queue:
		_queued_ids[String(card.get("id", ""))] = true

	_update_day_label()
	_present_next()


func _update_day_label() -> void:
	var weekday: String = WEEKDAYS[(GameState.day - 1) % WEEKDAYS.size()]
	var level := clampi(GameState.fatigue_level(), 0, DAY_FRAME_BY_FATIGUE.size() - 1)
	var frame: String = DAY_FRAME_BY_FATIGUE[level]
	# Burnt-out variant drops the day number and takes only the weekday.
	if frame.count("%d") == 0:
		_day_label.text = frame % weekday
	else:
		_day_label.text = frame % [GameState.day, weekday]


# ---------------------------------------------------------------------------
# Presenting cards
# ---------------------------------------------------------------------------

## Pop the front of the queue and show it, or end the day if there's nothing
## left / the clock is spent.
func _present_next() -> void:
	if _day_over:
		return

	if GameState.time <= 0 or _queue.is_empty():
		_finish_day()
		return

	var card: Dictionary = _queue.pop_front()
	_queued_ids.erase(String(card.get("id", "")))

	var card_node: Node = CARD_SCENE.instantiate()
	_card_container.add_child(card_node)
	# CardContainer is a plain Control, so size the card to fill it ourselves.
	if card_node is Control:
		(card_node as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_current_card = card_node

	# Slow card animation when tired: lower anim_speed stretches durations.
	if card_node.has_method("set_anim_speed"):
		card_node.set_anim_speed(_anim_speed())

	card_node.setup(card)
	card_node.chosen.connect(_on_card_chosen.bind(card))
	card_node.deferred.connect(_on_card_deferred.bind(card))

	if card_node.has_method("play_enter"):
		card_node.play_enter()

	card_presented.emit(card_node)


# ---------------------------------------------------------------------------
# Intent handlers
# ---------------------------------------------------------------------------

func _on_card_chosen(response: Dictionary, card: Dictionary) -> void:
	if _advancing:
		return
	_advancing = true

	GameState.apply_response(response)
	_seen_ids[String(card.get("id", ""))] = true

	_maybe_enqueue_followup(response)

	await _dismiss_current()
	_advancing = false
	_present_next()


func _on_card_deferred(card: Dictionary) -> void:
	if _advancing:
		return
	_advancing = true

	var id := String(card.get("id", ""))
	_defer_counts[id] = int(_defer_counts.get(id, 0)) + 1

	if _defer_counts[id] <= MAX_DEFERS_PER_CARD:
		# Re-surface later: push to the back of the queue.
		_queue.push_back(card)
		_queued_ids[id] = true
	else:
		# Forced to the front; it must be answered next. (We still present a
		# fresh next card here; on its turn the player can't defer past the cap
		# because we re-front it.)
		_queue.push_front(card)
		_queued_ids[id] = true

	await _dismiss_current()
	_advancing = false
	_present_next()


## Insert a deferred-consequence follow-up a few slots in, if it exists and
## hasn't already been seen or queued this day.
func _maybe_enqueue_followup(response: Dictionary) -> void:
	var followup := String(response.get("followup", ""))
	if followup.is_empty():
		return
	if not EventDeck.has_card(followup):
		return
	if _seen_ids.has(followup) or _queued_ids.has(followup):
		return

	var card := EventDeck.get_card(followup)
	if card.is_empty():
		return

	var insert_at: int = mini(FOLLOWUP_INSERT_OFFSET, _queue.size())
	_queue.insert(insert_at, card)
	_queued_ids[followup] = true


## Animate the current card out (if it supports it) and free it.
func _dismiss_current() -> void:
	if _current_card == null:
		return
	var card := _current_card
	_current_card = null
	if card.has_method("play_exit"):
		await card.play_exit()
	card.queue_free()


# ---------------------------------------------------------------------------
# Day / run boundaries
# ---------------------------------------------------------------------------

## End the day, then run the between-day flow: announce the day, close it out in
## GameState, and either chain into the next day (via an optional interstitial)
## or, once the run is over, present the ending. This is the unified director
## that drives BOTH real play and headless autoplay through the same path.
func _finish_day() -> void:
	if _day_over:
		return
	_day_over = true

	var finished_day := GameState.day
	# end_day() advances the day index and, when past the final day, emits
	# run_ended() synchronously (caught by _on_run_ended, setting _run_ended).
	GameState.end_day()

	print("Day %d done. Energy %d/%d, Patience %d/%d." % [
		finished_day, GameState.energy, GameState.MAX_ENERGY,
		GameState.patience, GameState.MAX_PATIENCE])

	day_finished.emit(finished_day)

	await _run_post_day_flow(finished_day)


## The post-day transition. If the run has ended, present the ending and stop.
## Otherwise show the interstitial for the day just finished (if any), then open
## the next day's shift. Driven the same way in real play and autoplay.
func _run_post_day_flow(finished_day: int) -> void:
	if _run_ended:
		await _present_ending()
		return

	var interstitial := EventDeck.select_interstitial(finished_day)
	if not interstitial.is_empty():
		await _present_interstitial(interstitial)

	start_shift()


## Show the between-day Interstitial overlay and wait for the player (or the
## autoplayer) to advance it. The card chrome is hidden for the beat and
## restored after.
func _present_interstitial(interstitial: Dictionary) -> void:
	_set_chrome_visible(false)

	var node: Node = INTERSTITIAL_SCENE.instantiate()
	_overlay().add_child(node)
	node.setup(interstitial)

	interstitial_shown.emit(node)

	await node.finished
	node.queue_free()

	_set_chrome_visible(true)


## Present the Ending screen (the run is over) and wait for it to be dismissed.
## On dismissal we currently restart a fresh run; real MainMenu routing is PR-08.
func _present_ending() -> void:
	_set_chrome_visible(false)

	var ending := EventDeck.select_ending()
	var node: Node = ENDING_SCENE.instantiate()
	_overlay().add_child(node)
	node.setup(ending)

	ending_shown.emit(node)

	await node.dismissed
	node.queue_free()

	# TODO(PR-08): route to the real MainMenu here. For now, start a fresh run so
	# the screen has a graceful way forward instead of a dead end.
	_set_chrome_visible(true)
	GameState.new_run()
	start_shift()


## Lazily create (and return) the CanvasLayer the narrative overlays live on.
func _overlay() -> CanvasLayer:
	if _overlay_layer == null:
		_overlay_layer = CanvasLayer.new()
		_overlay_layer.name = "OverlayLayer"
		_overlay_layer.layer = OVERLAY_CANVAS_LAYER
		add_child(_overlay_layer)
	return _overlay_layer


## Show/hide the day chrome (the card column + HUD) so a narrative beat owns the
## screen cleanly. The fatigue FX is intentionally left running underneath.
func _set_chrome_visible(visible_now: bool) -> void:
	if _hud_layer != null:
		_hud_layer.visible = visible_now
	var margin := get_node_or_null("Margin")
	if margin is CanvasItem:
		(margin as CanvasItem).visible = visible_now


func _on_run_ended() -> void:
	_run_ended = true
	print("run ended")
