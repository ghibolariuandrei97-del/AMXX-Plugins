#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fun>
#include <hamsandwich>
#include <fakemeta>

#define VIP_FLAG ADMIN_LEVEL_H 
#define TASK_VIP_MENU 1000

// Linux Memory Offsets
#define OFFSET_PLAYER_LINUX 5

// Offsets
#define m_fClientMapZone 235 
#define m_flProgressBar 100
#define m_bIsDefusing 383

new g_cvar_vip_all, g_cvar_fly_speed, g_cvar_vip_hp, g_cvar_knife_dmg;
new Float:g_saved_origin[33][3];
new bool:g_has_saved[33];
new bool:g_is_flying[33];

public plugin_init() {
    register_plugin("AMXX Super VIP", "1.3", "AI");

    g_cvar_vip_all = register_cvar("amx_vip_all", "0");
    g_cvar_fly_speed = register_cvar("amx_vip_fly_speed", "600");
    g_cvar_vip_hp = register_cvar("amx_vip_hp", "150");
    
    // Cvar is handled as a Float for the calculation
    g_cvar_knife_dmg = register_cvar("amx_vip_knifedamage", "75.0"); 

    register_clcmd("say /save", "cmd_save");
    register_clcmd("say /load", "cmd_load");
    register_clcmd("say /revive", "cmd_revive");
    register_clcmd("say", "handle_say");

    RegisterHam(Ham_Spawn, "player", "fw_PlayerSpawn", 1);
    
    // Using your requested Damage event for the Knife logic
    register_event("Damage", "event_Damage_Engine", "b", "2!0", "3=0", "4!0");
    
    // Pre-hook to block Fall Damage only
    RegisterHam(Ham_TakeDamage, "player", "fw_TakeDamage_Pre", 0);
    
    register_forward(FM_CmdStart, "fw_CmdStart");
}

bool:is_user_vip(id) {
    if (get_pcvar_num(g_cvar_vip_all) == 1) return true;
    if (!is_user_connected(id)) return false;
    return (get_user_flags(id) & VIP_FLAG) ? true : false;
}

// --- 1. KNIFE DAMAGE (VIA ENGINE EVENT) ---
public event_Damage_Engine(victim) {
    if (!is_user_alive(victim)) return;

    static attacker; attacker = get_user_attacker(victim);
    
    // Verify Attacker is VIP and using Knife
    if (is_user_connected(attacker) && is_user_vip(attacker)) {
        if (get_user_weapon(attacker) == CSW_KNIFE) {
            
            static Float:fHealth; 
            // Correct way to get Float without Tag Mismatch:
            pev(victim, pev_health, fHealth);
            
            static Float:fExtra; 
            fExtra = get_pcvar_float(g_cvar_knife_dmg);

            if (fHealth <= fExtra) {
                // If extra damage is lethal, force the kill
                ExecuteHamB(Ham_Killed, victim, attacker, 0);
            } else {
                // Manually set health (set_pev requires Float for pev_health)
                set_pev(victim, pev_health, fHealth - fExtra);
                client_print(attacker, print_center, "Knife Bonus: -%.0f HP", fExtra);
            }
        }
    }
}

// --- 2. FLY & INSTANT DEFUSE (FORCE ROUND END) ---
public fw_CmdStart(id, uc_handle, seed) {
    if (!is_user_alive(id) || !is_user_vip(id)) return FMRES_IGNORED;

    // FLY LOGIC
    static impulse; impulse = get_uc(uc_handle, UC_Impulse);
    if (impulse == 201) {
        g_is_flying[id] = !g_is_flying[id];
        set_pev(id, pev_movetype, g_is_flying[id] ? MOVETYPE_FLY : MOVETYPE_WALK);
        client_print(id, print_center, "[VIP] Fly Mode: %s!", g_is_flying[id] ? "ENABLED" : "DISABLED");
        set_uc(uc_handle, UC_Impulse, 0); 
    }

    if (g_is_flying[id]) {
        new Float:vec[3]; velocity_by_aim(id, get_pcvar_num(g_cvar_fly_speed), vec);
        set_pev(id, pev_velocity, vec);
    }

    static button; button = get_uc(uc_handle, UC_Buttons);

    // FORCED INSTANT DEFUSE (CT)
    if (cs_get_user_team(id) == CS_TEAM_CT && (button & IN_USE)) {
        new ent = -1;
        while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "grenade")) != 0) {
            static model[32]; pev(ent, pev_model, model, 31);
            if (containi(model, "w_c4.mdl") != -1) {
                
                static Float:origin[3], Float:bombOrigin[3];
                pev(id, pev_origin, origin);
                pev(ent, pev_origin, bombOrigin);
                
                if (get_distance_f(origin, bombOrigin) < 100.0) {
                    engfunc(EngFunc_RemoveEntity, ent); // Remove C4
                    set_pdata_float(id, m_flProgressBar, 0.0, OFFSET_PLAYER_LINUX);
                    
                    client_print_color(0, id, "^4[VIP] ^3%n ^1defused the bomb instantly!", id);
                    client_cmd(0, "spk ^"radio/ctwin^"");
                    
                    // Force Round End by eliminating Terrorists
                    new players[32], num, t_player;
                    get_players(players, num, "ae", "TERRORIST");
                    for(new i=0; i<num; i++) {
                        t_player = players[i];
                        ExecuteHamB(Ham_Killed, t_player, id, 0);
                    }
                }
            }
        }
    }

    // PLANT ANYWHERE (T)
    if (cs_get_user_team(id) == CS_TEAM_T && get_user_weapon(id) == CSW_C4 && (button & IN_ATTACK)) {
        set_pdata_int(id, m_fClientMapZone, get_pdata_int(id, m_fClientMapZone, OFFSET_PLAYER_LINUX) | (1<<1), OFFSET_PLAYER_LINUX);
        set_pdata_float(id, m_flProgressBar, 0.01, OFFSET_PLAYER_LINUX);
    }

    return FMRES_IGNORED;
}

// --- 3. NO FALL DAMAGE (PRE) ---
public fw_TakeDamage_Pre(victim, inflictor, attacker, Float:damage, damagebits) {
    if (is_user_connected(victim) && is_user_vip(victim) && (damagebits & DMG_FALL)) {
        return HAM_SUPERCEDE;
    }
    return HAM_IGNORED;
}

// --- 4. REVIVE, MENU, SPAWN ---
public cmd_revive(id) {
    if (!is_user_vip(id) || is_user_alive(id)) return PLUGIN_HANDLED;
    ExecuteHamB(Ham_CS_RoundRespawn, id);
    client_print_color(0, id, "^4[VIP] ^3%n ^1revived himself!", id);
    return PLUGIN_HANDLED;
}

public fw_PlayerSpawn(id) {
    if (is_user_alive(id) && is_user_vip(id)) {
        g_is_flying[id] = false;
        set_pev(id, pev_movetype, MOVETYPE_WALK);
        set_user_health(id, get_pcvar_num(g_cvar_vip_hp));
        set_task(0.3, "show_vip_menu", id + TASK_VIP_MENU);
    }
}

public show_vip_menu(taskid) {
    new id = taskid - TASK_VIP_MENU;
    if (!is_user_connected(id) || !is_user_alive(id)) return;
    
    new menu = menu_create("\yVIP Weapon Packs:", "menu_handler");
    menu_additem(menu, "Pack 1 M4A1 + All Nades", "1");
    menu_additem(menu, "Pack 2 AK47 + All Nades", "2");
    menu_additem(menu, "Pack 3 AWP + All Nades", "3");
    menu_additem(menu, "Pack 4 MP5 + All Nades", "4");
    menu_additem(menu, "Pack 5 M249 + All Nades", "5");
    menu_display(id, menu, 0);
}

public menu_handler(id, menu, item) {
    if (item == MENU_EXIT || !is_user_alive(id)) { 
        if (pev_valid(menu)) menu_destroy(menu); 
        return PLUGIN_HANDLED; 
    }
    
    new bool:hasC4 = (user_has_weapon(id, CSW_C4) != 0);
    
    strip_user_weapons(id);
    give_item(id, "weapon_knife");
    
    if (hasC4) {
        give_item(id, "weapon_c4");
        
        // --- FIX ICONITA BOMBA ---
        // Trimitem manual mesajul catre HUD pentru a afisa iconita verde de C4
        message_begin(MSG_ONE, get_user_msgid("StatusIcon"), {0,0,0}, id);
        write_byte(1);          // 1 = Afiseaza / 0 = Ascunde
        write_string("c4");     // Numele iconitei
        write_byte(0);          // Rosu
        write_byte(160);        // Verde (Verde clasic de C4)
        write_byte(0);          // Albastru
        message_end();
    }
    
    give_item(id, "weapon_deagle"); cs_set_user_bpammo(id, CSW_DEAGLE, 35);
    give_item(id, "weapon_hegrenade");
    give_item(id, "weapon_flashbang"); cs_set_user_bpammo(id, CSW_FLASHBANG, 2);
    give_item(id, "weapon_smokegrenade");
    
    switch(item) {
        case 0: { give_item(id, "weapon_m4a1"); cs_set_user_bpammo(id, CSW_M4A1, 90); }
        case 1: { give_item(id, "weapon_ak47"); cs_set_user_bpammo(id, CSW_AK47, 90); }
        case 2: { give_item(id, "weapon_awp"); cs_set_user_bpammo(id, CSW_AWP, 30); }
        case 3: { give_item(id, "weapon_mp5navy"); cs_set_user_bpammo(id, CSW_MP5NAVY, 120); }
        case 4: { give_item(id, "weapon_m249"); cs_set_user_bpammo(id, CSW_M249, 200); }
    }
    
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// --- 5. SAVE/LOAD & CHAT ---
public cmd_save(id) {
    if (is_user_vip(id) && is_user_alive(id)) {
        pev(id, pev_origin, g_saved_origin[id]); 
        g_has_saved[id] = true;
        client_print_color(id, id, "^4[VIP] ^1Position ^3Saved^1.");
    }
    return PLUGIN_HANDLED;
}

public cmd_load(id) {
    if (is_user_vip(id) && is_user_alive(id) && g_has_saved[id]) {
        static Float:origin[3];
        origin[0] = g_saved_origin[id][0];
        origin[1] = g_saved_origin[id][1];
        origin[2] = g_saved_origin[id][2];

        new tr = 0;
        engfunc(EngFunc_TraceHull, origin, origin, 0, HULL_HUMAN, id, tr);
        if (!get_tr2(tr, TR_StartSolid) && !get_tr2(tr, TR_AllSolid)) {
            set_pev(id, pev_origin, origin);
            client_print_color(id, id, "^4[VIP] ^1Position ^3Loaded^1.");
        }
    }
    return PLUGIN_HANDLED;
}

public handle_say(id) {
    if (!is_user_vip(id)) return PLUGIN_CONTINUE;
    new msg[192], name[32]; read_args(msg, 191); remove_quotes(msg);
    if (msg[0] == '/' || msg[0] == '!' || msg[0] == 0) return PLUGIN_CONTINUE;
    get_user_name(id, name, 31);
    client_print_color(0, id, "^4[--------------------------------------------------]");
    client_print_color(0, id, "^4[VIP] ^3%s^1 :  %s", name, msg);
    client_print_color(0, id, "^4[--------------------------------------------------]");
    return PLUGIN_HANDLED; 
}
