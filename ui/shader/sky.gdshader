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

    float g1 = smoothstep(horizon_height - horizon_blur, horizon_height, UV.y);
    float g2 = smoothstep(horizon_height, horizon_height + horizon_blur, UV.y);
    
    vec3 sky_gradient = mix(col_top, col_horizon, g1);
    sky_gradient = mix(sky_gradient, col_bottom, g2);
    
    vec2 pixel_pos = UV / SCREEN_PIXEL_SIZE;
    vec2 screen_res = 1.0 / SCREEN_PIXEL_SIZE;
    
    if (enable_sun_moon && UV.y < horizon_height) {
        float horizon_y = horizon_height * screen_res.y;
        float horizon_fade = smoothstep(0.0, 0.15, horizon_height - UV.y);
        
        // 1. LE SOLEIL 
        float sun_p = -1.0;
        if (time_of_day >= 0.70) {
            sun_p = (time_of_day - 0.70) / 0.60;
        } else if (time_of_day <= 0.30) {
            sun_p = (time_of_day + 0.30) / 0.60;
        }
        
        if (sun_p >= 0.0 && sun_p <= 1.0) {
            float sun_x = mix(-0.2 * screen_res.x, 1.2 * screen_res.x, sun_p);
            float sun_y = horizon_y - sin(sun_p * PI) * (horizon_y * 0.85);
            
            float dist_sun = length(pixel_pos - vec2(sun_x, sun_y));
            float sun_disc = smoothstep(sun_radius * 2.5, sun_radius * 0.2, dist_sun); 
            float sun_glow = pow(smoothstep(sun_radius * 7.0, sun_radius * 0.1, dist_sun), 1.2) * 0.7;
            
            vec3 sun_final = (vec3(1.0, 1.0, 0.92) * sun_disc + vec3(1.0, 0.5, 0.1) * sun_glow) * (1.0 - stars_opacity);
            sky_gradient += sun_final * horizon_fade;
        }
        
        // 2. LA LUNE AVEC CROISSANT ALÉATOIRE CHAQUE NUIT
        float moon_p = -1.0;
        if (time_of_day >= 0.20 && time_of_day <= 0.80) {
            moon_p = (time_of_day - 0.20) / 0.60;
        }
        
        if (moon_p >= 0.0 && moon_p <= 1.0) {
            float moon_x = mix(-0.2 * screen_res.x, 1.2 * screen_res.x, moon_p);
            float moon_y = horizon_y - sin(moon_p * PI) * (horizon_y * 0.82);
            vec2 moon_center = vec2(moon_x, moon_y);
            
            float dist_moon = length(pixel_pos - moon_center);
            
            // --- NOUVEAU : CALCUL DE LA GÉOMÉTRIE DU CROISSANT ALÉATOIRE ---
            // On récupère l'ID du jour actuel pour changer de graine à chaque cycle
            float day_id = floor(TIME / cycle_duration);
            float rand_thickness = hash(vec2(day_id, 3.14)); // Épaisseur aléatoire
            float rand_tilt = hash(vec2(day_id, 9.81));      // Inclinaison aléatoire
            
            // On calcule le décalage de l'ombre en fonction des variables aléatoires du jour
            float shadow_dist_x = mix(0.25, 0.65, rand_thickness) * moon_radius;
            float shadow_dist_y = mix(-0.35, 0.35, rand_tilt) * moon_radius;
            
            vec2 shadow_center = moon_center + vec2(shadow_dist_x, shadow_dist_y);
            float shadow_disc = smoothstep(moon_radius * 1.06, moon_radius * 0.94, length(pixel_pos - shadow_center));
            
            float full_moon_disc = smoothstep(moon_radius * 1.06, moon_radius * 0.94, dist_moon);
            float moon_disc = clamp(full_moon_disc - shadow_disc, 0.0, 1.0);
            
            // Taches lunaires
            vec2 moon_local_uv = (pixel_pos - moon_center) / moon_radius;
            float moon_noise = noise(moon_local_uv * 3.0) * 0.6 + noise(moon_local_uv * 6.0) * 0.4;
            float dark_spots = smoothstep(0.2, 0.8, moon_noise) * 0.35; 
            
            vec3 moon_base_color = vec3(0.75, 0.78, 0.83) * (1.0 - dark_spots);
            
            // Lumière cendrée (Earthshine)
            float earthshine = full_moon_disc * 0.04; 
            
            // Halo de brume nocturne
            float moon_glow = smoothstep(moon_radius * 3.5, moon_radius * 0.1, dist_moon) * 0.12; 
            
            vec3 moon_final = (moon_base_color * (moon_disc + earthshine) + vec3(0.8, 0.85, 1.0) * moon_glow) * stars_opacity;
            sky_gradient += moon_final * horizon_fade;
        }
    }
    
    // Étoiles de nuit
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
            
            float horizon_fade = smoothstep(0.0, 0.2, horizon_height - UV.y);
            sky_gradient += vec3(star_shape * twinkle * stars_opacity * horizon_fade);
        }
    }
    
    // Nuages
    vec2 cloud_uv = UV * cloud_scale;
    cloud_uv.x += TIME * cloud_speed; 
    cloud_uv.y -= horizon_height * 0.5;
    
    float n = noise(cloud_uv) * 0.6 + noise(cloud_uv * 2.5) * 0.4;
    float cloud_mask = smoothstep(1.0 - cloud_density, 1.0 - cloud_density + 0.1, n);
    
    float horizon_dist = 1.0 - smoothstep(0.1, 0.5, abs(UV.y - horizon_height));
    cloud_mask *= horizon_dist;
    
    float current_cloud_alpha = mix(day_clouds.a, night_clouds.a, stars_opacity);
    if((time_of_day > 0.0 && time_of_day < 0.25) || (time_of_day > 0.5 && time_of_day < 0.75)) {
        current_cloud_alpha = sunset_clouds.a;
    }
    
    vec3 final_color = mix(sky_gradient, col_cloud, cloud_mask * current_cloud_alpha);
    
    COLOR = vec4(final_color, 1.0);
}