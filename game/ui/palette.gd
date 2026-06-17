extends RefCounted
class_name Palette
## Palette — the game's design tokens. A static, autoload-free token bank.
##
## "Enough" wants a muted, late-evening DOMESTIC palette: warm paper and ink
## neutrals, with restrained per-source accents (child / partner / work / self)
## that are gentle and distinguishable but never loud. Everything here is
## intentionally desaturated and low-contrast — the warmth lives in the hues,
## not in saturation.
##
## A PER-DAY COLOR SCRIPT (ambient_for_day) gives each day 1..7 a faint ambient
## tint + brightness that drifts subtly cooler and dimmer toward day 7 — the week
## wearing on you. It is applied as a whole-screen wash UNDER the FatigueFX
## shader, so it is kept deliberately subtle: it sets the mood, FatigueFX drains
## the colour. The two must not fight, hence the gentle deltas.
##
## All members are static — call as Palette.INK, Palette.source_accent("child"),
## Palette.ambient_for_day(3). Nothing here touches the scene tree, so it is
## trivially usable from theme-building tools and tests alike.

# ---------------------------------------------------------------------------
# Core neutrals — warm paper & ink (the domestic ground)
# ---------------------------------------------------------------------------

## The darkest ground — a warm near-black for menu / interstitial / ending fields.
const GROUND := Color(0.086, 0.082, 0.094, 1.0)

## A slightly lifted ground, for panels/overlays sitting on GROUND.
const GROUND_RAISED := Color(0.129, 0.122, 0.137, 1.0)

## Warm "paper" — the card surface. A soft, aged off-white with a touch of cream.
const PAPER := Color(0.945, 0.925, 0.890, 1.0)

## A faintly warmer/darker paper for pressed/secondary surfaces.
const PAPER_SHADE := Color(0.898, 0.875, 0.835, 1.0)

## Ink — primary text on paper. A soft warm charcoal, never pure black.
const INK := Color(0.180, 0.165, 0.157, 1.0)

## Muted ink — secondary text / captions on paper.
const INK_MUTED := Color(0.392, 0.373, 0.353, 1.0)

## Faint ink — hairlines, dividers, disabled text on paper.
const INK_FAINT := Color(0.604, 0.580, 0.553, 1.0)

## Paper-coloured text used on the dark ground (titles, interstitial/ending body).
const PAPER_TEXT := Color(0.918, 0.898, 0.863, 1.0)

## Muted paper text on dark ground (subtitles, hints, the quiet "tap to continue").
const PAPER_TEXT_MUTED := Color(0.604, 0.588, 0.561, 1.0)

# ---------------------------------------------------------------------------
# Restrained accents (used sparingly — never as fills, mostly as chips/edges)
# ---------------------------------------------------------------------------

## The one warm accent — a dimmed terracotta/amber, for gentle emphasis.
const ACCENT_WARM := Color(0.776, 0.518, 0.404, 1.0)

## A cool counter-accent — dusty slate-blue, for curt/cooler moments.
const ACCENT_COOL := Color(0.451, 0.510, 0.561, 1.0)

# ---------------------------------------------------------------------------
# Per-source accents (child / partner / work / self) — gentle, distinguishable
# ---------------------------------------------------------------------------
#
# Each is a low-saturation hue that reads at a glance without shouting. Used for
# the source chip on a card (a soft filled pill) and, faintly, the card's edge.

## Child — a warm, tender clay/rose.
const SOURCE_CHILD := Color(0.804, 0.486, 0.408, 1.0)

## Partner — a muted sage green (quiet, grounded).
const SOURCE_PARTNER := Color(0.482, 0.561, 0.471, 1.0)

## Work — a desaturated indigo/slate (cooler, obligational).
const SOURCE_WORK := Color(0.435, 0.475, 0.596, 1.0)

## Self — a dusty mauve/plum (interior, quiet).
const SOURCE_SELF := Color(0.580, 0.494, 0.580, 1.0)

## Fallback chip colour for an unknown source.
const SOURCE_DEFAULT := Color(0.490, 0.471, 0.451, 1.0)

# ---------------------------------------------------------------------------
# Resource-meter hues (restrained, each its own quiet temperature)
# ---------------------------------------------------------------------------

## Energy — a warm honey/amber. Physical reserve.
const METER_ENERGY := Color(0.792, 0.624, 0.392, 1.0)

## Patience — a calm muted teal/green. Emotional reserve.
const METER_PATIENCE := Color(0.490, 0.624, 0.580, 1.0)

## The unfilled track behind a meter (on the dark HUD ground).
const METER_TRACK := Color(0.243, 0.231, 0.255, 1.0)

# ---------------------------------------------------------------------------
# Per-source accent lookup
# ---------------------------------------------------------------------------

## The accent colour for a card source ("child" | "partner" | "work" | "self").
## Unknown sources fall back to a neutral grey.
static func source_accent(source: String) -> Color:
	match source:
		"child":
			return SOURCE_CHILD
		"partner":
			return SOURCE_PARTNER
		"work":
			return SOURCE_WORK
		"self":
			return SOURCE_SELF
		_:
			return SOURCE_DEFAULT


## A faint, paper-tinted version of a source accent for the card's chip text
## ground / soft fill — keeps the chip legible and quiet, not garish.
static func source_chip_fill(source: String) -> Color:
	var base := source_accent(source)
	# Pull strongly toward paper so the chip is a soft tinted pill, not a block.
	return base.lerp(PAPER, 0.62)


# ---------------------------------------------------------------------------
# Per-day colour script — the ambient wash under everything
# ---------------------------------------------------------------------------
#
# Each day gets a faint full-screen tint + a brightness scalar. Early days are
# warm and bright (a fresh morning); the week drifts cooler and dimmer toward
# day 7. Kept SUBTLE on purpose: this is a whisper of mood that layers under the
# FatigueFX desaturation, so the two read together rather than cancel out.

## Per-day ambient tint hues (day 1..7). Warm cream -> cool dusk. Index = day-1.
const _AMBIENT_TINT := [
	Color(1.000, 0.980, 0.949, 1.0),  # Day 1 — warm morning cream
	Color(0.992, 0.969, 0.937, 1.0),  # Day 2
	Color(0.973, 0.961, 0.945, 1.0),  # Day 3 — neutral
	Color(0.949, 0.953, 0.961, 1.0),  # Day 4 — cooling
	Color(0.925, 0.941, 0.969, 1.0),  # Day 5
	Color(0.906, 0.929, 0.965, 1.0),  # Day 6 — dusk blue
	Color(0.886, 0.914, 0.961, 1.0),  # Day 7 — cold, late
]

## Per-day brightness scalar (day 1..7). Drifts gently dimmer as the week wears.
const _AMBIENT_BRIGHTNESS := [1.00, 0.985, 0.97, 0.955, 0.94, 0.925, 0.91]


## The ambient *modulate* colour for a given day (1-based). Multiply a screen-
## filling ColorRect's modulate by this (it is a near-white tint, so the effect
## is a faint temperature shift + dimming, never a colour cast). Days outside
## 1..7 clamp to the ends.
static func ambient_for_day(day: int) -> Color:
	var i := clampi(day - 1, 0, _AMBIENT_TINT.size() - 1)
	var tint: Color = _AMBIENT_TINT[i]
	var b: float = _AMBIENT_BRIGHTNESS[i]
	return Color(tint.r * b, tint.g * b, tint.b * b, 1.0)
