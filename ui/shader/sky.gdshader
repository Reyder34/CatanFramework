shader_type canvas_item;

group_uniforms Option_Visualisation;
uniform bool enable_sun_moon = true; 

group_uniforms Cycle_Jour_Nuit;
// 1200 secondes = 20 minutes (10m de jour / 10m de nuit)
uniform float cycle_duration : hint_range(5.0, 3600.0) = 1200.0;

group_uniforms Couleurs_Jour;
uniform vec4 day_top : source_color = vec4(0.2, 0.5, 0.8, 1.0);
uniform vec4 day_horizon : source_color = vec4(0.7, 0.8, 0.9, 1.0);
uniform vec4 day_bottom : source_color = vec4(0.1, 0.15, 0.25, 1.0);
uniform vec4 day_clouds : source_color = vec4(1.0, 1.0, 1.0, 0.4);

group_uniforms Couleurs_Sunset;
uniform vec4 sunset_top : source_color = vec4(0.15, 0.2, 0.4, 1.0);
uniform vec4 sunset_horizon : source_color = vec4(0.9, 0.4, 0.1, 1.0);
uniform vec4 sunset_bottom : source_color = vec4(0.05, 0.05, 0.1, 1.0);
uniform vec4 sunset_clouds : source_color = vec4(0.9, 0.6, 0.6, 0.4);

group_uniforms Couleurs_Nuit;
uniform vec4 night_top : source_color = vec4(0.02, 0.04, 0.08, 1.0);
uniform vec4 night_horizon : source_color = vec4(0.07, 0.1, 0.18, 1.0);
uniform vec4 night_bottom : source_color = vec4(0.01, 0.02, 0.04, 1.0);
uniform vec4 night_clouds : source_color = vec4(0.2, 0.3, 0.5, 0.15);

group_uniforms Etoiles;
uniform float star_twinkle_speed : hint_range(0.1, 5.0) = 1.5; 
uniform float star_density : hint_range(0.95, 0.999) = 0.985;  
uniform float star_max_radius : hint_range(0.5, 3.0) = 1.2;    

group_uniforms Soleil_Et_Lune;
uniform float sun_radius : hint_range(5.0, 150.0) = 65.0;   
uniform float moon_radius : hint_range(5.0, 100.0) = 26.0;  

group_uniforms Dynamique_Visuelle;
uniform float horizon_height : hint_range(0.0, 1.0) = 0.5;
uniform float horizon_blur : hint_range(0.0, 1.0) = 0.3;

group_uniforms Nuages;
uniform float cloud_scale : hint_range(0.1, 10.0) = 3.0;
uniform float cloud_speed : hint_range(0.0, 1.0) = 0.05;
uniform float cloud_density : hint_range(0.0, 1.0) = 0.45;

group_uniforms Meteo;
uniform float meteo_nuageux : hint_range(0.0, 1.0) = 0.0; 
uniform float meteo_pluie : hint_range(0.0, 1.0) = 0.0;   
uniform float meteo_neige : hint_range(0.0, 1.0) = 0.0;   
uniform float meteo_tempete : hint_range(0.0, 1.0) = 0.0; 
uniform float lightning_flash : hint_range(0.0, 1.0) = 0.0;
uniform float weather_cloud_phase = 0.0; // Defilement meteo des nuages, INTEGRE par le code (evite le saut vers 0.70)
uniform float weather_rain_phase = 0.0;  // Idem pour la chute de pluie 

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2(0.0,0.0)), hash(i + vec2(1.0,0.0)), u.x),
               mix(hash(i + vec2(0.0,1.0)), hash(i + vec2(1.0,1.0)), u.x), u.y);
}

void fragment() {
    float time_of_day = fract(TIME / cycle_duration);

    float total_weather_cover = clamp(meteo_nuageux + meteo_pluie + meteo_neige + meteo_tempete, 0.0, 1.0);
    float storm_intensity = clamp(meteo_pluie + meteo_tempete, 0.0, 1.0);
    float celestial_fade = 1.0 - smoothstep(0.0, 0.5, total_weather_cover); 
    
    // VITESSE NUAGES : la part meteo (pluie/tempete) est integree par le CODE (weather_cloud_phase).
    // Multiplier TIME par une vitesse qui change faisait "sauter" les nuages au passage de ~0.70.
    
    float dyn_cloud_density = clamp(cloud_density + (meteo_nuageux * 0.25) + (meteo_pluie * 0.3) + (meteo_neige * 0.25) + (meteo_tempete * 0.35), 0.0, 0.75);

    vec3 col_top, col_horizon, col_bottom, col_cloud;
    float stars_opacity = 0.0;
    
    if (time_of_day < 0.25) { 
        float t = time_of_day / 0.25;
        col_top = mix(day_top.rgb, sunset_top.rgb, t);
        col_horizon = mix(day_horizon.rgb, sunset_horizon.rgb, t);
        col_bottom = mix(day_bottom.rgb, sunset_bottom.rgb, t);
        col_cloud = mix(day_clouds.rgb, sunset_clouds.rgb, t);
    } 
    else if (time_of_day < 0.50) { 
        float t = (time_of_day - 0.25) / 0.25;
        col_top = mix(sunset_top.rgb, night_top.rgb, t);
        col_horizon = mix(sunset_horizon.rgb, night_horizon.rgb, t);
        col_bottom = mix(sunset_bottom.rgb, night_bottom.rgb, t);
        col_cloud = mix(sunset_clouds.rgb, night_clouds.rgb, t);
        stars_opacity = t;
    } 
    else if (time_of_day < 0.75) { 
        float t = (time_of_day - 0.50) / 0.25;
        col_top = mix(night_top.rgb, sunset_top.rgb, t);
        col_horizon = mix(night_horizon.rgb, sunset_horizon.rgb, t);
        col_bottom = mix(night_bottom.rgb, sunset_bottom.rgb, t);
        col_cloud = mix(night_clouds.rgb, sunset_clouds.rgb, t);
        stars_opacity = 1.0 - t;
    } 
    else { 
        float t = (time_of_day - 0.75) / 0.25;
        col_top = mix(sunset_top.rgb, day_top.rgb, t);
        col_horizon = mix(sunset_horizon.rgb, day_horizon.rgb, t);
        col_bottom = mix(sunset_bottom.rgb, day_bottom.rgb, t);
        col_cloud = mix(day_clouds.rgb, day_clouds.rgb, t);
    }

    vec3 c_overcast = vec3(0.45, 0.5, 0.55);
    vec3 c_rain = vec3(0.25, 0.3, 0.35);
    vec3 c_snow = vec3(0.65, 0.7, 0.75);
    vec3 c_storm = vec3(0.25, 0.28, 0.35); 
    
    vec3 cloud_overcast = vec3(0.35, 0.4, 0.45);
    vec3 cloud_rain = vec3(0.15, 0.18, 0.22);
    vec3 cloud_snow = vec3(0.85, 0.9, 0.95);
    vec3 cloud_storm = vec3(0.06, 0.07, 0.09); 
    
    vec3 weather_sky = mix(col_top, c_overcast, meteo_nuageux);
    weather_sky = mix(weather_sky, c_rain, meteo_pluie);
    weather_sky = mix(weather_sky, c_snow, meteo_neige);
    weather_sky = mix(weather_sky, c_storm, meteo_tempete);
    
    weather_sky = mix(weather_sky, vec3(0.7, 0.8, 1.0), lightning_flash * meteo_tempete * 0.4);
    
    vec3 weather_cloud = mix(col_cloud, cloud_overcast, meteo_nuageux);
    weather_cloud = mix(weather_cloud, cloud_rain, meteo_pluie);
    weather_cloud = mix(weather_cloud, cloud_snow, meteo_neige);
    weather_cloud = mix(weather_cloud, cloud_storm, meteo_tempete);
    
    col_top = mix(col_top, weather_sky, total_weather_cover);
    col_horizon = mix(col_horizon, weather_sky * 0.85, total_weather_cover);
    
    float g1 = smoothstep(horizon_height - horizon_blur, horizon_height, UV.y);
    float g2 = smoothstep(horizon_height, horizon_height + horizon_blur, UV.y);
    
    vec3 sky_gradient = mix(col_top, col_horizon, g1);
    sky_gradient = mix(sky_gradient, col_bottom, g2);
    
    vec2 pixel_pos = UV / SCREEN_PIXEL_SIZE;
    vec2 screen_res = 1.0 / SCREEN_PIXEL_SIZE;
    float weather_horizon_fade = smoothstep(0.0, 0.2, horizon_height - UV.y);

    if (enable_sun_moon && UV.y < horizon_height) {
        float horizon_y = horizon_height * screen_res.y;
        float horizon_fade = smoothstep(0.0, 0.15, horizon_height - UV.y);
        
        float sun_p = -1.0;
        if (time_of_day >= 0.70) { sun_p = (time_of_day - 0.70) / 0.60; } 
        else if (time_of_day <= 0.30) { sun_p = (time_of_day + 0.30) / 0.60; }
        
        if (sun_p >= 0.0 && sun_p <= 1.0) {
            float sun_x = mix(-0.2 * screen_res.x, 1.2 * screen_res.x, sun_p);
            float sun_y = horizon_y - sin(sun_p * PI) * (horizon_y * 0.85);
            float dist_sun = length(pixel_pos - vec2(sun_x, sun_y));
            float sun_disc = smoothstep(sun_radius * 2.5, sun_radius * 0.2, dist_sun); 
            float sun_glow = pow(smoothstep(sun_radius * 7.0, sun_radius * 0.1, dist_sun), 1.2) * 0.7;
            vec3 sun_final = (vec3(1.0, 1.0, 0.92) * sun_disc + vec3(1.0, 0.5, 0.1) * sun_glow) * (1.0 - stars_opacity);
            sky_gradient += sun_final * horizon_fade * celestial_fade; 
        }
        
        float moon_p = -1.0;
        if (time_of_day >= 0.20 && time_of_day <= 0.80) { moon_p = (time_of_day - 0.20) / 0.60; }
        
        if (moon_p >= 0.0 && moon_p <= 1.0) {
            float moon_x = mix(-0.2 * screen_res.x, 1.2 * screen_res.x, moon_p);
            float moon_y = horizon_y - sin(moon_p * PI) * (horizon_y * 0.82);
            vec2 moon_center = vec2(moon_x, moon_y);
            float dist_moon = length(pixel_pos - moon_center);
            
            float day_id = floor(TIME / cycle_duration);
            float rand_thickness = hash(vec2(day_id, 3.14));
            float rand_tilt = hash(vec2(day_id, 9.81));      
            
            vec2 shadow_center = moon_center + vec2(mix(0.25, 0.65, rand_thickness) * moon_radius, mix(-0.35, 0.35, rand_tilt) * moon_radius);
            float shadow_disc = smoothstep(moon_radius * 1.06, moon_radius * 0.94, length(pixel_pos - shadow_center));
            float full_moon_disc = smoothstep(moon_radius * 1.06, moon_radius * 0.94, dist_moon);
            float moon_disc = clamp(full_moon_disc - shadow_disc, 0.0, 1.0);
            
            vec2 moon_local_uv = (pixel_pos - moon_center) / moon_radius;
            float moon_noise = noise(moon_local_uv * 3.0) * 0.6 + noise(moon_local_uv * 6.0) * 0.4;
            float dark_spots = smoothstep(0.2, 0.8, moon_noise) * 0.35; 
            
            vec3 moon_base_color = vec3(0.75, 0.78, 0.83) * (1.0 - dark_spots);
            float earthshine = full_moon_disc * 0.04; 
            float moon_glow = smoothstep(moon_radius * 3.5, moon_radius * 0.1, dist_moon) * 0.12; 
            
            vec3 moon_final = (moon_base_color * (moon_disc + earthshine) + vec3(0.8, 0.85, 1.0) * moon_glow) * stars_opacity;
            sky_gradient += moon_final * horizon_fade * celestial_fade; 
        }
    }
    
    if (stars_opacity > 0.0 && UV.y < horizon_height) {
        float grid_size = 24.0; 
        vec2 st_id = floor(pixel_pos / grid_size);
        vec2 st_f = fract(pixel_pos / grid_size);
        float star_hash = hash(st_id);
        if (star_hash > star_density) {
            float dist_in_pixels = length((st_f - vec2(0.5)) * grid_size);
            float star_shape = smoothstep(star_max_radius, star_max_radius - 0.8, dist_in_pixels);
            float unique_speed = star_twinkle_speed * (0.4 + star_hash * 1.6);
            float twinkle = sin(TIME * unique_speed + star_hash * 42.0) * 0.45 + 0.55;
            sky_gradient += vec3(star_shape * twinkle * stars_opacity * weather_horizon_fade * celestial_fade);
        }
    }
    
    // --- NUAGES ---
    vec2 cloud_uv = UV * cloud_scale;
    cloud_uv.x += TIME * cloud_speed + weather_cloud_phase; 
    cloud_uv.y -= horizon_height * 0.5;
    float n_base = noise(cloud_uv) * 0.6 + noise(cloud_uv * 2.5) * 0.4;
    
    vec2 storm_cloud_uv = UV * (cloud_scale * 0.35); 
    storm_cloud_uv.x += (TIME * cloud_speed + weather_cloud_phase) * 0.8;
    float n_storm = noise(storm_cloud_uv) * 0.7 + noise(storm_cloud_uv * 2.0) * 0.3;
    
    float n_final = mix(n_base, max(n_base, n_storm), storm_intensity * 0.8);

    float cloud_mask = smoothstep(1.0 - dyn_cloud_density, 1.0 - dyn_cloud_density + 0.2, n_final);
    
    float cloud_interior = smoothstep(1.0 - dyn_cloud_density + 0.1, 1.0 - dyn_cloud_density + 0.35, n_final);
    vec3 flash_color = vec3(1.0, 1.0, 1.0) * lightning_flash * meteo_tempete * 2.0;
    
    float cloud_depth = smoothstep(horizon_height - 0.4, horizon_height, UV.y);
    vec3 base_cloud_color = mix(col_cloud, weather_cloud, total_weather_cover);
    base_cloud_color = mix(base_cloud_color, base_cloud_color * 0.3, cloud_depth * storm_intensity * cloud_mask);
    
    vec3 final_cloud_color = base_cloud_color + (flash_color * cloud_interior);
    
    float horizon_dist_normal = 1.0 - smoothstep(0.1, 0.5, abs(UV.y - horizon_height));
    float horizon_dist_storm = 1.0 - smoothstep(0.1, 0.9, abs(UV.y - horizon_height));
    float horizon_dist = mix(horizon_dist_normal, horizon_dist_storm, total_weather_cover);
    
    cloud_mask *= horizon_dist;
    
    float current_cloud_alpha = mix(day_clouds.a, night_clouds.a, stars_opacity);
    if((time_of_day > 0.0 && time_of_day < 0.25) || (time_of_day > 0.5 && time_of_day < 0.75)) {
        current_cloud_alpha = sunset_clouds.a;
    }
    current_cloud_alpha = mix(current_cloud_alpha, 0.98, total_weather_cover); 
    
    // --- RENDU ATMOSPHÉRIQUE DE PLUIE / NEIGE ---
    
    // 1. PLUIE
    vec2 rain_uv = UV;
    float wind_angle = 0.2 + (meteo_tempete * 0.4);
    rain_uv.x += rain_uv.y * wind_angle; 
    
    vec2 rain_scale = vec2(700.0, 15.0);
    vec2 scaled_rain = rain_uv * rain_scale;
    // Base constante sur TIME ; le surplus tempete/neige est integre par le code (weather_rain_phase).
    scaled_rain.y -= TIME * 12.0 + weather_rain_phase;
    
    float column_id = floor(scaled_rain.x);
    scaled_rain.y += hash(vec2(column_id, 0.0)) * 100.0; 
    
    vec2 r_id = floor(scaled_rain);
    vec2 r_f = fract(scaled_rain);
    float drop_hash = hash(r_id);
    
    float rain_threshold = 0.96 - (meteo_pluie * 0.1) - (meteo_tempete * 0.15);
    float drop_present = step(rain_threshold, drop_hash); 
    
    float drop_width = smoothstep(0.15, 0.0, abs(r_f.x - 0.5));
    float drop_length = smoothstep(0.4, 0.1, abs(r_f.y - 0.5));
    
    float rain_mask = drop_width * drop_length * drop_present * clamp(meteo_pluie + meteo_tempete, 0.0, 1.0) * weather_horizon_fade;
    vec3 rain_color = vec3(0.65, 0.7, 0.8);

    // 2. NEIGE
    vec2 snow_uv = UV * vec2(12.0, 12.0);
    snow_uv.x += sin(TIME * 0.3 + UV.y * 3.0) * 0.4; 
    snow_uv.y -= TIME * 0.15; 
    float snow_n = noise(snow_uv);
    float snow_flakes = smoothstep(0.75, 0.85, snow_n);
    float snow_mask = snow_flakes * meteo_neige * 0.8 * weather_horizon_fade;
    
    // --- MÉLANGE FINAL ---
    vec3 final_color = mix(sky_gradient, final_cloud_color, cloud_mask * current_cloud_alpha);
    final_color += rain_color * rain_mask;
    final_color = mix(final_color, vec3(0.95, 0.95, 1.0), snow_mask);
    
    COLOR = vec4(final_color, 1.0);
}