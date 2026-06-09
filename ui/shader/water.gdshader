// res://ui/shader/water.gdshader
// Eau avec RÉFLEXION PLANAIRE : reflets inversés "vrais" lus depuis une caméra-miroir
// (SubViewport "WaterViewport" + script water_reflection.gd) via reflection_tex.
// screen_tex sert encore à la réfraction (voir à travers l'eau).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx, depth_draw_opaque;

uniform vec3  shallow_color      : source_color      = vec3(0.20, 0.52, 0.76);
uniform vec3  deep_color         : source_color      = vec3(0.06, 0.24, 0.46);
uniform vec3  reflection_color   : source_color      = vec3(0.55, 0.72, 0.95);

uniform vec2  wave_direction     = vec2(1.0, 0.5);

uniform float wave_speed         : hint_range(0.0, 3.0)  = 0.35;
uniform float wave_freq          : hint_range(0.5, 30.0) = 9.5;
uniform float ripple_strength    : hint_range(0.0, 1.0)  = 0.20;
uniform float vertex_amp         : hint_range(0.0, 0.1)  = 0.006;

uniform float fresnel_power      : hint_range(0.5, 8.0)  = 3.0;
uniform float water_roughness    : hint_range(0.0, 1.0)  = 0.12;
uniform float reflection_strength: hint_range(0.0, 1.0)  = 0.5;
uniform float refraction_strength: hint_range(0.0, 0.2)  = 0.04;
uniform float water_clarity      : hint_range(0.0, 1.0)  = 0.5;

uniform bool refraction_enabled = true;

// Texture pour voir à travers l'eau (réfraction).
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
// Texture des vrais reflets isométriques (caméra-miroir -> WaterViewport).
uniform sampler2D reflection_tex : filter_linear_mipmap;

varying vec3 v_world;

float wave_height(vec2 p, float t) {
	vec2 dir = normalize(wave_direction);
	vec2 perp = vec2(-dir.y, dir.x);

	p -= dir * t * 0.4;

	vec2 warp = vec2(
		sin(dot(p, perp) * wave_freq * 0.3 + t * 0.4),
		cos(dot(p, dir) * wave_freq * 0.3 - t * 0.4)
	) * 0.15;

	p += warp;

	float h = 0.0;
	h += sin(dot(p, dir) * wave_freq) * 0.40;
	h += sin(dot(p, dir * 0.8 + perp * 0.3) * wave_freq * 1.5) * 0.20;
	h += sin(dot(p, dir * 1.1 - perp * 0.4) * wave_freq * 2.5) * 0.10;
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

	float e = 0.08;
	float dx = wave_height(p + vec2(e, 0.0), t) - wave_height(p - vec2(e, 0.0), t);
	float dz = wave_height(p + vec2(0.0, e), t) - wave_height(p - vec2(0.0, e), t);

	vec3 wn = normalize(vec3(dx, 1.0, dz) * vec3(ripple_strength, 1.0, ripple_strength));
	vec3 wn_view = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, wn_view, 0.7));

	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	vec3 tint = mix(shallow_color, deep_color, f);

	// --- VRAI REFLET (caméra-miroir exact) ---
	// Miroir géométrique exact -> on échantillonne au MÊME SCREEN_UV (pas d'inversion).
	// + petite distorsion par la normale pour suivre les vagues.
	vec2 ref_uv = SCREEN_UV + NORMAL.xy * refraction_strength;
	vec3 real_reflection = texture(reflection_tex, ref_uv).rgb;
	vec3 final_reflection_color = mix(reflection_color, real_reflection, 0.8);
	tint = mix(tint, final_reflection_color, f * reflection_strength);
	// -----------------------------------

	ROUGHNESS = water_roughness;
	METALLIC  = 0.0;
	SPECULAR  = 0.6;

	if (refraction_enabled) {
		vec2 ruv = SCREEN_UV - NORMAL.xy * refraction_strength;
		vec3 behind = textureLod(screen_tex, ruv, 0.0).rgb;
		float clear = water_clarity * (1.0 - f);
		EMISSION = behind * clear;
		ALBEDO   = tint * (1.0 - clear);
	} else {
		ALBEDO = tint;
	}
	ALPHA = 1.0;
}
