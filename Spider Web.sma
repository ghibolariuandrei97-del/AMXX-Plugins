#include <amxmodx>
#include <amxmisc>
#include <engine>
#include <fakemeta>
#include <hamsandwich>
#include <xs>

#define PLUGIN "Spider-Web Detector Fix"
#define VERSION "1.0"
#define AUTHOR "Ai"

#define ADMIN_WH_ACCESS ADMIN_BAN
#define BEAM_UPDATE_INTERVAL 0.07  // Fast enough for movement, slow enough for clarity
#define DETECTION_RADIUS 40.0

new bool:g_is_detecting[33];
new Float:g_last_draw[33];
new g_spr_beam;
new g_maxplayers;

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    
    register_clcmd("say /wh", "cmd_toggle_detector");
    register_clcmd("say_team /wh", "cmd_toggle_detector");
    
    // Fixed the underscore here: Ham_Player_PreThink
    RegisterHam(Ham_Player_PreThink, "player", "fw_PreThink");
    
    g_maxplayers = get_maxplayers();
}

public plugin_precache() {
    g_spr_beam = precache_model("sprites/zbeam4.spr");
}

public client_disconnected(id) {
    g_is_detecting[id] = false;
    g_last_draw[id] = 0.0;
}

public cmd_toggle_detector(id) {
    if (!(get_user_flags(id) & ADMIN_WH_ACCESS)) return PLUGIN_HANDLED;
    
    g_is_detecting[id] = !g_is_detecting[id];
    client_print(id, print_chat, "[WH] Spider-Web Mode %s", g_is_detecting[id] ? "^3ENABLED" : "^1DISABLED");
    
    return PLUGIN_HANDLED;
}

public fw_PreThink(id) {
    if (!g_is_detecting[id] || is_user_alive(id))
        return HAM_IGNORED;

    new Float:fTime = get_gametime();
    if (fTime - g_last_draw[id] < BEAM_UPDATE_INTERVAL)
        return HAM_IGNORED;

    g_last_draw[id] = fTime;

    // Get spectated player (iuser2)
    new target = entity_get_int(id, EV_INT_iuser2);
    
    if (1 <= target <= g_maxplayers && is_user_alive(target)) {
        draw_logic(id, target);
    }
    
    return HAM_HANDLED;
}

draw_logic(admin, target) {
    static Float:t_origin[3], Float:t_view[3], Float:t_eye_pos[3];
    static Float:aim_vec[3], Float:aim_end[3], Float:trace_hit[3];
    
    entity_get_vector(target, EV_VEC_origin, t_origin);
    entity_get_vector(target, EV_VEC_view_ofs, t_view);
    xs_vec_add(t_origin, t_view, t_eye_pos);
    
    // Calculate aim line
    velocity_by_aim(target, 2500, aim_vec);
    xs_vec_add(t_eye_pos, aim_vec, aim_end);
    
    // Trace for the main beam endpoint (stops at walls)
    engfunc(EngFunc_TraceLine, t_eye_pos, aim_end, IGNORE_MONSTERS, target, 0);
    get_tr2(0, TR_vecEndPos, trace_hit);

    new target_team = get_user_team(target);
    new bool:is_locking = false;

    // Loop through players to draw web lines
    for (new i = 1; i <= g_maxplayers; i++) {
        if (!is_user_alive(i) || i == target) continue;

        static Float:enemy_origin[3];
        entity_get_vector(i, EV_VEC_origin, enemy_origin);
        
        // Use math to check if the aim line passes near the enemy
        new bool:aiming_at_this = (get_distance_to_line(t_eye_pos, aim_end, enemy_origin) < DETECTION_RADIUS);
        
        if (get_user_team(i) != target_team) {
            // Draw thin connection to enemy
            // Red if aiming at them, Yellow if just existing
            create_beam(admin, t_origin, enemy_origin, aiming_at_this ? {255, 0, 0} : {255, 255, 0}, aiming_at_this ? 10 : 2);
            
            if (aiming_at_this) is_locking = true;
        }
    }

    // MAIN AIM BEAM (Green or Red)
    create_beam(admin, t_eye_pos, trace_hit, is_locking ? {255, 0, 0} : {0, 255, 0}, 7);
}

create_beam(admin, Float:start[3], Float:end[3], color[3], width) {
    message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, admin);
    write_byte(TE_BEAMPOINTS);
    engfunc(EngFunc_WriteCoord, start[0]);
    engfunc(EngFunc_WriteCoord, start[1]);
    engfunc(EngFunc_WriteCoord, start[2]);
    engfunc(EngFunc_WriteCoord, end[0]);
    engfunc(EngFunc_WriteCoord, end[1]);
    engfunc(EngFunc_WriteCoord, end[2]);
    write_short(g_spr_beam);
    write_byte(0); // start frame
    write_byte(0); // framerate
    write_byte(1); // life (0.1s)
    write_byte(width); 
    write_byte(0); // noise
    write_byte(color[0]); 
    write_byte(color[1]); 
    write_byte(color[2]);
    write_byte(180); // brightness
    write_byte(0); 
    message_end();
}

Float:get_distance_to_line(Float:A[3], Float:B[3], Float:P[3]) {
    static Float:AB[3], Float:AP[3], Float:area[3];
    xs_vec_sub(B, A, AB);
    xs_vec_sub(P, A, AP);
    xs_vec_cross(AB, AP, area);
    
    // Formula: Area of parallelogram / length of base = height (distance)
    new Float:len = xs_vec_len(AB);
    if (len == 0.0) return 9999.0;
    
    return xs_vec_len(area) / len;
}
