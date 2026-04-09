/* 
* CS 1.6 AMXX Plugin: Bullet Reflection + Aim Helper (v1.0 - Customizable)
* Author: AI Studio Build
* Description: Reflects bullets with damage, adds a pool-style aim helper, autoshot, and user commands.
*/

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <xs>

#define PLUGIN "Bullet Reflection & Aim Helper"
#define VERSION "1.0"
#define AUTHOR "AI Studio"

#define MAX_REFLECTIONS 2
#define BEAM_LIFE 2 // 0.2s
#define UPDATE_FREQ 0.25 // Optimized frequency

new g_mSpriteBeam;
new Float:g_fLastUpdate[33];
new Float:g_vLastAngle[33][3];
new bool:g_bUserHelper[33];
new bool:g_bUserAutoShot[33];
new bool:g_bInReflect; // Guard against recursion spikes

// Path storage for optimization
new Float:g_fPathPoints[33][MAX_REFLECTIONS + 2][3];
new g_iPathCount[33];
new bool:g_bPathHitPlayer[33];

// CVars
new pCvarEnable, pCvarHelper, pCvarDamage, pCvarTrails, pCvarMaxBounces, pCvarAutoShot;
new pCvarTrailX, pCvarTrailY; // Custom colors

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    
    pCvarEnable = register_cvar("amx_reflect_enable", "1");
    pCvarHelper = register_cvar("amx_reflect_helper", "1");
    pCvarDamage = register_cvar("amx_reflect_damage", "1");
    pCvarTrails = register_cvar("amx_reflect_trails", "1");
    pCvarMaxBounces = register_cvar("amx_reflect_bounces", "2");
    pCvarAutoShot = register_cvar("amx_reflect_autoshot", "0");
    
    // Trail colors (Format: "R G B")
    pCvarTrailX = register_cvar("amx_reflect_trail_x", "0 255 0"); // Hit color (Green)
    pCvarTrailY = register_cvar("amx_reflect_trail_y", "255 0 0"); // No-hit color (Red)
    
    RegisterHam(Ham_TraceAttack, "worldspawn", "fw_TraceAttack_Post", 1);
    RegisterHam(Ham_TraceAttack, "func_wall", "fw_TraceAttack_Post", 1);
    RegisterHam(Ham_TraceAttack, "func_door", "fw_TraceAttack_Post", 1);
    RegisterHam(Ham_TraceAttack, "func_door_rotating", "fw_TraceAttack_Post", 1);
    RegisterHam(Ham_TraceAttack, "func_breakable", "fw_TraceAttack_Post", 1);
    
    register_clcmd("say /pool", "cmd_toggle_pool");
    register_clcmd("say_team /pool", "cmd_toggle_pool");
    register_clcmd("say /autopool", "cmd_toggle_autopool");
    register_clcmd("say_team /autopool", "cmd_toggle_autopool");
    
    register_forward(FM_PlayerPostThink, "fw_PlayerPostThink");
}

public plugin_precache() {
    g_mSpriteBeam = precache_model("sprites/laserbeam.spr");
}

public client_putinserver(id) {
    g_bUserHelper[id] = true;
    g_bUserAutoShot[id] = true;
    xs_vec_set(g_vLastAngle[id], 0.0, 0.0, 0.0);
}

public cmd_toggle_pool(id) {
    g_bUserHelper[id] = !g_bUserHelper[id];
    client_print_color(id, print_team_default, "^4[Reflect]^1 Aim helper is now %s", g_bUserHelper[id] ? "^3ENABLED" : "^1DISABLED");
    return PLUGIN_HANDLED;
}

public cmd_toggle_autopool(id) {
    g_bUserAutoShot[id] = !g_bUserAutoShot[id];
    client_print_color(id, print_team_default, "^4[Reflect]^1 Autoshot is now %s", g_bUserAutoShot[id] ? "^3ENABLED" : "^1DISABLED");
    return PLUGIN_HANDLED;
}

public fw_PlayerPostThink(id) {
    if (!get_pcvar_num(pCvarEnable)) return;
    if (!is_user_alive(id) || is_user_bot(id)) return;
    
    // Load Balancing: Spread processing across frames (4 frames cycle)
    static frame_counter;
    if ((id + frame_counter++) % 4 != 0) {
        // Still process autoshot on cached data for responsiveness
        if (g_bPathHitPlayer[id] && get_pcvar_num(pCvarAutoShot) && g_bUserAutoShot[id]) {
            set_pev(id, pev_button, pev(id, pev_button) | IN_ATTACK);
        }
        return;
    }
    
    static wpId; wpId = get_user_weapon(id);
    if (wpId == 2 || wpId == 6 || wpId == 24 || wpId == 25 || wpId == 29) return;
    
    static Float:fTime; fTime = get_gametime();
    if (fTime - g_fLastUpdate[id] < UPDATE_FREQ) return;

    static Float:vAngle[3]; pev(id, pev_v_angle, vAngle);
    
    // Fast Angle Check: Skip if mouse hasn't moved significantly
    static Float:diff[3]; xs_vec_sub(vAngle, g_vLastAngle[id], diff);
    if (xs_vec_dot(diff, diff) < 0.001) return;

    g_fLastUpdate[id] = fTime;
    xs_vec_copy(vAngle, g_vLastAngle[id]);
    
    if (g_bUserHelper[id] && get_pcvar_num(pCvarHelper)) {
        calculate_and_draw_path(id);
        
        if (g_bPathHitPlayer[id] && get_pcvar_num(pCvarAutoShot) && g_bUserAutoShot[id]) {
            set_pev(id, pev_button, pev(id, pev_button) | IN_ATTACK);
        }
    }
}

public fw_TraceAttack_Post(victim, attacker, Float:damage, Float:direction[3], tracehandle, damagebits) {
    #pragma unused victim, damagebits
    
    // CRITICAL: Guard against recursion spikes from reflected bullets
    if (g_bInReflect) return HAM_IGNORED;
    if (!get_pcvar_num(pCvarEnable)) return HAM_IGNORED;
    if (!is_user_connected(attacker)) return HAM_IGNORED;

    static Float:endPos[3], Float:planeNormal[3];
    get_tr2(tracehandle, TR_vecEndPos, endPos);
    get_tr2(tracehandle, TR_vecPlaneNormal, planeNormal);

    static Float:reflection[3];
    static Float:dotProduct; dotProduct = xs_vec_dot(direction, planeNormal);
    
    if (dotProduct < 0.0) {
        xs_vec_mul_scalar(planeNormal, 2.0 * dotProduct, reflection);
        xs_vec_sub(direction, reflection, reflection);
        
        g_bInReflect = true; // Lock
        reflect_bullet(attacker, endPos, reflection, 1, damage);
        g_bInReflect = false; // Unlock
    }

    return HAM_IGNORED;
}

reflect_bullet(attacker, Float:start[3], Float:dir[3], count, Float:damage) {
    if (count > get_pcvar_num(pCvarMaxBounces)) return;

    static Float:end[3];
    xs_vec_mul_scalar(dir, 8192.0, end);
    xs_vec_add(start, end, end);

    engfunc(EngFunc_TraceLine, start, end, DONT_IGNORE_MONSTERS, attacker, 0);

    static Float:fraction;
    get_tr2(0, TR_flFraction, fraction);

    if (fraction < 1.0) {
        static Float:hitPos[3], Float:normal[3];
        get_tr2(0, TR_vecEndPos, hitPos);
        get_tr2(0, TR_vecPlaneNormal, normal);
        
        static pHit; pHit = get_tr2(0, TR_pHit);
        
        if (get_pcvar_num(pCvarDamage)) {
            if (is_user_alive(pHit) || (pev_valid(pHit) && pev(pHit, pev_takedamage) != DAMAGE_NO)) {
                // Teammate check
                if (!is_user_connected(pHit) || get_user_team(attacker) != get_user_team(pHit)) {
                    static tr_handle;
                    if (!tr_handle) tr_handle = create_tr2();
                    
                    engfunc(EngFunc_TraceLine, start, hitPos, DONT_IGNORE_MONSTERS, attacker, tr_handle);
                    ExecuteHamB(Ham_TraceAttack, pHit, attacker, damage, dir, tr_handle, DMG_BULLET);
                }
            }
        }

        if (get_pcvar_num(pCvarTrails)) {
            draw_laser(start, hitPos, 255, 255, 255, 100, 0);
        }

        static Float:nextDir[3];
        static Float:dot; dot = xs_vec_dot(dir, normal);
        if (dot < 0.0) {
            xs_vec_mul_scalar(normal, 2.0 * dot, nextDir);
            xs_vec_sub(dir, nextDir, nextDir);
            reflect_bullet(attacker, hitPos, nextDir, count + 1, damage);
        }
    }
}

calculate_and_draw_path(id) {
    static Float:start[3], Float:viewOfs[3], Float:vAngle[3], Float:dir[3];
    pev(id, pev_origin, start);
    pev(id, pev_view_ofs, viewOfs);
    xs_vec_add(start, viewOfs, start);
    pev(id, pev_v_angle, vAngle);
    angle_vector(vAngle, ANGLEVECTOR_FORWARD, dir);
    
    g_iPathCount[id] = 0;
    g_bPathHitPlayer[id] = false;
    xs_vec_copy(start, g_fPathPoints[id][0]);
    g_iPathCount[id]++;

    trace_path_recursive(id, start, dir, 0);

    static r, g, b, bright;
    static szColor[32], szR[8], szG[8], szB[8];
    
    if (g_bPathHitPlayer[id]) {
        get_pcvar_string(pCvarTrailX, szColor, charsmax(szColor));
    } else {
        get_pcvar_string(pCvarTrailY, szColor, charsmax(szColor));
    }
    
    parse(szColor, szR, charsmax(szR), szG, charsmax(szG), szB, charsmax(szB));
    r = str_to_num(szR);
    g = str_to_num(szG);
    b = str_to_num(szB);
    
    bright = g_bPathHitPlayer[id] ? 150 : 100;

    for (new i = 0; i < g_iPathCount[id] - 1; i++) {
        draw_laser(g_fPathPoints[id][i], g_fPathPoints[id][i+1], r, g, b, bright, id);
    }
}

trace_path_recursive(id, Float:start[3], Float:dir[3], count) {
    if (count > get_pcvar_num(pCvarMaxBounces)) return;

    static Float:end[3];
    xs_vec_mul_scalar(dir, 8192.0, end);
    xs_vec_add(start, end, end);

    engfunc(EngFunc_TraceLine, start, end, DONT_IGNORE_MONSTERS, id, 0);

    static Float:fraction;
    get_tr2(0, TR_flFraction, fraction);

    if (fraction < 1.0) {
        static Float:hitPos[3], Float:normal[3];
        get_tr2(0, TR_vecEndPos, hitPos);
        get_tr2(0, TR_vecPlaneNormal, normal);
        
        xs_vec_copy(hitPos, g_fPathPoints[id][g_iPathCount[id]]);
        g_iPathCount[id]++;

        static pHit; pHit = get_tr2(0, TR_pHit);
        if (is_user_alive(pHit)) {
            // Teammate check for aim helper and autoshot
            if (get_user_team(id) != get_user_team(pHit)) {
                g_bPathHitPlayer[id] = true;
                return;
            }
        }

        static Float:nextDir[3];
        static Float:dot; dot = xs_vec_dot(dir, normal);
        if (dot < 0.0) {
            xs_vec_mul_scalar(normal, 2.0 * dot, nextDir);
            xs_vec_sub(dir, nextDir, nextDir);
            trace_path_recursive(id, hitPos, nextDir, count + 1);
        }
    } else {
        xs_vec_copy(end, g_fPathPoints[id][g_iPathCount[id]]);
        g_iPathCount[id]++;
    }
}

draw_laser(Float:start[3], Float:end[3], r, g, b, bright, id) {
    if (id > 0) {
        message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, id);
    } else {
        message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    }
    
    write_byte(TE_BEAMPOINTS);
    engfunc(EngFunc_WriteCoord, start[0]);
    engfunc(EngFunc_WriteCoord, start[1]);
    engfunc(EngFunc_WriteCoord, start[2]);
    engfunc(EngFunc_WriteCoord, end[0]);
    engfunc(EngFunc_WriteCoord, end[1]);
    engfunc(EngFunc_WriteCoord, end[2]);
    write_short(g_mSpriteBeam);
    write_byte(0); write_byte(0); 
    write_byte(id > 0 ? 1 : BEAM_LIFE); 
    write_byte(id > 0 ? 3 : 5); 
    write_byte(0);
    write_byte(r); write_byte(g); write_byte(b); write_byte(bright);
    write_byte(0);
    message_end();
}
