#include <amxmodx>
#include <amxmisc>
#include <fun>
#include <hamsandwich>
#include <nvault>
#include <fakemeta>
#include <engine>
#include <cstrike>

#define PLUGIN "Weapons With Levels"
#define VERSION "1.0"
#define AUTHOR "AIs"

#define MAX_WEAPONS 31
#define MAX_LEVEL 100
#define XP_PER_LEVEL 1000

new g_Vault
new g_WeaponXP[33][MAX_WEAPONS]
new g_PlayerName[33][32]

/* Cvar Pointers */
new p_DmgPerLvl, p_RecoilPerLvl, p_SpeedPerLvl, p_DmgProtection

new const g_WeaponNames[][] = { 
        "weapon_p228", "weapon_scout", "weapon_xm1014", "weapon_mac10", "weapon_aug", 
        "weapon_elite", "weapon_fiveseven", "weapon_ump45", "weapon_sg550", "weapon_galil", 
        "weapon_famas", "weapon_usp", "weapon_glock18", "weapon_awp", "weapon_mp5navy", 
        "weapon_m249", "weapon_m3", "weapon_m4a1", "weapon_tmp", "weapon_g3sg1", 
        "weapon_deagle", "weapon_sg552", "weapon_ak47", "weapon_p90" 
    }

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)
    
    p_DmgPerLvl = register_cvar("amx_weaponlevels_damage", "4.0")
    p_RecoilPerLvl = register_cvar("amx_weaponlevels_recoil", "1.0")
    p_SpeedPerLvl = register_cvar("amx_weaponlevels_speed", "2.0")
    p_DmgProtection = register_cvar("amx_weaponlevels_protection", "1.0") 
    
    register_event("Damage", "event_Damage_Engine", "b", "2!0", "3=0", "4!0")
    register_event("CurWeapon", "event_CurWeapon", "be", "1=1")
    register_event("DeathMsg", "event_DeathMsg", "a")
    
    for(new i = 0; i < sizeof g_WeaponNames; i++) {
        RegisterHam(Ham_Weapon_PrimaryAttack, g_WeaponNames[i], "fw_RecoilControl", 1)
    }
    
    register_clcmd("say /xp", "cmd_show_info")
    register_concmd("amx_givexp", "admin_add_xp", ADMIN_RCON, "<nume> <xp>")
    
    g_Vault = nvault_open("wl_data")
}

public client_putinserver(id) {
    get_user_name(id, g_PlayerName[id], 31)
    load_data(id)
}

public client_disconnected(id) {
    save_data(id)
}

// Detectare schimbare nume
public client_infochanged(id) {
    if (!is_user_connected(id)) return
    
    new newname[32], oldname[32]
    get_user_info(id, "name", newname, 31)
    get_user_name(id, oldname, 31)
    
    if (!equal(newname, oldname)) {
        save_data(id) // Salvam pe numele vechi
        
        // Resetam variabilele locale inainte de load
        for(new i = 0; i < MAX_WEAPONS; i++) g_WeaponXP[id][i] = 0
        
        copy(g_PlayerName[id], 31, newname)
        load_data(id) // Incarcam de pe numele nou (daca exista in vault)
    }
}

public event_Damage_Engine(victim) {
    new attacker = get_user_attacker(victim)
    if(!is_user_alive(victim)) return
    
    // --- 1. LOGICA DE PROTECTIE (Victima are arma de nivel mare) ---
    new v_wpn = get_user_weapon(victim)
    new v_level = get_level(g_WeaponXP[victim][v_wpn])
    
    if(v_level > 0) {
        new Float:prot_percent = float(v_level) * get_pcvar_float(p_DmgProtection)
        if(prot_percent > 0.0) {
            new Float:current_hp; pev(victim, pev_health, current_hp)
            new damage_received = read_data(2)
            
            // Calculam cat damage ar trebui sa "anulam"
            new Float:reduction = float(damage_received) * (prot_percent / 100.0)
            if(reduction > float(damage_received)) reduction = float(damage_received)
            
            // Adaugam HP inapoi (simularea protectiei)
            set_pev(victim, pev_health, current_hp + reduction)
        }
    }

    // --- 2. LOGICA DE EXTRA DAMAGE (Atacatorul are arma de nivel mare) ---
    if(!is_user_connected(attacker) || !is_user_alive(attacker) || victim == attacker) return
        
    new a_wpn = get_user_weapon(attacker)
    new a_level = get_level(g_WeaponXP[attacker][a_wpn])
    
    if(a_level > 0) {
        new damage_done = read_data(2)
        new Float:multiplier = (float(a_level) * get_pcvar_float(p_DmgPerLvl)) / 100.0
        new Float:extra_to_apply = float(damage_done) * multiplier
        
        if(extra_to_apply > 0.1) {
            new Float:vic_hp; pev(victim, pev_health, vic_hp)
            if(vic_hp - extra_to_apply <= 0.0) make_death(attacker, victim)
            else set_pev(victim, pev_health, vic_hp - extra_to_apply)
        }
    }
}

stock make_death(attacker, victim) {
    set_msg_block(get_user_msgid("DeathMsg"), BLOCK_ONCE)
    set_msg_block(get_user_msgid("ScoreInfo"), BLOCK_ONCE)
    user_kill(victim, 1)
    
    new wpn_id = get_user_weapon(attacker)
    new wpn_name[32]; get_weaponname(wpn_id, wpn_name, 31); replace(wpn_name, 31, "weapon_", "")
    
    message_begin(MSG_ALL, get_user_msgid("DeathMsg"))
    write_byte(attacker); write_byte(victim); write_byte(0); write_string(wpn_name); message_end()
}

public event_CurWeapon(id) {
    if(!is_user_alive(id)) return
    new level = get_level(g_WeaponXP[id][read_data(2)])
    set_user_maxspeed(id, 250.0 + (float(level) * get_pcvar_float(p_SpeedPerLvl)))
}

public event_DeathMsg() {
    new attacker = read_data(1), victim = read_data(2)
    
    if(!is_user_connected(attacker) || attacker == victim) return
    
    new wpn_id = get_user_weapon(attacker)
    
    if(wpn_id < MAX_WEAPONS) {
        g_WeaponXP[attacker][wpn_id] += 50
        
        new current_xp = g_WeaponXP[attacker][wpn_id]
        new level = get_level(current_xp)
        
        // Verificam daca tocmai a facut level up (daca XP-ul anterior era de nivel mai mic)
        if(level > get_level(current_xp - 50)) {
            new wpn_name[32]
            get_weaponname(wpn_id, wpn_name, 31)
            replace(wpn_name, 31, "weapon_", "")
            strtoupper(wpn_name) // Exemplu: AK47
            
            client_print_color(attacker, print_team_default, "^x04[WEAPON LEVELS]^x01 Felicitari! Ai acum Nivel ^x03%d^x01 pe ^x04%s^x01!", level, wpn_name)
        }


	save_data(attacker);
    }
}

public fw_RecoilControl(wpn_ent) {
    new id = get_pdata_cbase(wpn_ent, 41, 4)
    if(!is_user_alive(id)) return
    new level = get_level(g_WeaponXP[id][cs_get_weapon_id(wpn_ent)])
    if(level > 0) {
        new Float:punch[3]; pev(id, pev_punchangle, punch)
        new Float:red = 1.0 - (float(level) * (get_pcvar_float(p_RecoilPerLvl) / 100.0))
        punch[0] *= (red < 0.0 ? 0.0 : red); punch[1] *= (red < 0.0 ? 0.0 : red)
        set_pev(id, pev_punchangle, punch)
    }
}

public get_level(xp) {
    new lvl = xp / XP_PER_LEVEL
    return (lvl > MAX_LEVEL) ? MAX_LEVEL : lvl
}

public cmd_show_info(id) {
    new target = id; 

    // Verificăm dacă jucătorul este mort
    if (!is_user_alive(id)) {
        // pev_iuser1 stochează modul de spectator
        // pev_iuser2 stochează ID-ul jucătorului urmărit
        new spec_mode = pev(id, pev_iuser1);
        new spec_target = pev(id, pev_iuser2);

        // Dacă e spectator pe cineva (modurile 1, 2 sau 4)
        if (spec_mode > 0 && spec_target > 0) {
            target = spec_target;
        } else {
            client_print_color(id, print_team_default, "^x04[INFO]^x01 Trebuie să fii în viață sau spectator pe cineva pentru această comandă.");
            return PLUGIN_HANDLED;
        }
    }

    // Luăm arma curentă a țintei
    new wpn_id = get_user_weapon(target);
    
    // Verificăm dacă are o armă în mână (ID-ul 0 nu e valid)
    if (wpn_id <= 0) return PLUGIN_HANDLED;

    new level = get_level(g_WeaponXP[target][wpn_id]);
    new xp = g_WeaponXP[target][wpn_id];

    new wpn_name[32];
    get_weaponname(wpn_id, wpn_name, 31);
    replace(wpn_name, 31, "weapon_", "");
    strtoupper(wpn_name);

    new name[32];
    get_user_name(target, name, 31);

    // Mesajele merg la 'id' (cel care a scris), datele vin de la 'target'
    client_print_color(id, print_team_default, "^x04[INFO]^x01 Jucător: ^x03%s^x01 | Arma: ^x04%s", name, wpn_name);
    client_print_color(id, print_team_default, "^x04[XP]^x01 Level: ^x04%d/100^x01 | Progres: ^x03%d^x01 / ^x03%d^x01 XP", level, xp, (level + 1) * XP_PER_LEVEL);
    client_print_color(id, print_team_default, "^x04[STATS]^x01 DMG: ^x03+%d%%^x01 | PROT: ^x03-%d%%^x01 | Recoil: ^x03-%d%%", 
        level * get_pcvar_num(p_DmgPerLvl), 
        level * get_pcvar_num(p_DmgProtection), 
        level * get_pcvar_num(p_RecoilPerLvl));
        
    return PLUGIN_HANDLED;
}


public admin_add_xp(id, level, cid) {
    if(!cmd_access(id, level, cid, 3)) return PLUGIN_HANDLED
    new arg1[32], arg2[10]; read_argv(1, arg1, 31); read_argv(2, arg2, 9)
    new target = cmd_target(id, arg1, 2)
    if(target) {
        g_WeaponXP[target][get_user_weapon(target)] += str_to_num(arg2)
        save_data(target)
    }
    return PLUGIN_HANDLED
}

public save_data(id) {
    new key[64], data[1024]; formatex(key, 63, "WPN_%s", g_PlayerName[id])
    new pos = 0
    for(new i = 1; i < MAX_WEAPONS; i++) pos += formatex(data[pos], 1023-pos, "%d ", g_WeaponXP[id][i])
    nvault_set(g_Vault, key, data)
}

public load_data(id) {
    new key[64], data[1024]; formatex(key, 63, "WPN_%s", g_PlayerName[id])
    if(nvault_get(g_Vault, key, data, 1023)) {
        new xps[MAX_WEAPONS][12]
        parse(data, xps[1], 11, xps[2], 11, xps[3], 11, xps[4], 11, xps[5], 11, xps[6], 11, xps[7], 11, xps[8], 11, xps[9], 11, xps[10], 11,
                    xps[11], 11, xps[12], 11, xps[13], 11, xps[14], 11, xps[15], 11, xps[16], 11, xps[17], 11, xps[18], 11, xps[19], 11, xps[20], 11,
                    xps[21], 11, xps[22], 11, xps[23], 11, xps[24], 11, xps[25], 11, xps[26], 11, xps[27], 11, xps[28], 11, xps[29], 11, xps[30], 11)
        for(new i = 1; i < MAX_WEAPONS; i++) g_WeaponXP[id][i] = str_to_num(xps[i])
    }
}
