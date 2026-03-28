#include <amxmodx>
#include <reapi>
#include <hamsandwich>
#include <fakemeta>
#include <xs>

#define PLUGIN "E-Key Pickup (Optimized)"
#define VERSION "16.0"
#define AUTHOR "Gemini"

#define TASK_HUD 1000

// Offsets
#define m_flNextPickup 36
#define m_iId 43
#define m_iItem 34 
#define m_iClip 51
#define m_rgpPlayerItems_slot0 34 

// --- GLOBAL CONSTANTS ---

// Armoury Data
new const ARMOURY_NAMES[][] = { 
    "MP5", "TMP", "P90", "MAC10", "AK47", "SG552", "M4A1", "AUG", "SCOUT", 
    "AWP", "G3SG1", "SG550", "M249", "M3", "XM1014", "FLASHBANG", "HEGRENADE", 
    "SMOKE", "ARMOR", "ARMOR+HELMET", "SHIELD" 
};

new const ARMOURY_FULL[][] = { 
    "weapon_mp5navy", "weapon_tmp", "weapon_p90", "weapon_mac10", "weapon_ak47", 
    "weapon_sg552", "weapon_m4a1", "weapon_aug", "weapon_scout", "weapon_awp", 
    "weapon_g3sg1", "weapon_sg550", "weapon_m249", "weapon_m3", "weapon_xm1014", 
    "weapon_flashbang", "weapon_hegrenade", "weapon_smokegrenade", "item_kevlar", 
    "item_assaultsuit", "weapon_shield" 
};

// Weapon Categorization
new const PRIMARY_WEAPONS[][] = { 
    "m4a1", "ak47", "awp", "mp5", "p90", "m3", "xm1014", "scout", "aug", 
    "sg552", "famas", "galil", "sg550", "g3sg1", "m249" 
};

new const SECONDARY_WEAPONS[][] = { 
    "deagle", "usp", "glock", "p228", "elite", "fiveseven" 
};

new g_pcvar_distance;

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    g_pcvar_distance = register_cvar("amx_pickup_dist", "300.0");
    
    RegisterHam(Ham_Spawn, "player", "fw_PlayerSpawn_Post", 1);
    RegisterHam(Ham_Killed, "player", "fw_PlayerKilled_Post", 1);
    register_forward(FM_CmdStart, "fwd_CmdStart");
}

// --- HUD & BUTTON LOGIC ---

public fw_PlayerSpawn_Post(id) {
    if (!is_user_alive(id)) return;
    remove_task(id + TASK_HUD);
    set_task(0.1, "weapon_hud_task", id + TASK_HUD, _, _, "b");
}

public fw_PlayerKilled_Post(id) {
    remove_task(id + TASK_HUD);
}

public weapon_hud_task(id) {
    id -= TASK_HUD;
    if (!is_user_alive(id)) return;

    new ent = find_best_weapon(id);
    if (pev_valid(ent)) {
        static weapon_name[32];
        get_clean_weapon_name(ent, weapon_name, charsmax(weapon_name));

        set_hudmessage(255, 255, 255, -1.0, 0.6, 0, 0.0, 0.15, 0.0, 0.0, -1);
        show_hudmessage(id, "Press [E] to pick up %s", weapon_name);
    }
}

public fwd_CmdStart(id, uc_handle, seed) {
    if (!is_user_alive(id)) return FMRES_IGNORED;

    static button, oldbutton;
    button = get_uc(uc_handle, UC_Buttons);
    oldbutton = pev(id, pev_oldbuttons);

    if ((button & IN_USE) && !(oldbutton & IN_USE)) {
        new ent = find_best_weapon(id);
        if (pev_valid(ent)) {
            transfer_weapon(id, ent);
        }
    }
    return FMRES_IGNORED;
}

// --- WEAPON TRANSFER LOGIC ---

stock transfer_weapon(id, ent) {
    static classname[32], weapon_fullname[32];
    pev(ent, pev_classname, classname, charsmax(classname));

    if (equal(classname, "weaponbox")) {
        new weapon_ent = get_weapon_in_box(ent);
        if (pev_valid(weapon_ent)) {
            pev(weapon_ent, pev_classname, weapon_fullname, charsmax(weapon_fullname));
            
            new iClip = get_pdata_int(weapon_ent, m_iClip, 4);
            new wid = get_pdata_int(weapon_ent, m_iId, 4);
            new InventorySlotType:slot = rg_get_weapon_info(WeaponIdType:wid, WI_SLOT);
            
            rg_drop_items_by_slot(id, slot);
            rg_give_item(id, weapon_fullname, GT_APPEND);
            
            new new_wep = -1;
            while ((new_wep = engfunc(EngFunc_FindEntityByString, new_wep, "classname", weapon_fullname)) != 0) {
                if (pev(new_wep, pev_owner) == id) {
                    set_pdata_int(new_wep, m_iClip, iClip, 4);
                    break;
                }
            }
            set_pev(ent, pev_flags, pev(ent, pev_flags) | FL_KILLME);
        }
    } else if (equal(classname, "armoury_entity")) {
        get_clean_weapon_name(ent, weapon_fullname, charsmax(weapon_fullname), true);
        
        if (is_primary(weapon_fullname)) rg_drop_items_by_slot(id, PRIMARY_WEAPON_SLOT);
        else if (is_secondary(weapon_fullname)) rg_drop_items_by_slot(id, PISTOL_SLOT);

        rg_give_item(id, weapon_fullname, GT_APPEND);
        
        set_pev(ent, pev_effects, pev(ent, pev_effects) | EF_NODRAW);
        set_pev(ent, pev_solid, SOLID_NOT);
        set_task(20.0, "respawn_armoury", ent);
    }
}

public respawn_armoury(ent) {
    if (pev_valid(ent)) {
        set_pev(ent, pev_effects, pev(ent, pev_effects) & ~EF_NODRAW);
        set_pev(ent, pev_solid, SOLID_TRIGGER);
    }
}

// --- HELPER FUNCTIONS ---

stock get_weapon_in_box(box_ent) {
    for (new i = 0; i < 6; i++) {
        new weapon = get_pdata_cbase(box_ent, m_rgpPlayerItems_slot0 + i, 4);
        if (pev_valid(weapon)) return weapon;
    }
    return -1;
}

stock find_best_weapon(id) {
    static Float:origin[3], Float:view_ofs[3], Float:v_forward[3], Float:v_angle[3];
    static Float:ent_origin[3], Float:vec_to_ent[3];
    
    pev(id, pev_origin, origin);
    pev(id, pev_view_ofs, view_ofs);
    xs_vec_add(origin, view_ofs, origin);
    
    pev(id, pev_v_angle, v_angle);
    angle_vector(v_angle, ANGLEVECTOR_FORWARD, v_forward);

    new Float:max_dist = get_pcvar_float(g_pcvar_distance);
    new best_ent = -1;
    new Float:best_dot = 0.85;

    new ent = -1;
    while ((ent = engfunc(EngFunc_FindEntityInSphere, ent, origin, max_dist)) != 0) {
        if (!pev_valid(ent) || (pev(ent, pev_effects) & EF_NODRAW)) continue;

        static classname[32];
        pev(ent, pev_classname, classname, charsmax(classname));
        
        if (equal(classname, "weaponbox") || equal(classname, "armoury_entity")) {
            pev(ent, pev_origin, ent_origin);
            xs_vec_sub(ent_origin, origin, vec_to_ent);
            xs_vec_normalize(vec_to_ent, vec_to_ent);
            
            new Float:dot = xs_vec_dot(v_forward, vec_to_ent);
            if (dot > best_dot) {
                best_dot = dot;
                best_ent = ent;
            }
        }
    }
    return best_ent;
}

stock get_clean_weapon_name(ent, name[], len, bool:full_name = false) {
    static classname[32];
    pev(ent, pev_classname, classname, charsmax(classname));

    if (equal(classname, "weaponbox")) {
        new weapon = get_weapon_in_box(ent);
        if (pev_valid(weapon)) {
            pev(weapon, pev_classname, name, len);
            if (!full_name) {
                replace(name, len, "weapon_", "");
                for(new i = 0; name[i] != '^0'; i++) { if('a' <= name[i] <= 'z') name[i] -= 32; }
            }
        } else copy(name, len, "WEAPON");
    } else if (equal(classname, "armoury_entity")) {
        new type = get_pdata_int(ent, m_iItem, 4); 
        if (0 <= type < sizeof(ARMOURY_NAMES)) {
            copy(name, len, full_name ? ARMOURY_FULL[type] : ARMOURY_NAMES[type]);
        }
    }
}

// Optimized Category Checks
bool:is_primary(const name[]) {
    for (new i = 0; i < sizeof(PRIMARY_WEAPONS); i++) {
        if (containi(name, PRIMARY_WEAPONS[i]) != -1) return true;
    }
    return false;
}

bool:is_secondary(const name[]) {
    for (new i = 0; i < sizeof(SECONDARY_WEAPONS); i++) {
        if (containi(name, SECONDARY_WEAPONS[i]) != -1) return true;
    }
    return false;
}
