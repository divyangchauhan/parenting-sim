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
const PAUSE_MENU_SCENE := preload("res://scenes/PauseMenu.tscn")
const MAIN_MENU_SCENE := "res://scenes/MainMenu.tscn"

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

const PALETTE := preload("res://ui/palette.gd")

@onready var _day_label: Label = %DayLabel
@onready var _card_container: Control = %CardContainer
@onready var _ambient: ColorRect = %Ambient
@onready var _hud_layer: CanvasLayer = $HUDLayer
@onready var _pause_button: Button = %PauseButton

## The hosted post-effect node; also the source of the shared anim_speed factor.
var _fatigue_fx: Node = null

## The in-game pause overlay, lazily created (null until first opened / created).
var _pause_menu: CanvasLayer = null

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
	GameState.day_changed.connect(_on_day_changed)

	_setup_pause()

	start_shift()


## Wire the corner pause affordance and host the pause overlay. Under headless /
## AUTOPLAY there is no human to pause, so we hide the button and never create
## the overlay — pausing the tree there would stall the autoplayer / CI.
func _setup_pause() -> void:
	if _is_unattended():
		if _pause_button != null:
			_pause_button.visible = false
		return

	if _pause_button != null:
		_pause_button.pressed.connect(_on_pause_pressed)

	_pause_menu = PAUSE_MENU_SCENE.instantiate()
	_pause_menu.quit_to_menu.connect(_on_quit_to_menu)
	add_child(_pause_menu)


## True when no human is driving (headless display or AUTOPLAY): never auto-pause.
func _is_unattended() -> bool:
	return OS.get_environment("AUTOPLAY") == "1" or DisplayServer.get_name() == "headless"


func _on_pause_pressed() -> void:
	if _pause_menu != null and not _pause_menu.is_open():
		_pause_menu.open()


## Quit to Menu from the pause overlay: autosave the run, then route to MainMenu.
func _on_quit_to_menu() -> void:
	SaveManager.autosave()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


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
	_apply_ambient(GameState.day)

	# Start (or keep) the quiet domestic bed — room-tone + a faint ticking clock.
	# Idempotent: re-calling across days won't restart the already-playing bed.
	var am := _audio()
	if am != null:
		am.play_room_ambient()

	_present_next()


## Apply the per-day colour script: a faint full-screen ambient wash that drifts
## cooler/dimmer toward day 7. It sits UNDER the FatigueFX shader so the two layer
## rather than fight — this only sets the mood; FatigueFX drains the colour.
func _on_day_changed(day: int) -> void:
	_apply_ambient(day)


func _apply_ambient(day: int) -> void:
	if _ambient == null:
		return
	# The palette returns a near-white tint colour; we lay it as a faint, low-alpha
	# wash so the temperature shift reads without washing the screen out. Day 1 is
	# barely-warm; day 7 a cooler, slightly heavier dusk.
	var tint := PALETTE.ambient_for_day(day)
	_ambient.color = Color(tint.r, tint.g, tint.b, 0.10)


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
	# CardContainer is a VBoxContainer: the card fills the column width and sizes to
	# its own content so the prompt and responses always read together without
	# overflow, sitting near the top with calm breathing room below.
	if card_node is Control:
		(card_node as Control).size_flags_horizontal = Control.SIZE_FILL
		(card_node as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
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

	# Day-boundary autosave: persist the just-advanced run so Continue resumes the
	# next day. If the run just ended we instead erase the save (see _present_ending)
	# so a finished week never resumes into a broken, post-final-day state.
	if not _run_ended:
		SaveManager.autosave()

	# Day-boundary feel: a firmer haptic and a brief duck of the bed under the
	# transition, so the moment lands. Guarded; both are no-ops if unavailable.
	var haptics := _haptics()
	if haptics != null:
		haptics.medium()
	var am := _audio()
	if am != null:
		am.duck(8.0, 0.3)

	day_finished.emit(finished_day)

	await _run_post_day_flow(finished_day)

	if am != null:
		am.release_duck()


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

	# The between-day beat gets the sparse piano motif under a quieter bed.
	var am := _audio()
	if am != null:
		am.play_menu_music()

	var node: Node = INTERSTITIAL_SCENE.instantiate()
	_overlay().add_child(node)
	node.setup(interstitial)

	interstitial_shown.emit(node)

	await node.finished
	node.queue_free()

	# Hand the screen back to the day: stop the motif, let the bed resume.
	if am != null:
		am.stop_music()

	_set_chrome_visible(true)


## Present the Ending screen (the run is over) and wait for it to be dismissed.
## On dismissal we currently restart a fresh run; real MainMenu routing is PR-08.
func _present_ending() -> void:
	_set_chrome_visible(false)

	# The ending sits in the motif; the domestic bed fades away under it.
	var am := _audio()
	if am != null:
		am.stop_ambient(2.0)
		am.play_menu_music(2.0)

	var ending := EventDeck.select_ending()
	var node: Node = ENDING_SCENE.instantiate()
	_overlay().add_child(node)
	node.setup(ending)

	ending_shown.emit(node)

	await node.dismissed
	node.queue_free()

	# The run is complete: erase the save so Continue can't resume a finished week
	# into a broken (past-final-day) state, then route to the real MainMenu.
	SaveManager.erase_save()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


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


## Resolve the AudioManager autoload defensively (null in bare tests / headless
## without the autoload). All call sites guard on null.
func _audio() -> Object:
	return get_node_or_null("/root/AudioManager")


## Resolve the Haptics autoload defensively (null in bare tests).
func _haptics() -> Object:
	return get_node_or_null("/root/Haptics")
