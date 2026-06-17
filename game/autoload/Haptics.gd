extends Node
## Haptics — Android vibration wrapper; no-op on other platforms. STUB (PR-10).
##
## Respects the player's haptics setting: SaveManager pushes the enabled flag in
## on _ready and whenever it changes (see SaveManager._apply_haptics).

## When false, all vibration calls are suppressed. Driven by the haptics setting.
var enabled: bool = true


## Setter used by SaveManager to honor the haptics setting.
func set_enabled(value: bool) -> void:
	enabled = value


func light() -> void:
	if enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(20)


func medium() -> void:
	if enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(40)
