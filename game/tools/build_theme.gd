extends SceneTree
## build_theme.gd — dev tool. Builds ui/theme.tres from code so the StyleBoxes,
## fonts, colours and type-variations stay in one readable place. Run headless:
##   godot --headless --path game --script tools/build_theme.gd
## Not shipped; the produced theme.tres is what the game actually loads.
##
## Typography: base sizes are authored here but they are deliberately the
## ThemeDB.fallback_font_size's siblings — SaveManager scales accessibility text
## via ThemeDB.fallback_font_size, and any Control WITHOUT an explicit theme font
## size inherits that. So we leave the bulk of body text unset (inherits the
## scaled fallback) and only set sizes where hierarchy demands (titles, chips).
## Roles that must scale with text_scale read their size from a small ratio over
## SaveManager.BASE_FONT_SIZE so "Large" text grows everything proportionally.

const FONT_LORA := preload("res://ui/fonts/Lora.ttf")
const FONT_INTER := preload("res://ui/fonts/Inter.ttf")

const Pal := preload("res://ui/palette.gd")

## SaveManager.BASE_FONT_SIZE — kept in sync; the multiplicand text_scale uses.
const BASE := 16

# Type scale (ratios of BASE) — applied as concrete sizes where hierarchy needs
# it. Body text is left UNSET so it inherits ThemeDB.fallback_font_size (which
# SaveManager scales). These fixed sizes are the "art" sizes; text_scale still
# moves the inherited body, and we keep titles comfortably larger.
const SIZE_TITLE := 52       # MainMenu "Enough"
const SIZE_TITLE_SUB := 17   # quiet subtitle
const SIZE_PROMPT := 25      # card prompt (serif)
const SIZE_RESPONSE := 18    # response button text (serif, readable)
const SIZE_HUD_LABEL := 13   # "Energy" / "Patience" caps labels
const SIZE_HUD_VALUE := 17   # the numeric readouts
const SIZE_CHIP := 12        # source tag chip
const SIZE_DAYFRAME := 16    # day-open frame line
const SIZE_BODY := 18        # interstitial / ending body lines (serif)
const SIZE_ENDING_TITLE := 34
const SIZE_BUTTON := 18      # menu / settings buttons (sans)
const SIZE_HEADING := 28     # settings heading (serif)


func _init() -> void:
	var theme := Theme.new()

	var serif := _font_variation(FONT_LORA, 500)
	var serif_semi := _font_variation(FONT_LORA, 600)
	var sans := _font_variation(FONT_INTER, 450)
	var sans_med := _font_variation(FONT_INTER, 550)
	var sans_caps := _font_variation(FONT_INTER, 650)

	# Default font for the whole theme: humanist sans for chrome/labels/buttons.
	theme.default_font = sans
	theme.default_font_size = BASE

	_setup_label(theme, sans)
	_setup_button(theme, sans_med)
	_setup_panel(theme)
	_setup_progress(theme)
	_setup_slider(theme)
	_setup_checkbutton(theme, sans)
	_setup_optionbutton(theme, sans_med)
	_setup_dialogs(theme)
	_setup_line_edit(theme)

	# --- Type-variation roles (referenced by the scenes) ---
	_variation_label(theme, "Title", serif_semi, SIZE_TITLE, Pal.PAPER_TEXT)
	_variation_label(theme, "Subtitle", sans, SIZE_TITLE_SUB, Pal.PAPER_TEXT_MUTED)
	_variation_label(theme, "Heading", serif_semi, SIZE_HEADING, Pal.PAPER_TEXT)
	_variation_label(theme, "Prompt", serif, SIZE_PROMPT, Pal.INK)
	_variation_label(theme, "DayFrame", sans, SIZE_DAYFRAME, Pal.PAPER_TEXT_MUTED)
	_variation_label(theme, "InterstitialLine", serif, SIZE_BODY, Pal.PAPER_TEXT)
	_variation_label(theme, "EndingTitle", serif_semi, SIZE_ENDING_TITLE, Pal.PAPER_TEXT)
	_variation_label(theme, "EndingLine", serif, SIZE_BODY, Pal.PAPER_TEXT)
	_variation_label(theme, "ContinueHint", sans, SIZE_TITLE_SUB, Pal.PAPER_TEXT_MUTED)

	# HUD labels & values (sans).
	_variation_label(theme, "HudLabel", sans_caps, SIZE_HUD_LABEL, Pal.PAPER_TEXT_MUTED)
	_variation_label(theme, "HudValue", sans_med, SIZE_HUD_VALUE, Pal.PAPER_TEXT)

	# Source chips, one per source (filled soft pill, tinted text).
	for source in ["child", "partner", "work", "self"]:
		_variation_source_chip(theme, source, sans_caps)

	# Response buttons by tone (serif body, subtle tonal differentiation).
	_variation_response_button(theme, "warm", serif)
	_variation_response_button(theme, "neutral", serif)
	_variation_response_button(theme, "curt", serif)

	# Quiet defer affordance (flat, low-key text button).
	_variation_defer_button(theme, sans)

	# HUD background band (flat, no corners, faint bottom hairline).
	_variation_hud_panel(theme)

	# Menu / primary buttons get a softly elevated variation.
	_variation_menu_button(theme, sans_med)

	var err := ResourceSaver.save(theme, "res://ui/theme.tres")
	if err != OK:
		push_error("build_theme: save failed %d" % err)
		quit(1)
		return
	print("build_theme: wrote res://ui/theme.tres")
	quit(0)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _font_variation(base: FontFile, weight: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": weight}
	return fv


func _flat(bg: Color, radius: int, content: Array, border_w: int = 0, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = content[0]
	sb.content_margin_top = content[1]
	sb.content_margin_right = content[2]
	sb.content_margin_bottom = content[3]
	if border_w > 0:
		sb.border_width_left = border_w
		sb.border_width_top = border_w
		sb.border_width_right = border_w
		sb.border_width_bottom = border_w
		sb.border_color = border
	return sb


func _empty() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


# ---------------------------------------------------------------------------
# Base classes
# ---------------------------------------------------------------------------

## Default Label = chrome text on dark ground.
func _setup_label(theme: Theme, sans: FontVariation) -> void:
	theme.set_font("font", "Label", sans)
	theme.set_color("font_color", "Label", Pal.PAPER_TEXT)
	theme.set_constant("line_spacing", "Label", 4)


func _setup_button(theme: Theme, sans_med: FontVariation) -> void:
	theme.set_font("font", "Button", sans_med)
	theme.set_font_size("font_size", "Button", SIZE_BUTTON)
	theme.set_color("font_color", "Button", Pal.PAPER_TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Pal.PAPER_TEXT_MUTED)
	theme.set_color("font_disabled_color", "Button", Pal.INK_FAINT)
	theme.set_color("font_focus_color", "Button", Pal.PAPER_TEXT)

	var normal := _flat(Pal.GROUND_RAISED, 10, [18, 12, 18, 12], 1, Color(0.32, 0.31, 0.34, 1.0))
	var hover := _flat(Color(0.176, 0.169, 0.184, 1.0), 10, [18, 12, 18, 12], 1, Color(0.40, 0.38, 0.42, 1.0))
	var pressed := _flat(Color(0.110, 0.106, 0.122, 1.0), 10, [18, 12, 18, 12], 1, Color(0.30, 0.29, 0.33, 1.0))
	var disabled := _flat(Color(0.106, 0.102, 0.114, 1.0), 10, [18, 12, 18, 12], 1, Color(0.20, 0.19, 0.22, 1.0))
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", _empty())


func _setup_panel(theme: Theme) -> void:
	# Generic Panel = a quiet raised surface on the dark ground.
	theme.set_stylebox("panel", "Panel", _flat(Pal.GROUND_RAISED, 12, [0, 0, 0, 0]))
	# PanelContainer (the Card base) = warm paper with a soft border + padding.
	var paper := _flat(Pal.PAPER, 18, [22, 22, 22, 22], 1, Color(0.0, 0.0, 0.0, 0.06))
	paper.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	paper.shadow_size = 14
	paper.shadow_offset = Vector2(0, 6)
	theme.set_stylebox("panel", "PanelContainer", paper)


func _setup_progress(theme: Theme) -> void:
	# Generic ProgressBar; per-meter fill is set on the variations below.
	theme.set_stylebox("background", "ProgressBar", _flat(Pal.METER_TRACK, 6, [0, 0, 0, 0]))
	theme.set_stylebox("fill", "ProgressBar", _flat(Pal.METER_ENERGY, 6, [0, 0, 0, 0]))
	theme.set_color("font_color", "ProgressBar", Pal.PAPER_TEXT)
	theme.set_font_size("font_size", "ProgressBar", SIZE_HUD_LABEL)

	# Energy / Patience meter variations (own hues).
	var energy := _flat(Pal.METER_ENERGY, 6, [0, 0, 0, 0])
	theme.set_type_variation("EnergyBar", "ProgressBar")
	theme.set_stylebox("background", "EnergyBar", _flat(Pal.METER_TRACK, 6, [0, 0, 0, 0]))
	theme.set_stylebox("fill", "EnergyBar", energy)

	var patience := _flat(Pal.METER_PATIENCE, 6, [0, 0, 0, 0])
	theme.set_type_variation("PatienceBar", "ProgressBar")
	theme.set_stylebox("background", "PatienceBar", _flat(Pal.METER_TRACK, 6, [0, 0, 0, 0]))
	theme.set_stylebox("fill", "PatienceBar", patience)


func _setup_slider(theme: Theme) -> void:
	var track := _flat(Pal.METER_TRACK, 4, [0, 0, 0, 0])
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	theme.set_stylebox("slider", "HSlider", track)
	var grabbed := _flat(Pal.ACCENT_WARM, 4, [0, 0, 0, 0])
	grabbed.content_margin_top = 6
	grabbed.content_margin_bottom = 6
	theme.set_stylebox("grabber_area", "HSlider", grabbed)
	theme.set_stylebox("grabber_area_highlight", "HSlider", grabbed)
	var grabber := _flat(Pal.PAPER_TEXT, 10, [0, 0, 0, 0])
	theme.set_stylebox("grabber", "HSlider", grabber)


func _setup_checkbutton(theme: Theme, sans: FontVariation) -> void:
	theme.set_font("font", "CheckButton", sans)
	theme.set_font_size("font_size", "CheckButton", SIZE_BUTTON)
	theme.set_color("font_color", "CheckButton", Pal.PAPER_TEXT)
	theme.set_color("font_hover_color", "CheckButton", Color.WHITE)
	theme.set_stylebox("normal", "CheckButton", _empty())
	theme.set_stylebox("hover", "CheckButton", _empty())
	theme.set_stylebox("pressed", "CheckButton", _empty())
	theme.set_stylebox("focus", "CheckButton", _empty())


func _setup_optionbutton(theme: Theme, sans_med: FontVariation) -> void:
	theme.set_font("font", "OptionButton", sans_med)
	theme.set_font_size("font_size", "OptionButton", SIZE_BUTTON)
	theme.set_color("font_color", "OptionButton", Pal.PAPER_TEXT)
	theme.set_color("font_hover_color", "OptionButton", Color.WHITE)
	var normal := _flat(Pal.GROUND_RAISED, 10, [16, 10, 16, 10], 1, Color(0.32, 0.31, 0.34, 1.0))
	var hover := _flat(Color(0.176, 0.169, 0.184, 1.0), 10, [16, 10, 16, 10], 1, Color(0.40, 0.38, 0.42, 1.0))
	theme.set_stylebox("normal", "OptionButton", normal)
	theme.set_stylebox("hover", "OptionButton", hover)
	theme.set_stylebox("pressed", "OptionButton", normal)
	theme.set_stylebox("focus", "OptionButton", _empty())
	# The popup menu it spawns.
	theme.set_stylebox("panel", "PopupMenu", _flat(Pal.GROUND_RAISED, 10, [8, 8, 8, 8], 1, Color(0.32, 0.31, 0.34, 1.0)))
	theme.set_color("font_color", "PopupMenu", Pal.PAPER_TEXT)


func _setup_dialogs(theme: Theme) -> void:
	# AcceptDialog / ConfirmationDialog share the same window panel.
	var panel := _flat(Pal.GROUND_RAISED, 14, [20, 20, 20, 20], 1, Color(0.34, 0.33, 0.36, 1.0))
	panel.shadow_color = Color(0, 0, 0, 0.4)
	panel.shadow_size = 18
	theme.set_stylebox("panel", "AcceptDialog", panel)
	theme.set_color("title_color", "AcceptDialog", Pal.PAPER_TEXT)
	theme.set_constant("title_height", "AcceptDialog", 34)


func _setup_line_edit(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", _flat(Pal.GROUND, 8, [12, 8, 12, 8], 1, Color(0.32, 0.31, 0.34, 1.0)))
	theme.set_color("font_color", "LineEdit", Pal.PAPER_TEXT)


# ---------------------------------------------------------------------------
# Type variations
# ---------------------------------------------------------------------------

func _variation_label(theme: Theme, name: String, font: FontVariation, size: int, color: Color) -> void:
	theme.set_type_variation(name, "Label")
	theme.set_font("font", name, font)
	theme.set_font_size("font_size", name, size)
	theme.set_color("font_color", name, color)
	theme.set_constant("line_spacing", name, 6)


func _variation_source_chip(theme: Theme, source: String, font: FontVariation) -> void:
	var name := "SourceTag_%s" % source
	theme.set_type_variation(name, "Label")
	theme.set_font("font", name, font)
	theme.set_font_size("font_size", name, SIZE_CHIP)
	var accent: Color = Pal.source_accent(source)
	# Darken the accent for legible chip text on the soft fill.
	theme.set_color("font_color", name, accent.darkened(0.35))
	var fill := _flat(Pal.source_chip_fill(source), 6, [10, 4, 10, 4], 1, accent.lerp(Pal.PAPER, 0.35))
	theme.set_stylebox("normal", name, fill)


func _variation_response_button(theme: Theme, tone: String, serif: FontVariation) -> void:
	var name := "ResponseButton_%s" % tone
	theme.set_type_variation(name, "Button")
	theme.set_font("font", name, serif)
	theme.set_font_size("font_size", name, SIZE_RESPONSE)

	# Tonal differentiation — SUBTLE. All sit on paper; warmth/coolness/flatness
	# is conveyed by tiny shifts in fill warmth, border, and rounding.
	var fill := Pal.PAPER_SHADE
	var border := Color(0.0, 0.0, 0.0, 0.10)
	var radius := 12
	var text_col := Pal.INK
	match tone:
		"warm":
			# A touch warmer + softer (rounder), faint warm edge.
			fill = Color(0.949, 0.910, 0.851, 1.0)
			border = Pal.ACCENT_WARM.lerp(Pal.PAPER, 0.45)
			radius = 14
		"curt":
			# Flatter + cooler — squarer corners, cool faint edge.
			fill = Color(0.906, 0.902, 0.898, 1.0)
			border = Pal.ACCENT_COOL.lerp(Pal.PAPER, 0.5)
			radius = 8
			text_col = Pal.INK_MUTED
		_:
			# neutral — plain warm paper.
			fill = Pal.PAPER_SHADE

	var normal := _flat(fill, radius, [18, 14, 18, 14], 1, border)
	var hover := _flat(fill.darkened(0.04), radius, [18, 14, 18, 14], 1, border.darkened(0.1))
	var pressed := _flat(fill.darkened(0.08), radius, [18, 14, 18, 14], 1, border)
	# Disabled = clearly but quietly unavailable: very low-contrast, faint text.
	var disabled := _flat(Color(0.910, 0.898, 0.878, 0.5), radius, [18, 14, 18, 14], 1, Color(0, 0, 0, 0.05))

	theme.set_stylebox("normal", name, normal)
	theme.set_stylebox("hover", name, hover)
	theme.set_stylebox("pressed", name, pressed)
	theme.set_stylebox("disabled", name, disabled)
	theme.set_stylebox("focus", name, _empty())
	theme.set_color("font_color", name, text_col)
	theme.set_color("font_hover_color", name, text_col.darkened(0.1))
	theme.set_color("font_pressed_color", name, text_col)
	theme.set_color("font_disabled_color", name, Pal.INK_FAINT)


func _variation_defer_button(theme: Theme, sans: FontVariation) -> void:
	var name := "DeferButton"
	theme.set_type_variation(name, "Button")
	theme.set_font("font", name, sans)
	theme.set_font_size("font_size", name, SIZE_RESPONSE - 2)
	# Flat text affordance: no fill, faint ink, sits quietly under the responses.
	theme.set_stylebox("normal", name, _flat(Color.TRANSPARENT, 8, [10, 8, 10, 8]))
	theme.set_stylebox("hover", name, _flat(Color(0.0, 0.0, 0.0, 0.04), 8, [10, 8, 10, 8]))
	theme.set_stylebox("pressed", name, _flat(Color(0.0, 0.0, 0.0, 0.06), 8, [10, 8, 10, 8]))
	theme.set_stylebox("disabled", name, _empty())
	theme.set_stylebox("focus", name, _empty())
	theme.set_color("font_color", name, Pal.INK_MUTED)
	theme.set_color("font_hover_color", name, Pal.INK)
	theme.set_color("font_pressed_color", name, Pal.INK_MUTED)


func _variation_hud_panel(theme: Theme) -> void:
	var name := "HudPanel"
	theme.set_type_variation(name, "Panel")
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.110, 0.106, 0.122, 0.92)
	sb.border_width_bottom = 1
	sb.border_color = Color(1.0, 1.0, 1.0, 0.06)
	theme.set_stylebox("panel", name, sb)


func _variation_menu_button(theme: Theme, sans_med: FontVariation) -> void:
	var name := "MenuAction"
	theme.set_type_variation(name, "Button")
	theme.set_font("font", name, sans_med)
	theme.set_font_size("font_size", name, SIZE_BUTTON + 2)
	var normal := _flat(Pal.GROUND_RAISED, 12, [20, 16, 20, 16], 1, Color(0.30, 0.29, 0.33, 1.0))
	var hover := _flat(Color(0.180, 0.173, 0.192, 1.0), 12, [20, 16, 20, 16], 1, Color(0.42, 0.40, 0.45, 1.0))
	var pressed := _flat(Color(0.110, 0.106, 0.122, 1.0), 12, [20, 16, 20, 16], 1, Color(0.30, 0.29, 0.33, 1.0))
	var disabled := _flat(Color(0.106, 0.102, 0.114, 1.0), 12, [20, 16, 20, 16], 1, Color(0.18, 0.17, 0.20, 1.0))
	theme.set_stylebox("normal", name, normal)
	theme.set_stylebox("hover", name, hover)
	theme.set_stylebox("pressed", name, pressed)
	theme.set_stylebox("disabled", name, disabled)
	theme.set_stylebox("focus", name, _empty())
	theme.set_color("font_color", name, Pal.PAPER_TEXT)
	theme.set_color("font_hover_color", name, Color.WHITE)
	theme.set_color("font_disabled_color", name, Pal.INK_FAINT)
