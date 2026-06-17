extends Node
## Haptics — Android vibration wrapper; no-op on other platforms. STUB (PR-10).

func light() -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(20)

func medium() -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(40)
