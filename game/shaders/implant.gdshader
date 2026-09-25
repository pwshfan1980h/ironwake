// Ocular implant overlay: the HUD is drawn into a viewport, then projected with slight RGB split,
// a slow scan band, and slice-glitching when the pilot link takes a jolt.
shader_type canvas_item;
// the viewport holds premultiplied colour, so blend it that way
render_mode blend_premul_alpha;

uniform float glitch = 0.0;
uniform float link = 1.0;

float h1(float n) {
	return fract(sin(n * 91.3458) * 47453.5453);
}

void fragment() {
	vec2 uv = UV;
	float tb = floor(TIME * 24.0);
	float band = floor(uv.y * 36.0);
	float r = h1(band + tb * 13.0);
	uv.x += (r - 0.5) * 0.05 * glitch * step(0.72, r);
	float ca = 0.0005 + glitch * 0.008;
	vec4 c = texture(TEXTURE, uv);
	vec4 cr = texture(TEXTURE, uv + vec2(ca, 0.0));
	vec4 cb = texture(TEXTURE, uv - vec2(ca, 0.0));
	vec3 rgb = vec3(cr.r, c.g, cb.b);
	float a = max(c.a, max(cr.a, cb.a) * 0.7);
	// slow scan band rolling down the optic, plus faint line structure
	float scan = smoothstep(0.0, 0.04, abs(fract(uv.y - TIME * 0.08) - 0.5));
	float k = mix(1.25, 1.0, scan) * (0.9 + 0.1 * sin(FRAGCOORD.y * 1.7));
	// flicker while the link is still syncing
	k *= mix(0.6 + 0.4 * h1(tb), 1.0, step(0.999, link));
	COLOR = vec4(rgb, a) * k;
}
