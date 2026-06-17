extends Node
## GameState — single source of truth for one run.
##
## Holds the visible resources (time / energy / patience) and the hidden states
## (connection, security, partnership, wellbeing, standing), the day index, and
## the run's narrative flags. Derives a fatigue level 0..3 from energy+patience.
##
## All tunable numbers live as named constants here (per ARCHITECTURE.md). Other
## systems react via signals rather than polling. This node is autoloaded.

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------

## Number of days in a run (one week).
const WEEK_LENGTH := 7

## Starting reserves for day 1. Time resets to DAY_START_TIME each day; energy
## and patience carry across days and are only partially topped up overnight.
const DAY_START_TIME := 12
const DAY_START_ENERGY := 10
const DAY_START_PATIENCE := 8

## Overnight partial refill applied at end_day(), capped at the day-start maxima.
const OVERNIGHT_ENERGY_REFILL := 6
const OVERNIGHT_PATIENCE_REFILL := 5

## Hard ceilings on the carried reserves.
const MAX_ENERGY := 10
const MAX_PATIENCE := 8

## Fatigue level cutoffs. Mapping uses the combined (energy + patience) reserve,
## which ranges 0..(MAX_ENERGY + MAX_PATIENCE) = 0..18. The thresholds are the
## *lower bound* of each fatigue level, ordered from fresh (level 0) to burnt
## out (level 3). A combined reserve >= FATIGUE_THRESHOLDS[i] qualifies for the
## freshest level whose cutoff it clears.
##   combined >= 12 -> level 0 (fresh)
##   combined >=  8 -> level 1 (tired)
##   combined >=  4 -> level 2 (frayed)
##   else           -> level 3 (burnt out)
const FATIGUE_THRESHOLDS := [12, 8, 4, 0]

## The hidden-state keys tracked silently across a run.
const HIDDEN_STATES := ["connection", "security", "partnership", "wellbeing", "standing"]

## Save serialization version (bumped when the save shape changes).
const SAVE_VERSION := 1

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var time: int = DAY_START_TIME
var energy: int = DAY_START_ENERGY
var patience: int = DAY_START_PATIENCE

## Hidden states: each key in HIDDEN_STATES -> int (starts at 0).
var states: Dictionary = {}

## Narrative flags used as a set: String -> true.
var flags: Dictionary = {}

## 1-based day index.
var day: int = 1

## Cached fatigue level (0..3); kept in sync so we only emit on change.
var _fatigue: int = 0

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal resources_changed(time: int, energy: int, patience: int)
signal state_changed(states: Dictionary)
signal day_changed(day: int)
signal fatigue_level_changed(level: int)
signal run_ended()

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

## Reset everything to the start of a fresh run (day 1) and announce it.
func new_run() -> void:
	day = 1
	time = DAY_START_TIME
	energy = DAY_START_ENERGY
	patience = DAY_START_PATIENCE
	states = {}
	for key in HIDDEN_STATES:
		states[key] = 0
	flags = {}
	_fatigue = _compute_fatigue()
	resources_changed.emit(time, energy, patience)
	state_changed.emit(states)
	day_changed.emit(day)
	fatigue_level_changed.emit(_fatigue)

## (Re)start the current day: reset the clock to the full day-start time.
## Energy and patience are untouched here (they carry / refill via end_day).
func start_day() -> void:
	time = DAY_START_TIME
	resources_changed.emit(time, energy, patience)
	day_changed.emit(day)

## Close out the day: apply the capped overnight refills, advance the day index,
## and either end the run (past the final day) or announce the new day.
func end_day() -> void:
	energy = mini(energy + OVERNIGHT_ENERGY_REFILL, MAX_ENERGY)
	patience = mini(patience + OVERNIGHT_PATIENCE_REFILL, MAX_PATIENCE)
	_refresh_fatigue()
	resources_changed.emit(time, energy, patience)
	day += 1
	if day > WEEK_LENGTH:
		run_ended.emit()
	else:
		day_changed.emit(day)

# ---------------------------------------------------------------------------
# Affordability & gating
# ---------------------------------------------------------------------------

## True if the current reserves can cover every cost present in `cost`.
## `cost` may contain any of: time, energy, patience (missing keys cost 0).
func can_afford(cost: Dictionary) -> bool:
	if time < int(cost.get("time", 0)):
		return false
	if energy < int(cost.get("energy", 0)):
		return false
	if patience < int(cost.get("patience", 0)):
		return false
	return true

## True if a response is *locked* because a reserve sits below a required
## minimum. `gated_by` may contain energy_min and/or patience_min.
func is_response_gated(gated_by: Dictionary) -> bool:
	if energy < int(gated_by.get("energy_min", 0)):
		return true
	if patience < int(gated_by.get("patience_min", 0)):
		return true
	return false

# ---------------------------------------------------------------------------
# Applying a response
# ---------------------------------------------------------------------------

## Resolve a chosen response: spend its cost (clamped at 0), apply its hidden-
## state effects, and record any flags it sets. Recomputes fatigue and emits the
## relevant change signals (fatigue only when its level actually changes).
##
## `response` shape (see content/schema.md):
##   cost:       { time:int, energy:int, patience:int }   (optional keys)
##   effects:    { <hidden_state>: int_delta, ... }
##   sets_flags: Array[String]
func apply_response(response: Dictionary) -> void:
	var cost: Dictionary = response.get("cost", {})
	time = maxi(time - int(cost.get("time", 0)), 0)
	energy = maxi(energy - int(cost.get("energy", 0)), 0)
	patience = maxi(patience - int(cost.get("patience", 0)), 0)

	var effects: Dictionary = response.get("effects", {})
	for key in effects:
		if states.has(key):
			states[key] += int(effects[key])

	for flag in response.get("sets_flags", []):
		flags[String(flag)] = true

	resources_changed.emit(time, energy, patience)
	state_changed.emit(states)
	_refresh_fatigue()

# ---------------------------------------------------------------------------
# Fatigue
# ---------------------------------------------------------------------------

## Current fatigue level (0 fresh .. 3 burnt out) derived from energy+patience.
func fatigue_level() -> int:
	return _fatigue

## Compute the fatigue level from the combined reserve via FATIGUE_THRESHOLDS.
func _compute_fatigue() -> int:
	var combined := energy + patience
	for level in range(FATIGUE_THRESHOLDS.size()):
		if combined >= FATIGUE_THRESHOLDS[level]:
			return level
	return FATIGUE_THRESHOLDS.size() - 1

## Recompute fatigue and emit fatigue_level_changed only if it moved.
func _refresh_fatigue() -> void:
	var level := _compute_fatigue()
	if level != _fatigue:
		_fatigue = level
		fatigue_level_changed.emit(_fatigue)

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------

## Record a narrative flag.
func set_flag(flag: String) -> void:
	flags[flag] = true

## True if a narrative flag has been set this run.
func has_flag(flag: String) -> bool:
	return flags.has(flag)

# ---------------------------------------------------------------------------
# Serialization (SaveManager)
# ---------------------------------------------------------------------------

## Full snapshot of the run for saving. Dictionaries are duplicated so callers
## can't mutate live state through the returned copy.
func to_dict() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"time": time,
		"energy": energy,
		"patience": patience,
		"states": states.duplicate(),
		"flags": flags.duplicate(),
		"day": day,
	}

## Restore a run from a saved snapshot and announce the restored state. Missing
## keys fall back to sensible defaults so partial / older saves still load.
func from_dict(d: Dictionary) -> void:
	time = int(d.get("time", DAY_START_TIME))
	energy = int(d.get("energy", DAY_START_ENERGY))
	patience = int(d.get("patience", DAY_START_PATIENCE))
	day = int(d.get("day", 1))

	states = {}
	var saved_states: Dictionary = d.get("states", {})
	for key in HIDDEN_STATES:
		states[key] = int(saved_states.get(key, 0))

	flags = {}
	var saved_flags: Dictionary = d.get("flags", {})
	for flag in saved_flags:
		flags[String(flag)] = true

	_fatigue = _compute_fatigue()
	resources_changed.emit(time, energy, patience)
	state_changed.emit(states)
	day_changed.emit(day)
	fatigue_level_changed.emit(_fatigue)
