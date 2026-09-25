// Harrow Basin desert: sand/rock by slope, strata on cliffs, wind ripples and grit as detail normals.
shader_type spatial;

uniform vec3 sand_a : source_color = vec3(0.62, 0.45, 0.31);
uniform vec3 sand_b : source_color = vec3(0.72, 0.55, 0.38);
uniform vec3 sand_c : source_color = vec3(0.5, 0.36, 0.26);
uniform vec3 rock_a : source_color = vec3(0.36, 0.26, 0.21);
uniform vec3 rock_b : source_color = vec3(0.5, 0.36, 0.28);
uniform vec3 wash : source_color = vec3(0.42, 0.34, 0.28);

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vn2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vn2(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

float detail_h(vec2 p, float rockiness) {
	float warp = fbm(p * 0.13) * 6.0;
	float rip = sin(dot(p, vec2(0.83, 0.55)) * 2.4 + warp) * 0.5 + 0.5;
	float grit = vn2(p * 3.1) * 0.6 + vn2(p * 7.3) * 0.4;
	float chips = fbm(p * 0.9);
	return mix(rip * 0.3 + grit * 0.7, chips * 1.6 + grit * 0.3, rockiness);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	float slope = 1.0 - n.y;
	float big = fbm(wpos.xz * 0.018);
	float mid = fbm(wpos.xz * 0.11 + 4.0);
	float fine = vn2(wpos.xz * 2.2);
	vec3 sand = mix(sand_a, sand_b, smoothstep(0.3, 0.72, big));
	sand = mix(sand, sand_c, smoothstep(0.55, 0.85, mid) * 0.6);
	sand = mix(sand, wash, smoothstep(2.0, -3.0, wpos.y) * 0.5);
	vec3 rock = mix(rock_a, rock_b, mid);
	float strata = sin(wpos.y * 1.25 + mid * 3.0) * 0.5 + 0.5;
	rock *= 0.78 + 0.3 * strata;
	float rk = smoothstep(0.2, 0.4, slope + (mid - 0.5) * 0.2);
	vec3 col = mix(sand, rock, rk) * (0.88 + 0.22 * fine);

	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float amt = mix(0.4, 1.0, rk) * (1.0 - smoothstep(50.0, 220.0, dist));
	float e = 0.12;
	vec2 p = wpos.xz;
	float h0 = detail_h(p, rk);
	float hx = detail_h(p + vec2(e, 0.0), rk);
	float hz = detail_h(p + vec2(0.0, e), rk);
	vec3 dn = normalize(n + vec3(-(hx - h0) / e, 0.0, -(hz - h0) / e) * amt * 0.22);
	NORMAL = normalize((VIEW_MATRIX * vec4(dn, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = 0.94;
	SPECULAR = 0.25;
}
