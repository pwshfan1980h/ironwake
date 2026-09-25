// Cockpit canopy glass: faint tint, fresnel sheen, dust settling along the frame, fine scratches.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.62, 0.78, 0.82);
uniform float base_alpha = 0.035;
uniform vec3 dust_col : source_color = vec3(0.62, 0.48, 0.36);
uniform float dust = 1.0;
uniform float damage = 0.0;

float h2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vn(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	// UV spans each pane 0..1: dust collects at the edges, heaviest along the bottom
	vec2 e = min(UV, 1.0 - UV);
	float edge = 1.0 - smoothstep(0.0, 0.16, min(e.x, e.y));
	float bottom = 1.0 - smoothstep(0.0, 0.3, 1.0 - UV.y);
	float n = vn(UV * vec2(38.0, 30.0)) * 0.6 + vn(UV * vec2(120.0, 90.0)) * 0.4;
	float grime = clamp((edge * 0.7 + bottom * 0.5) * (0.4 + n), 0.0, 1.0) * dust;
	// hairline scratches: thin diagonal streaks
	float sc = smoothstep(0.985, 1.0, vn(vec2(UV.x * 3.0 + UV.y * 1.3, UV.y * 180.0 - UV.x * 40.0)));
	// cracks when armor is low: a jagged web near one corner
	float cr = 0.0;
	if (damage > 0.0) {
		vec2 q = (UV - vec2(0.18, 0.82)) * vec2(1.6, 1.0);
		float r = length(q);
		float a = atan(q.y, q.x);
		float spokes = smoothstep(0.93, 1.0, vn(vec2(a * 9.0, r * 3.0)));
		float rings = smoothstep(0.96, 1.0, vn(vec2(r * 60.0, a * 2.0)));
		cr = (spokes + rings * 0.6) * (1.0 - smoothstep(0.0, 0.5 + damage * 0.3, r)) * damage;
	}
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 4.0);
	ALBEDO = mix(tint, dust_col, clamp(grime * 1.4, 0.0, 1.0));
	ALBEDO = mix(ALBEDO, vec3(0.9), clamp(sc * 0.5 + cr, 0.0, 1.0));
	ROUGHNESS = mix(0.04, 0.6, grime);
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ALPHA = clamp(base_alpha + fres * 0.25 + grime * 0.32 + sc * 0.12 + cr * 0.7, 0.0, 0.9);
}
