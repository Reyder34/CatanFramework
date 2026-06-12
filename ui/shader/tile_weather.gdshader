shader_type spatial;
// Surcouche meteo posee sur TOUTES les tuiles via MeshInstance3D.material_overlay : une passe
// transparente par-dessus le materiau de base (peu importe lequel), donc rien a reecrire.
// Pilotee par des parametres GLOBAUX que l'autoload Weather met a jour chaque frame
// (comme day_night_factor) -> identique sur toutes les tuiles, synchronise en multi.
//
//   weather_snow : 0..1 -> couche de neige blanche sur les faces tournees vers le ciel
//   weather_wet  : 0..1 -> voile SOMBRE (mouille) + petits "ploc" de pluie ; coupe pendant la neige
//
// Le mouille ASSOMBRIT (mate, aucun reflet) pour ne pas blanchir la tuile comme de la neige.

render_mode blend_mix, cull_back;

global uniform float weather_snow;
global uniform float weather_wet;

uniform float snow_up_sharpness : hint_range(0.5, 8.0) = 3.0;  // + grand = neige surtout bien a plat
uniform float ripple_scale : hint_range(1.0, 12.0) = 5.0;      // densite des ploc (+ grand = + petits/nombreux)
uniform float ripple_speed : hint_range(0.1, 3.0) = 0.9;       // frequence des ploc

// Hash 3D -> 0..1, deterministe (grain de neige, paillettes, ploc de pluie).
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

// Un "ploc" de pluie par cellule de la grille : un anneau concentrique nait a un instant pseudo-aleatoire,
// s'agrandit puis s'estompe. PERF : une seule cellule (pas de boucle 3x3) -> ~9x moins de hash par fragment.
// Le centre est confine a [0.3, 0.7] et le rayon max (0.25) garde l'anneau DANS la cellule (pas de debordement).
float rain_ripples(vec2 p, float t) {
	vec2 c = floor(p);
	float seed = hash13(vec3(c, 7.0));
	float cycle = t * ripple_speed + seed;
	float prog = fract(cycle);                                       // 0..1 : age de l'anneau
	vec2 center = c + 0.3 + 0.4 * vec2(hash13(vec3(c, 1.0)), hash13(vec3(c, 2.0)));
	float d = length(p - center);
	float ring = smoothstep(0.07, 0.0, abs(d - prog * 0.25));        // anneau fin qui grandit
	float fade = 1.0 - prog;                                         // s'estompe en grandissant
	float active = step(0.4, hash13(vec3(c, floor(cycle) + 3.0)));   // rythme irregulier (ploc... ploc..)
	return clamp(ring * fade * active, 0.0, 1.0);
}

void fragment() {
	// Normale en espace MONDE : neige/ploc tiennent sur les faces qui regardent le ciel.
	vec3 wn = normalize(mat3(INV_VIEW_MATRIX) * NORMAL);
	float up = clamp(wn.y, 0.0, 1.0);

	float snow = weather_snow * pow(up, snow_up_sharpness);
	float wet = weather_wet * mix(0.3, 0.55, up);

	float cover = clamp(snow + wet, 0.0, 1.0);
	float snow_ratio = snow / max(snow + wet, 0.0001);

	// Neige : blanc legerement bleute, avec grain + quelques paillettes.
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = hash13(floor(world_pos * 45.0));
	float grain = 0.85 + 0.15 * h;
	float sparkle = step(0.99, h) * up * weather_snow;
	vec3 snow_col = vec3(0.93, 0.96, 1.0) * grain;

	vec3 wet_col = vec3(0.04, 0.06, 0.09);   // voile sombre (mouille)

	// Ploc de pluie : seulement sur le dessus, seulement quand il pleut (pas pendant la neige).
	float ripple = 0.0;
	if (weather_wet > 0.01) {
		ripple = rain_ripples(world_pos.xz * ripple_scale, TIME) * up * weather_wet;
	}

	vec3 base = mix(wet_col, snow_col, snow_ratio);
	base += vec3(0.22, 0.28, 0.36) * ripple * (1.0 - snow_ratio);   // anneau plus clair = eau remuee

	ALBEDO = base;
	ALPHA = clamp(cover + ripple * 0.35, 0.0, 1.0);   // l'anneau se voit meme sur un voile leger
	ROUGHNESS = mix(0.5, 0.9, snow_ratio);            // mouille = satine (pas miroir) ; neige = mate
	METALLIC = 0.0;
	EMISSION = vec3(sparkle) * 0.5 + vec3(0.10, 0.13, 0.17) * ripple;   // petit eclat du ploc
}
