extends Node
## Screenshot — dev-QA harness for visual verification (not shipped).
##
## Loads a target scene (with autoloads live, since this is a normal windowed run),
## lets it settle, captures the viewport to a PNG, and quits. Used to eyeball the
## art/theme passes without a human in the loop on every change.
##
## Usage:
##   SHOT_SCENE=res://scenes/MainMenu.tscn SHOT_OUT=/tmp/menu.png \
##     godot --path game tools/Screenshot.tscn
## Optional: SHOT_FRAMES (settle frames, default 12), SHOT_FATIGUE (0..3 to force a
## fatigue level for DayShift visuals).

func _ready() -> void:
	var scene_path := OS.get_environment("SHOT_SCENE")
	var out_path := OS.get_environment("SHOT_OUT")
	if scene_path.is_empty() or out_path.is_empty():
		push_error("Screenshot: set SHOT_SCENE and SHOT_OUT")
		get_tree().quit(1)
		return

	var frames := 12
	if not OS.get_environment("SHOT_FRAMES").is_empty():
		frames = int(OS.get_environment("SHOT_FRAMES"))

	# Most gameplay scenes assume a run has begun.
	GameState.new_run()

	var fatigue_env := OS.get_environment("SHOT_FATIGUE")
	if not fatigue_env.is_empty():
		# Drive reserves down to force a fatigue band for the FX screenshot.
		var lvl := int(fatigue_env)
		var burn: int = {1: 4, 2: 9, 3: 15}.get(lvl, 0)
		GameState.apply_response({"cost": {"energy": burn, "patience": burn}})

	var scene: Node = load(scene_path).instantiate()
	add_child(scene)

	# Interstitial / Ending are pure views fed by setup(); without it they render
	# empty. For a representative screenshot, feed them sample content here. This
	# only runs in the harness — the real flow always calls setup() itself.
	_seed_sample_content(scene_path, scene)

	for i in range(frames):
		await get_tree().process_frame

	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	if err == OK:
		print("SHOT saved: %s (%dx%d)" % [out_path, img.get_width(), img.get_height()])
	else:
		push_error("Screenshot: save failed (%d)" % err)
	get_tree().quit(0 if err == OK else 1)


## Feed sample content to pure-view scenes so the screenshot isn't blank. For
## Interstitial we flip on reduce_motion first so its reveal lands instantly;
## Ending's slow reveal is given extra settle frames by the caller (SHOT_FRAMES).
func _seed_sample_content(scene_path: String, scene: Node) -> void:
	if scene_path.ends_with("Interstitial.tscn") and scene.has_method("setup"):
		SaveManager.set_setting("reduce_motion", true)
		scene.setup({
			"id": "sample",
			"art": "a dark hallway",
			"lines": [
				"You stand in the hallway a moment,",
				"listening to them breathe.",
				"The dishes can wait.",
			],
		})
	elif scene_path.ends_with("Ending.tscn") and scene.has_method("setup"):
		SaveManager.set_setting("reduce_motion", true)
		scene.setup({
			"id": "sample",
			"title": "They'll remember the stories.",
			"lines": [
				"You didn't get to everything.",
				"You never do.",
				"But you were there for the parts that stay.",
			],
		})
