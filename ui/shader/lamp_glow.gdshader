shader_type spatial;
// Ampoule de lampadaire : éteinte le jour, allumée la nuit — AUTOMATIQUEMENT.
// Pilotée par le global shader "day_night_factor" (1 = plein jour, 0 = nuit), mis à jour
// chaque frame par l'autoload DayNight. Aucun script : marche sur toutes les routes
// instanciées (jeu + menu), sans coût par instance (le GPU lit un seul uniform global).
// L'émission monte/descend en douceur au crépuscule/à l'aube (day_factor est lissé).

global uniform float day_night_factor;

uniform vec3 lamp_color : source_color = vec3(1.0, 0.82, 0.45); // blanc chaud
uniform float glow_strength : hint_range(0.0, 16.0) = 3.0;       // intensité d'émission la nuit
uniform float day_albedo : hint_range(0.0, 1.0) = 0.55;          // teinte de l'ampoule éteinte (jour)

void fragment() {
	float night = clamp(1.0 - day_night_factor, 0.0, 1.0);
	ALBEDO = lamp_color * day_albedo;
	EMISSION = lamp_color * glow_strength * night;
}
