// res://assets/shaders/water.gdshader
// Procedural animated water for the Catan board.
// World-space waves => seamless ripples across every water hex.
// All knobs are exposed as uniforms (tweak live in the inspector).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3  shallow_color   : source_color      = vec3(0.20, 0.52, 0.76);
uniform vec3  deep_color      : source_color      = vec3(0.06, 0.24, 0.46);
uniform float wave_speed      : hint_range(0.0, 3.0)  = 0.7;   // animation speed
uniform float wave_freq       : hint_range(0.5, 20.0) = 5.5;   // ripple density
uniform float ripple_strength : hint_range(0.0, 1.0)  = 0.35;  // how bent the normals get
uniform float vertex_amp      : hint_range(0.0, 0.1)  = 0.012;  // tiny surface bob
uniform float fresnel_power   : hint_range(0.5, 8.0)  = 3.0;    // edge darkening
uniform float water_roughness : hint_range(0.0, 1.0)  = 0.12;   // lower = glossier glints

varying vec3 v_world;

// Cheap multi-directional sine field (no texture needed).
float wave_height(vec2 p, float t) {
	float h = 0.0;
	h += sin(p.x * wave_freq + t) * 0.5;
	h += sin((p.x * 0.6 + p.y * 1.4) * wave_freq * 0.8 + t * 1.25) * 0.30;
	h += sin((p.y * 1.1 - p.x * 0.3) * wave_freq * 1.3 - t * 0.9) * 0.20;
	return h;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	VERTEX.y += wave_height(v_world.xz, t) * vertex_amp;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = v_world.xz;

	// Analytic normal from the height field (central differences).
	float e = 0.08;
	float dx = wave_height(p + vec2(e, 0.0), t) - wave_height(p - vec2(e, 0.0), t);
	float dz = wave_height(p + vec2(0.0, e), t) - wave_height(p - vec2(0.0, e), t);
	vec3 wn = normalize(vec3(-dx, 1.0, -dz) * vec3(ripple_strength, 1.0, ripple_strength));
	vec3 wn_view = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, wn_view, 0.7));

	// Fresnel: shallow/light facing up, deep/dark at grazing angles.
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	ALBEDO    = mix(shallow_color, deep_color, f);
	ROUGHNESS = water_roughness;
	METALLIC  = 0.0;
	SPECULAR  = 0.6;
}
