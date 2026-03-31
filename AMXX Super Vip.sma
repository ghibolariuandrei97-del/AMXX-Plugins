#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fun>
#include <hamsandwich>
#include <fakemeta>

#define VIP_FLAG ADMIN_LEVEL_H // Flag 't'

// Offsets
#define m_flProgressBar 100
#define m_fClientMapZone 235
#define m_bIsDefusing 383

new g_cvar_vip_all, g_cvar_fly_speed, g_cvar_vip_hp;
new Float:g_saved_origin[33][3];
new bool:g_has_saved[33];
new bool:g_is_flying[33];

public plugin_init() {
    register_plugin("AMXX Super VIP", "1.0", "AI");

    g_cvar_vip_all = register_cvar("amx_vip_all", "0");
    g_cvar_fly_speed = register_cvar("amx_vip_fly_speed", "600");
    g_cvar_vip_hp = register_cvar("amx_vip_hp", "150");

    register_clcmd("say /save", "cmd_save");
    register_clcmd("say /load", "cmd_load");
    register_clcmd("say /revive", "cmd_revive");
    register_clcmd("say", "handle_say");

    RegisterHam(Ham_Spawn, "player", "fw_PlayerSpawn", 1);
    RegisterHam(Ham_TakeDamage, "player", "fw_TakeDamage");
    
    register_forward(FM_CmdStart, "fw_CmdStart");
}

bool:is_user_vip(id) {
    if (get_pcvar_num(g_cvar_vip_all) == 1) return true;
    if (!is_user_connected(id)) return false;
    return (get_user_flags(id) & VIP_FLAG) ? true : false;
}

// --- 1. FLY (SOLID) & INSTANT ACTIONS ---
public fw_CmdStart(id, uc_handle, seed) {
    if (!is_user_alive(id) || !is_user_vip(id)) return FMRES_IGNORED;

    // FLY LOGIC (T-Key / Impulse 201)
    static impulse; impulse = get_uc(uc_handle, UC_Impulse);
    if (impulse == 201) {
        g_is_flying[id] = !g_is_flying[id];
        
        if (g_is_flying[id]) {
            set_pev(id, pev_movetype, MOVETYPE_FLY); 
            client_print(id, print_center, "[VIP] Fly Mode: ENABLED!");
        } else {
            set_pev(id, pev_movetype, MOVETYPE_WALK);
            client_print(id, print_center, "[VIP] Fly Mode: DISABLED!");
        }
        set_uc(uc_handle, UC_Impulse, 0); 
    }

    if (g_is_flying[id]) {
        new Float:vec[3]; velocity_by_aim(id, get_pcvar_num(g_cvar_fly_speed), vec);
        set_pev(id, pev_velocity, vec);
    }

    static button; button = get_uc(uc_handle, UC_Buttons);

    // Instant Defuse
    if ((button & IN_USE) && get_pdata_int(id, m_bIsDefusing)) {
        set_pdata_float(id, m_flProgressBar, 0.01);
    }

    // Instant Plant (Force site zone)
    if ((button & IN_ATTACK) && get_user_weapon(id) == CSW_C4) {
        set_pdata_int(id, m_fClientMapZone, get_pdata_int(id, m_fClientMapZone) | (1<<1));
        set_pdata_float(id, m_flProgressBar, 0.01);
    }

    return FMRES_IGNORED;
}

// --- 2. NO FALL DAMAGE ---
public fw_TakeDamage(victim, inflictor, attacker, Float:damage, damagebits) {
    if (is_user_connected(victim) && is_user_vip(victim) && (damagebits & DMG_FALL)) {
        return HAM_SUPERCEDE;
    }
    return HAM_IGNORED;
}

// --- 3. SELF-ONLY REVIVE ---
public cmd_revive(id) {
    if (!is_user_vip(id)) return PLUGIN_HANDLED;

    if (is_user_alive(id)) {
        client_print_color(id, id, "^4[VIP] ^1You are already alive!");
        return PLUGIN_HANDLED;
    }

    // Respawn the VIP
    ExecuteHamB(Ham_CS_RoundRespawn, id);
    
    // Global notification
    client_print_color(0, id, "^4[VIP] ^3%n ^1has revived himself!", id);

    return PLUGIN_HANDLED;
}

// --- 4. WEAPON MENU & SPAWN HP ---
public fw_PlayerSpawn(id) {
    if (is_user_alive(id) && is_user_vip(id)) {
        g_is_flying[id] = false;
        set_pev(id, pev_movetype, MOVETYPE_WALK);
        
        // Give Health from CVAR
        set_user_health(id, get_pcvar_num(g_cvar_vip_hp));
        
        set_task(0.3, "show_vip_menu", id);
    }
}

public show_vip_menu(id) {
    if (!is_user_alive(id)) return;
    new menu = menu_create("\yVIP Weapon Packs:", "menu_handler");
    menu_additem(menu, "Pack 1 M4A1 + All Nades", "1");
    menu_additem(menu, "Pack 2 AK47 + All Nades", "2");
    menu_additem(menu, "Pack 3 AWP + All Nades", "3");
    menu_additem(menu, "Pack 4 MP5 + All Nades", "4");
    menu_additem(menu, "Pack 5 M249 + All Nades", "5");
    menu_display(id, menu, 0);
}

public menu_handler(id, menu, item) {
    if (item == MENU_EXIT || !is_user_alive(id)) { menu_destroy(menu); return PLUGIN_HANDLED; }

    new bool:hasC4 = (user_has_weapon(id, CSW_C4)) ? true : false;
    strip_user_weapons(id);
    give_item(id, "weapon_knife");
    if (hasC4) give_item(id, "weapon_c4");

    // Standard Nades + Deagle
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
        pev(id, pev_origin, g_saved_origin[id]); g_has_saved[id] = true;
        client_print_color(id, id, "^4[VIP] ^1Position ^3Saved^1.");
    }
    return PLUGIN_HANDLED;
}

public cmd_load(id) {
    if (is_user_vip(id) && is_user_alive(id) && g_has_saved[id]) {
        set_pev(id, pev_origin, g_saved_origin[id]);
        client_print_color(id, id, "^4[VIP] ^1Position ^3Loaded^1.");
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
