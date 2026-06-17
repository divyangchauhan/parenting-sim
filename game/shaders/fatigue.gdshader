shader_type canvas_item;
// Full-screen "tiredness" post effect for Enough.
//
// Drawn by a screen-filling ColorRect (FatigueFX) above the card UI but below
// the HUD. It samples the already-rendered frame via a screen texture, then:
//   - desaturates it toward luminance (uniform `desaturation`, 0..1)
//   - darkens it overall and adds a soft vignette (uniform `dim`, 0..1)
// Both amounts are tweened by FatigueFX between fatigue levels so the change is
// gradual, never a snap. At desaturation = dim = 0 the frame is untouched.

// 0 = full colour, 1 = fully grayscale.
uniform float desaturation : hint_range(0.0, 1.0) = 0.0;
// 0 = full brightness, 1 = heavily dimmed + vignetted.
uniform float dim : hint_range(0.0, 1.0) = 0.0;

// The already-rendered frame, sampled so we can post-process it.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

// Rec. 709 luma weights for perceptual desaturation.
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

// How strong the vignette darkening gets at dim = 1, and how far from centre it
// starts biting. Kept as named constants so the ramp lives in one place.
const float VIGNETTE_STRENGTH = 0.6;
const float VIGNETTE_INNER = 0.25;
const float VIGNETTE_OUTER = 0.85;
// Flat overall darkening at dim = 1 (applied everywhere, not just edges).
const float MAX_FLAT_DARKEN = 0.35;

void fragment() {
	vec4 frame = texture(screen_tex, SCREEN_UV);
	vec3 col = frame.rgb;

	// Desaturate toward luminance.
	float luma = dot(col, LUMA);
	col = mix(col, vec3(luma), clamp(desaturation, 0.0, 1.0));

	// Flat darkening proportional to dim.
	col *= 1.0 - MAX_FLAT_DARKEN * dim;

	// Soft radial vignette, also scaled by dim.
	float d = distance(SCREEN_UV, vec2(0.5));
	float v = smoothstep(VIGNETTE_INNER, VIGNETTE_OUTER, d);
	col *= 1.0 - VIGNETTE_STRENGTH * v * dim;

	COLOR = vec4(col, 1.0);
}
