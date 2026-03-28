#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <hamsandwich>
#include <xs>

#define PLUGIN "Force Powers"
#define VERSION "1.0"
#define AUTHOR "AI"

#define MAX_ENERGY 100.0
#define HOLD_DISTANCE 150.0  // Distance the object stays from you

enum { FORCE_PUSH = 1, FORCE_PULL };

new Float:g_fEnergy[MAX_PLAYERS + 1], Float:g_fLastUse[MAX_PLAYERS + 1];
new bool:g_bPushing[MAX_PLAYERS + 1], bool:g_bPulling[MAX_PLAYERS + 1];
new g_iHeldEntity[MAX_PLAYERS + 1], g_iIsBeingHeldBy[MAX_PLAYERS + 1];
new g_iBeamSprite, g_msgStatusText;

// CVARs
new g_pcvar_push_pwr, g_pcvar_pull_pwr, g_pcvar_max_dist;
new g_pcvar_recharge, g_pcvar_cost, g_pcvar_hold_drain;
new g_pcvar_world_interact; // The "Push off walls" toggle

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    
    g_pcvar_push_pwr = register_cvar("force_push_power", "1000.0");
    g_pcvar_pull_pwr = register_cvar("force_pull_power", "1000.0");
    g_pcvar_max_dist = register_cvar("force_max_distance", "1024.0");
    g_pcvar_recharge = register_cvar("force_recharge_rate", "12.0");
    g_pcvar_cost = register_cvar("force_usage_cost", "15.0");
    g_pcvar_hold_drain = register_cvar("force_hold_drain", "25.0"); // Per second
    g_pcvar_world_interact = register_cvar("force_world_interact", "1"); // 1=On, 0=Off
    
    register_clcmd("+push", "cmd_push"); register_clcmd("-push", "cmd_stop");
    register_clcmd("+pull", "cmd_pull"); register_clcmd("-pull", "cmd_stop");
    register_clcmd("+hold", "cmd_hold"); register_clcmd("-hold", "cmd_release_hold");
    
    g_msgStatusText = get_user_msgid("StatusText");
    
    register_forward(FM_CmdStart, "fw_CmdStart");
    set_task(0.1, "task_logic", .flags = "b");
}

public plugin_precache() { g_iBeamSprite = precache_model("sprites/laserbeam.spr"); }

public client_putinserver(id) { g_fEnergy[id] = MAX_ENERGY; reset_user(id); }
public client_disconnected(id) { cmd_release_hold(id); }

reset_user(id) {
    g_bPushing[id] = false; g_bPulling[id] = false;
    if(g_iHeldEntity[id]) cmd_release_hold(id);
}

// Input Handling
public cmd_push(id) { if(is_user_alive(id)) g_bPushing[id] = true; return PLUGIN_HANDLED; }
public cmd_pull(id) { if(is_user_alive(id)) g_bPulling[id] = true; return PLUGIN_HANDLED; }
public cmd_stop(id) { g_bPushing[id] = false; g_bPulling[id] = false; return PLUGIN_HANDLED; }

public cmd_hold(id) {
    if(!is_user_alive(id) || g_fEnergy[id] < get_pcvar_float(g_pcvar_cost)) return PLUGIN_HANDLED;

    new iEnt = get_user_aiming_ent(id);
    if(is_movable(iEnt)) {
        g_iHeldEntity[id] = iEnt;
        if(is_user_alive(iEnt)) g_iIsBeingHeldBy[iEnt] = id;
        emit_sound(id, CHAN_ITEM, "weapons/mine_activate.wav", 0.6, ATTN_NORM, 0, PITCH_NORM);
    }
    return PLUGIN_HANDLED;
}

public cmd_release_hold(id) {
    new iEnt = g_iHeldEntity[id];
    if(iEnt > 0) {
        if(is_user_alive(iEnt)) g_iIsBeingHeldBy[iEnt] = 0;
        g_iHeldEntity[id] = 0;
    }
    return PLUGIN_HANDLED;
}

public fw_CmdStart(id, uc_handle) {
    if(!is_user_alive(id)) return;

    // 1. Block attack if being held
    if(g_iIsBeingHeldBy[id] > 0) {
        new iButtons = get_uc(uc_handle, UC_Buttons);
        iButtons &= ~(IN_ATTACK | IN_ATTACK2);
        set_uc(uc_handle, UC_Buttons, iButtons);
        return;
    }

    // 2. Handle Push/Pull
    if(get_gametime() - g_fLastUse[id] < 0.2) return;
    if(g_bPushing[id]) handle_force(id, FORCE_PUSH);
    else if(g_bPulling[id]) handle_force(id, FORCE_PULL);
}

handle_force(id, type) {
    new Float:fCost = get_pcvar_float(g_pcvar_cost);
    if(g_fEnergy[id] < fCost) return;

    if(apply_force_logic(id, (type == FORCE_PUSH ? 1 : -1))) {
        g_fEnergy[id] -= fCost;
        g_fLastUse[id] = get_gametime();
        emit_sound(id, CHAN_WEAPON, (type == FORCE_PUSH ? "weapons/glauncher.wav" : "weapons/mine_activate.wav"), 0.5, ATTN_NORM, 0, PITCH_NORM);
    }
}

bool:apply_force_logic(id, dir) {
    new Float:vStart[3], Float:vEnd[3], Float:vAim[3], Float:vOfs[3];
    get_entvar(id, var_origin, vStart); get_entvar(id, var_view_ofs, vOfs);
    xs_vec_add(vStart, vOfs, vStart); velocity_by_aim(id, 1, vAim);
    
    xs_vec_mul_scalar(vAim, get_pcvar_float(g_pcvar_max_dist), vEnd);
    xs_vec_add(vStart, vEnd, vEnd);

    new tr = create_tr2();
    engfunc(EngFunc_TraceLine, vStart, vEnd, DONT_IGNORE_MONSTERS, id, tr);
    new iTarget = get_tr2(tr, TR_pHit);
    new Float:vHit[3]; get_tr2(tr, TR_vecEndPos, vHit);
    free_tr2(tr);

    draw_beam(vStart, vHit, (dir == 1 ? {0, 100, 255} : {255, 0, 0}));

    if(!is_movable(iTarget)) {
        // Only propel player if CVAR is enabled
        if(get_pcvar_num(g_pcvar_world_interact) == 1) {
            new Float:vVel[3], Float:fPower = (dir == 1 ? get_pcvar_float(g_pcvar_push_pwr) : get_pcvar_float(g_pcvar_pull_pwr));
            xs_vec_mul_scalar(vAim, -(fPower * 0.8) * float(dir), vVel);
            if(dir == 1 && vAim[2] < -0.5) vVel[2] += 250.0;
            set_entvar(id, var_velocity, vVel);
        }
    } else {
        new Float:vVel[3], Float:fPower = (dir == 1 ? get_pcvar_float(g_pcvar_push_pwr) : get_pcvar_float(g_pcvar_pull_pwr));
        xs_vec_mul_scalar(vAim, fPower * float(dir), vVel);
        vVel[2] += 150.0;
        set_entvar(iTarget, var_velocity, vVel);
    }
    return true;
}

public task_logic() {
    new Float:fRecharge = get_pcvar_float(g_pcvar_recharge) * 0.1;
    new Float:fHoldDrain = get_pcvar_float(g_pcvar_hold_drain) * 0.1;

    for(new i = 1; i <= MaxClients; i++) {
        if(!is_user_alive(i)) continue;

        if(g_iHeldEntity[i] > 0) {
            // Process Force Hold
            if(g_fEnergy[i] > fHoldDrain) {
                g_fEnergy[i] -= fHoldDrain;
                update_held_entity(i);
            } else {
                cmd_release_hold(i); // Out of energy
            }
        } else if(g_fEnergy[i] < MAX_ENERGY) {
            g_fEnergy[i] = floatmin(MAX_ENERGY, g_fEnergy[i] + fRecharge);
        }

        update_hud(i);
    }
}

update_held_entity(id) {
    new iEnt = g_iHeldEntity[id];
    if(!is_entity(iEnt)) { cmd_release_hold(id); return; }

    new Float:vOrigin[3], Float:vAim[3], Float:vTarget[3], Float:vViewOfs[3];
    get_entvar(id, var_origin, vOrigin);
    get_entvar(id, var_view_ofs, vViewOfs);
    velocity_by_aim(id, 1, vAim);

    // Calculate point in front of player
    vTarget[0] = vOrigin[0] + vViewOfs[0] + vAim[0] * HOLD_DISTANCE;
    vTarget[1] = vOrigin[1] + vViewOfs[1] + vAim[1] * HOLD_DISTANCE;
    vTarget[2] = vOrigin[2] + vViewOfs[2] + vAim[2] * HOLD_DISTANCE;

    // Smooth movement: Set velocity toward target point instead of teleporting
    new Float:vEntOrigin[3], Float:vNewVel[3];
    get_entvar(iEnt, var_origin, vEntOrigin);
    xs_vec_sub(vTarget, vEntOrigin, vNewVel);
    xs_vec_mul_scalar(vNewVel, 10.0, vNewVel); // Pull speed multiplier
    
    set_entvar(iEnt, var_velocity, vNewVel);
    set_entvar(iEnt, var_movetype, MOVETYPE_FLY); // Prevent gravity from dropping them
    
    // Visual tether
    draw_beam(vOrigin, vEntOrigin, {0, 255, 100});
}

// Helpers
bool:is_movable(ent) {
    if(ent <= 0 || !is_entity(ent)) return false;
    new szClass[32]; get_entvar(ent, var_classname, szClass, 31);
    if(equal(szClass, "worldspawn") || equal(szClass, "func_wall")) return false;
    return true; 
}

get_user_aiming_ent(id) {
    new Float:vStart[3], Float:vEnd[3], Float:vAim[3], Float:vOfs[3];
    get_entvar(id, var_origin, vStart); get_entvar(id, var_view_ofs, vOfs);
    xs_vec_add(vStart, vOfs, vStart); velocity_by_aim(id, 1, vAim);
    xs_vec_mul_scalar(vAim, get_pcvar_float(g_pcvar_max_dist), vEnd);
    xs_vec_add(vStart, vEnd, vEnd);

    new tr = create_tr2();
    engfunc(EngFunc_TraceLine, vStart, vEnd, DONT_IGNORE_MONSTERS, id, tr);
    new iEnt = get_tr2(tr, TR_pHit);
    free_tr2(tr);
    return iEnt;
}

update_hud(id) {
    new szMsg[64];
    formatex(szMsg, 63, "Force: %d%% %s", floatround(g_fEnergy[id]), (g_iHeldEntity[id] ? "[HOLDING]" : ""));
    message_begin(MSG_ONE_UNRELIABLE, g_msgStatusText, _, id);
    write_byte(0); write_string(szMsg); message_end();
}

draw_beam(Float:start[3], Float:end[3], color[3]) {
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMPOINTS);
    engfunc(EngFunc_WriteCoord, start[0]); engfunc(EngFunc_WriteCoord, start[1]); engfunc(EngFunc_WriteCoord, start[2]);
    engfunc(EngFunc_WriteCoord, end[0]); engfunc(EngFunc_WriteCoord, end[1]); engfunc(EngFunc_WriteCoord, end[2]);
    write_short(g_iBeamSprite); write_byte(0); write_byte(15); write_byte(1); write_byte(10); write_byte(0);
    write_byte(color[0]); write_byte(color[1]); write_byte(color[2]); write_byte(150); write_byte(0);
    message_end();
}
