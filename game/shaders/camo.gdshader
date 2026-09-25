// Knife Cell armor: object-space digital camo, grain, dust climbing from the ground.
shader_type spatial;

uniform vec3 c0 : source_color = vec3(0.17, 0.18, 0.2);
uniform vec3 c1 : source_color = vec3(0.23, 0.25, 0.27);
uniform vec3 c2 : source_color = vec3(0.12, 0.13, 0.15);
uniform float cell = 0.22;
uniform float rough = 0.62;
uniform float metal = 0.15;
uniform vec3 dust_col : source_color = vec3(0.55, 0.42, 0.3);
uniform float dust = 0.5;
uniform float ground_y = 0.0;
uniform float flash = 0.0;

varying vec3 obj;
varying vec3 wld;

float h3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vn(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	obj = VERTEX;
	wld = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 sp = floor(obj / cell) * cell;
	float n = vn(sp * 0.9) * 0.65 + vn(sp * 2.3 + 7.0) * 0.35;
	vec3 col = n < 0.46 ? c0 : (n < 0.6 ? c1 : c2);
	float g = vn(obj * 9.0);
	col *= 0.9 + 0.2 * g;
	float dh = smoothstep(ground_y + 3.2, ground_y + 0.2, wld.y) * dust * (0.55 + 0.45 * vn(wld * 1.9));
	col = mix(col, dust_col, dh);
	ALBEDO = col;
	ROUGHNESS = clamp(rough + (g - 0.5) * 0.24 + dh * 0.2, 0.05, 1.0);
	METALLIC = metal * (1.0 - dh);
	EMISSION = vec3(1.0, 0.35, 0.2) * flash;
}
