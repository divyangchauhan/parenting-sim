extends Node
## FatigueFX — the emotional-core post effect that makes the interface feel tired.
##
## DayShift hosts one of these. It subscribes to GameState.fatigue_level_changed
## and drives a full-screen canvas-item shader (shaders/fatigue.gdshader): as the
## player's combined Energy+Patience reserve drains, the world desaturates and
## dims/vignettes, and a shared `anim_speed` factor slows every transition tween.
##
## The numeric ramp is a PURE, unit-testable mapping (`params_for_level`) that
## never touches the scene tree, so tests can assert its shape without a display.
## The node itself owns a CanvasLayer + ColorRect overlay and tweens the shader
## uniforms between levels so the change is gradual, never a snap.
##
## Layering: the overlay sits on FX_CANVAS_LAYER (below the HUD's higher layer),
## so the MetersHUD stays full-colour and readable while the card world tires.
##
## No game logic lives here — it only reads fatigue and renders feel.

# ---------------------------------------------------------------------------
# Ramp tunables (named constants — the whole level->feel curve lives here)
# ---------------------------------------------------------------------------

## Desaturation amount (0 = full colour, 1 = grayscale) per fatigue level 0..3.
const DESATURATION_BY_LEVEL := [0.0, 0.25, 0.55, 0.85]

## Dim/vignette amount (0 = bright, 1 = heavily darkened) per fatigue level 0..3.
const DIM_BY_LEVEL := [0.0, 0.15, 0.4, 0.7]

## Animation speed multiplier per fatigue level: 1.0 = normal, < 1.0 = slowed.
## Other scenes scale their tween durations by 1 / anim_speed, so a lower value
## means everything literally moves slower when tired.
const ANIM_SPEED_BY_LEVEL := [1.0, 0.9, 0.75, 0.6]

## Seconds to tween the shader uniforms when the fatigue level changes. The
## crossfade itself is intentionally unhurried.
const TRANSITION_TIME := 0.8

## Canvas layer the overlay draws on. Kept low so a HUD on a higher layer (see
## DayShift) renders above the effect and stays readable.
const FX_CANVAS_LAYER := 1

const FATIGUE_SHADER := preload("res://shaders/fatigue.gdshader")

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## The fatigue level currently being rendered (0 fresh .. 3 burnt out).
var current_level: int = 0

## The current animation-speed multiplier other scenes scale tweens by.
var anim_speed: float = 1.0

var _canvas: CanvasLayer
var _rect: ColorRect
var _material: ShaderMaterial
var _tween: Tween

# ---------------------------------------------------------------------------
# Pure mapping (no scene-tree access — unit-testable)
# ---------------------------------------------------------------------------

## Map a fatigue level (clamped to 0..3) to its feel parameters. Pure: touches
## no nodes, so tests instantiate this script and call it directly. Returns
## { "desaturation": 0..1, "dim": 0..1, "anim_speed": float }.
## Level 0 is neutral (0, 0, 1.0); higher levels desaturate/dim more and slow down.
static func params_for_level(level: int) -> Dictionary:
	var i := clampi(level, 0, DESATURATION_BY_LEVEL.size() - 1)
	return {
		"desaturation": float(DESATURATION_BY_LEVEL[i]),
		"dim": float(DIM_BY_LEVEL[i]),
		"anim_speed": float(ANIM_SPEED_BY_LEVEL[i]),
	}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_overlay()

	# Resolve the GameState autoload dynamically. Referencing the autoload global
	# directly would make this script fail to compile under `--script` (where
	# autoloads aren't registered), which would break the pure mapping's tests.
	var game_state: Object = Engine.get_singleton("GameState") if Engine.has_singleton("GameState") else get_node_or_null("/root/GameState")
	if game_state == null:
		return

	# Reflect the current level immediately (apply instantly, no tween), then
	# react to future changes via the signal.
	current_level = int(game_state.fatigue_level())
	_apply_params(params_for_level(current_level), false)

	game_state.fatigue_level_changed.connect(_on_fatigue_level_changed)


## Create the CanvasLayer + screen-filling ColorRect that carry the shader. The
## rect ignores mouse input so it never eats card/button presses underneath.
func _build_overlay() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = FX_CANVAS_LAYER
	add_child(_canvas)

	_material = ShaderMaterial.new()
	_material.shader = FATIGUE_SHADER

	_rect = ColorRect.new()
	_rect.material = _material
	_rect.color = Color(1, 1, 1, 1)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(_rect)


# ---------------------------------------------------------------------------
# Reacting to fatigue
# ---------------------------------------------------------------------------

func _on_fatigue_level_changed(level: int) -> void:
	current_level = level
	_apply_params(params_for_level(level), true)


## Push the level's params into the shader. When `animated`, tween the shader
## uniforms over TRANSITION_TIME so the tiredness creeps in; otherwise snap them
## (used for the initial apply). `anim_speed` updates immediately either way so
## new tweens elsewhere pick up the slowdown without delay.
func _apply_params(params: Dictionary, animated: bool) -> void:
	anim_speed = float(params["anim_speed"])

	var target_desat := float(params["desaturation"])
	var target_dim := float(params["dim"])

	if _tween != null and _tween.is_valid():
		_tween.kill()

	if not animated or _material == null:
		if _material != null:
			_material.set_shader_parameter("desaturation", target_desat)
			_material.set_shader_parameter("dim", target_dim)
		return

	_tween = _rect.create_tween().set_parallel(true)
	_tween.tween_method(_set_desaturation, _current_desaturation(), target_desat, TRANSITION_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_set_dim, _current_dim(), target_dim, TRANSITION_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _current_desaturation() -> float:
	return float(_material.get_shader_parameter("desaturation"))


func _current_dim() -> float:
	return float(_material.get_shader_parameter("dim"))


func _set_desaturation(v: float) -> void:
	_material.set_shader_parameter("desaturation", v)


func _set_dim(v: float) -> void:
	_material.set_shader_parameter("dim", v)
