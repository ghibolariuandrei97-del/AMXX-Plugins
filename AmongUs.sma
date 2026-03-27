#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fun>
#include <fakemeta>
#include <engine>

#define TASK_ENT_CLASS "au_repair_terminal"
#define CORPSE_CLASS "au_dead_body"
#define REPAIR_TIME 5

new bool:g_IsImpostor[33], g_Votes[33], bool:g_VoteActive[3];
new Float:g_DeadBodyPos[33][3], g_DeadBodyTeam[33], bool:g_IsImpostorVictim[33]; 
new Float:g_LastKillTime[33], Float:g_LastInvisTime[33];
new g_LightLevel, g_BarTime, g_MsgScreenFade, g_HudSync;
new bool:g_IsRepairing[33], bool:g_EmergencyUsed[33];

new cvar_cooldown, cvar_max_imp, cvar_team_mode, cvar_menu_time, cvar_invis_cooldown, cvar_invis_time;
new cvar_imp_hp, cvar_imp_money;
new const g_RandomWeapons[][] = { "weapon_m4a1", "weapon_ak47", "weapon_mp5navy", "weapon_awp", "weapon_famas", "weapon_galil" };

public plugin_init() {
    register_plugin("Among Us Hybrid", "b0.1", "Terra_Fan");

    cvar_cooldown = register_cvar("amx_au_kill_cooldown", "30.0");
    cvar_max_imp = register_cvar("amx_au_max_impostors", "2");
    cvar_team_mode = register_cvar("amx_au_team_mode", "3");
    cvar_menu_time = register_cvar("amx_au_menu_time", "20");
    cvar_invis_cooldown = register_cvar("amx_au_invis_cooldown", "45.0");
    cvar_invis_time = register_cvar("amx_au_invis_time", "7.0");
    
    // CVAR-uri noi pentru recompensa Impostor
    cvar_imp_hp = register_cvar("au_imposter_hp", "50");
    cvar_imp_money = register_cvar("au_imposter_money", "2500");

    register_event("HLTV", "event_round_start", "a", "1=0", "2=0");
    register_event("DeathMsg", "event_death", "a");
    register_forward(FM_CmdStart, "fwd_CmdStart");
    
    register_clcmd("say", "handle_say");
    register_clcmd("say_team", "handle_say");
    register_clcmd("say /report", "cmd_report");
    register_clcmd("say /emergency", "cmd_emergency");
    register_clcmd("kill_target", "cmd_kill_target");
    register_clcmd("invis", "cmd_invis");
    
    register_clcmd("say /imp", "admin_show_impostors", ADMIN_KICK);
    register_clcmd("say /imp2", "admin_force_impostor", ADMIN_RCON);
    
    register_concmd("amx_add_task", "admin_add_task", ADMIN_RCON);
    register_concmd("amx_clear_tasks", "admin_clear_tasks", ADMIN_RCON);

    g_BarTime = get_user_msgid("BarTime");
    g_MsgScreenFade = get_user_msgid("ScreenFade");
    g_HudSync = CreateHudSyncObj();

    set_task(0.5, "check_proximity_hud", _, _, _, "b");
}

public plugin_precache() {
    precache_model("sprites/ledglow.spr");
}

public event_round_start() {
    g_VoteActive[1] = false; g_VoteActive[2] = false;
    g_LightLevel = 109; set_lights("m"); 
    
    remove_entity_name(TASK_ENT_CLASS);
    remove_entity_name(CORPSE_CLASS);

    for(new i = 1; i <= 32; i++) {
        g_IsImpostor[i] = false; g_Votes[i] = 0;
        g_DeadBodyPos[i][0] = 0.0; g_IsRepairing[i] = false;
        g_LastKillTime[i] = 0.0; g_LastInvisTime[i] = 0.0;
        g_EmergencyUsed[i] = false; g_IsImpostorVictim[i] = false;
        
        if(is_user_connected(i)) {
            set_pev(i, pev_flags, pev(i, pev_flags) & ~FL_FROZEN);
            set_user_rendering(i, kRenderFxNone, 0, 0, 0, kRenderNormal, 255);
        }
    }
    
    set_task(1.0, "load_tasks_from_file");
    if(get_pcvar_num(cvar_team_mode) > 0) set_task(5.0, "assign_roles");
}

public admin_force_impostor(id, level, cid) {
    if(!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    g_IsImpostor[id] = true; cs_set_user_nvg(id, 1);
    client_print(id, print_chat, "[AMONG US] Te-ai facut Impostor cu forta!");
    return PLUGIN_HANDLED;
}

public admin_show_impostors(id, level, cid) {
    if(!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    new name[32], found = 0;
    client_print(id, print_chat, "[AMONG US] Lista Impostori:");
    for(new i = 1; i <= 32; i++) {
        if(is_user_connected(i) && g_IsImpostor[i]) {
            get_user_name(i, name, 31);
            client_print(id, print_chat, "- %s (%s)", name, (cs_get_user_team(i) == CS_TEAM_T) ? "Tero" : "CT");
            found++;
        }
    }
    if(!found) client_print(id, print_chat, "[AMONG US] Nu exista impostori.");
    return PLUGIN_HANDLED;
}

public handle_say(id) {
    if(get_pcvar_num(cvar_team_mode) > 0 && !is_user_alive(id)) {
        if(!(get_user_flags(id) & ADMIN_KICK)) {
            client_print(id, print_chat, "[AMONG US] Mortii nu pot vorbi!");
            return PLUGIN_HANDLED;
        }
    }
    return PLUGIN_CONTINUE;
}

public admin_add_task(id, level, cid) {
    if(!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    new Float:origin[3]; pev(id, pev_origin, origin);
    spawn_task_logic(origin);
    new mapname[32], filepath[128], dirpath[64];
    get_mapname(mapname, 31); get_configsdir(dirpath, 63);
    format(filepath, 127, "%s/au_tasks", dirpath);
    if(!dir_exists(filepath)) mkdir(filepath);
    format(filepath, 127, "%s/au_tasks/%s.ini", dirpath, mapname);
    new f = fopen(filepath, "at");
    if(f) {
        new line[64]; format(line, 63, "%f %f %f^n", origin[0], origin[1], origin[2]);
        fputs(f, line); fclose(f);
        client_print(id, print_chat, "[AMONG US] Task salvat.");
    }
    return PLUGIN_HANDLED;
}

public admin_clear_tasks(id, level, cid) {
    if(!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    new mapname[32], filepath[128], dirpath[64];
    get_mapname(mapname, 31); get_configsdir(dirpath, 63);
    format(filepath, 127, "%s/au_tasks/%s.ini", dirpath, mapname);
    if(file_exists(filepath)) delete_file(filepath);
    remove_entity_name(TASK_ENT_CLASS);
    return PLUGIN_HANDLED;
}

public load_tasks_from_file() {
    new mapname[32], filepath[128], dirpath[64], line[128];
    get_mapname(mapname, 31); get_configsdir(dirpath, 63);
    format(filepath, 127, "%s/au_tasks/%s.ini", dirpath, mapname);
    if(!file_exists(filepath)) return;
    new f = fopen(filepath, "rt");
    if(!f) return;
    while(!feof(f)) {
        fgets(f, line, 127); trim(line);
        if(!line[0]) continue;
        new str_x[16], str_y[16], str_z[16], Float:origin[3];
        parse(line, str_x, 15, str_y, 15, str_z, 15);
        origin[0] = str_to_float(str_x); origin[1] = str_to_float(str_y); origin[2] = str_to_float(str_z);
        spawn_task_logic(origin);
    }
    fclose(f);
}

public spawn_task_logic(Float:origin[3]) {
    new ent = create_entity("info_target");
    if(!is_valid_ent(ent)) return;
    entity_set_string(ent, EV_SZ_classname, TASK_ENT_CLASS);
    entity_set_origin(ent, origin);
    entity_set_model(ent, "sprites/ledglow.spr");
    entity_set_int(ent, EV_INT_renderfx, kRenderFxGlowShell);
    new Float:fColor[3]; fColor[0] = float(random_num(50, 255)); fColor[1] = float(random_num(50, 255)); fColor[2] = float(random_num(50, 255));
    entity_set_vector(ent, EV_VEC_rendercolor, fColor);
    entity_set_float(ent, EV_FL_renderamt, 200.0);
}

public fwd_CmdStart(id, uc_handle, seed) {
    if(!is_user_alive(id) || g_IsImpostor[id]) return FMRES_IGNORED;
    new buttons = get_uc(uc_handle, UC_Buttons);
    new oldbuttons = pev(id, pev_oldbuttons);
    if(g_IsRepairing[id]) {
        new Float:velocity[3]; entity_get_vector(id, EV_VEC_velocity, velocity);
        if(vector_length(velocity) > 10.0 || (buttons & IN_JUMP)) {
            cancel_repair(id); return FMRES_IGNORED;
        }
        velocity[0] = 0.0; velocity[1] = 0.0; entity_set_vector(id, EV_VEC_velocity, velocity);
    }
    if((buttons & IN_USE) && !(oldbuttons & IN_USE)) {
        new ent = -1, Float:pOrigin[3]; pev(id, pev_origin, pOrigin);
        while((ent = find_ent_by_class(ent, TASK_ENT_CLASS)) != 0) {
            new Float:eOrigin[3]; pev(ent, pev_origin, eOrigin);
            if(get_distance_f(pOrigin, eOrigin) < 100.0) {
                g_IsRepairing[id] = true;
                message_begin(MSG_ONE, g_BarTime, .player=id); write_short(REPAIR_TIME); message_end();
                new data[2]; data[0] = id; data[1] = ent;
                set_task(float(REPAIR_TIME), "task_finished", id + 100, data, 2);
                break;
            }
        }
    } else if(!(buttons & IN_USE) && (oldbuttons & IN_USE) && g_IsRepairing[id]) cancel_repair(id);
    return FMRES_IGNORED;
}

public cancel_repair(id) {
    g_IsRepairing[id] = false; remove_task(id + 100);
    message_begin(MSG_ONE, g_BarTime, .player=id); write_short(0); message_end();
}

public task_finished(data[]) {
    new id = data[0], ent = data[1];
    if(g_IsRepairing[id] && is_valid_ent(ent)) {
        g_IsRepairing[id] = false; g_LightLevel = 109; set_lights("m"); remove_entity(ent);
        cs_set_user_money(id, cs_get_user_money(id) + 1500);
        set_user_health(id, get_user_health(id) + 30);
        new w_idx = random_num(0, sizeof(g_RandomWeapons) - 1);
        give_item(id, g_RandomWeapons[w_idx]);
        client_print(id, print_chat, "[AMONG US] Task completat!");
        message_begin(MSG_ONE, g_BarTime, .player=id); write_short(0); message_end();
    }
}

public cmd_kill_target(id) {
    if(!is_user_alive(id) || !g_IsImpostor[id]) return PLUGIN_HANDLED;
    new team = _:cs_get_user_team(id);
    if(g_VoteActive[team]) return PLUGIN_HANDLED;
    if(get_gametime() - g_LastKillTime[id] < get_pcvar_float(cvar_cooldown)) return PLUGIN_HANDLED;
    
    new target, body; get_user_aiming(id, target, body, 150);
    if(is_user_alive(target) && cs_get_user_team(id) == cs_get_user_team(target) && !g_IsImpostor[target]) {
        g_IsImpostorVictim[target] = true;
        pev(target, pev_origin, g_DeadBodyPos[target]);
        g_DeadBodyTeam[target] = _:cs_get_user_team(target);
        
        spawn_glowing_corpse(target);
        user_kill(target, 1); 
        
        // Recompensa Impostor
        set_user_health(id, get_user_health(id) + get_pcvar_num(cvar_imp_hp));
        cs_set_user_money(id, cs_get_user_money(id) + get_pcvar_num(cvar_imp_money));
        
        g_LastKillTime[id] = get_gametime();
        g_LightLevel -= 3; if(g_LightLevel < 97) g_LightLevel = 97;
        new s[2]; s[0] = g_LightLevel; s[1] = 0; set_lights(s);
    }
    return PLUGIN_HANDLED;
}

spawn_glowing_corpse(id) {
    new ent = create_entity("info_target");
    if(!is_valid_ent(ent)) return;
    
    new Float:origin[3]; pev(id, pev_origin, origin);
    origin[2] -= 34.0; 
    entity_set_string(ent, EV_SZ_classname, CORPSE_CLASS);
    entity_set_origin(ent, origin);
    
    new model[64]; pev(id, pev_model, model, 63);
    entity_set_model(ent, model);
    
    entity_set_int(ent, EV_INT_sequence, 101);
    entity_set_int(ent, EV_INT_solid, SOLID_NOT);
    entity_set_int(ent, EV_INT_movetype, MOVETYPE_NONE);
    
    set_entity_visibility(ent, 1);
    entity_set_int(ent, EV_INT_renderfx, kRenderFxGlowShell);
    new Float:fColor[3] = {255.0, 0.0, 0.0};
    entity_set_vector(ent, EV_VEC_rendercolor, fColor);
    entity_set_int(ent, EV_INT_rendermode, kRenderNormal);
    entity_set_float(ent, EV_FL_renderamt, 25.0);
    
    entity_set_int(ent, EV_INT_iuser1, id); 
}

public check_proximity_hud() {
    new players[32], count; get_players(players, count, "ae");
    for(new i = 0; i < count; i++) {
        new id = players[i];
        if(g_IsImpostor[id]) continue;
        
        new team = _:cs_get_user_team(id);
        new ent = -1;
        while((ent = find_ent_by_class(ent, CORPSE_CLASS)) != 0) {
            new victim_id = entity_get_int(ent, EV_INT_iuser1);
            if(g_DeadBodyTeam[victim_id] == team) {
                new Float:cOrigin[3], Float:pOrigin[3];
                pev(ent, pev_origin, cOrigin); pev(id, pev_origin, pOrigin);
                if(get_distance_f(cOrigin, pOrigin) < 180.0) {
                    set_hudmessage(255, 50, 50, -1.0, 0.6, 0, 0.1, 0.6, 0.1, 0.1, -1);
                    ShowSyncHudMsg(id, g_HudSync, "CADAVRU DETECTAT!^nScrie /report pentru VOT");
                }
            }
        }
    }
}

public cmd_invis(id) {
    if(!is_user_alive(id) || !g_IsImpostor[id]) return PLUGIN_HANDLED;
    if(get_gametime() - g_LastInvisTime[id] < get_pcvar_float(cvar_invis_cooldown)) return PLUGIN_HANDLED;
    set_user_rendering(id, kRenderFxGlowShell, 0, 0, 0, kRenderTransAlpha, 0);
    g_LastInvisTime[id] = get_gametime();
    message_begin(MSG_ONE, g_MsgScreenFade, {0,0,0}, id);
    write_short(1<<12); write_short(1<<12 * get_pcvar_num(cvar_invis_time)); write_short(0x0001);
    write_byte(0); write_byte(100); write_byte(255); write_byte(130); message_end();
    set_task(get_pcvar_float(cvar_invis_time), "remove_invis", id);
    return PLUGIN_HANDLED;
}

public remove_invis(id) {
    if(is_user_connected(id)) {
        set_user_rendering(id, kRenderFxNone, 0, 0, 0, kRenderNormal, 255);
        message_begin(MSG_ONE, g_MsgScreenFade, {0,0,0}, id);
        write_short(1<<12); write_short(0); write_short(0x0002);
        write_byte(0); write_byte(0); write_byte(0); write_byte(0); message_end();
    }
}

public event_death() {
    new victim = read_data(2);
    if(!g_IsImpostorVictim[victim]) {
        pev(victim, pev_origin, g_DeadBodyPos[victim]);
        g_DeadBodyTeam[victim] = _:cs_get_user_team(victim);
    }
}

public cmd_report(id) {
    new team = _:cs_get_user_team(id);
    if(!is_user_alive(id) || g_VoteActive[team]) return PLUGIN_HANDLED;
    
    new Float:p[3]; pev(id, pev_origin, p);
    new found = 0, victim_id = 0;
    
    new ent = -1;
    while((ent = find_ent_by_class(ent, CORPSE_CLASS)) != 0) {
        new v_id = entity_get_int(ent, EV_INT_iuser1);
        if(g_DeadBodyTeam[v_id] == team) {
            new Float:cOrigin[3]; pev(ent, pev_origin, cOrigin);
            if(get_distance_f(p, cOrigin) < 150.0) {
                found = 1; victim_id = v_id; break;
            }
        }
    }
    
    if(found) {
        new name[32], victim_name[32]; get_user_name(id, name, 31); get_user_name(victim_id, victim_name, 31);
        client_print(0, print_chat, "[AMONG US] %s a gasit cadavrul lui %s si a inceput un vot in echipa %s!", name, victim_name, (team == 1) ? "Tero" : "CT");
        start_team_vote(id, team);
    } else {
        client_print(id, print_chat, "[AMONG US] Nu exista cadavre de echipa ucise de Impostor in apropiere!");
    }
    return PLUGIN_HANDLED;
}

public cmd_emergency(id) {
    new team = _:cs_get_user_team(id);
    if(!is_user_alive(id) || g_VoteActive[team]) return PLUGIN_HANDLED;
    if(g_EmergencyUsed[id]) {
        client_print(id, print_chat, "[AMONG US] Ai folosit deja butonul de urgenta!");
        return PLUGIN_HANDLED;
    }
    g_EmergencyUsed[id] = true;
    new name[32]; get_user_name(id, name, 31);
    client_print(0, print_chat, "[AMONG US] %s a apasat butonul de urgenta! Vot in echipa %s.", name, (team == 1) ? "Tero" : "CT");
    start_team_vote(id, team);
    return PLUGIN_HANDLED;
}

public start_team_vote(reporter, team) {
    g_VoteActive[team] = true;
    for(new i = 1; i <= 32; i++) {
        if(is_user_alive(i)) set_pev(i, pev_flags, pev(i, pev_flags) | FL_FROZEN);
    }
    new players[32], count; get_players(players, count, "e", (team == 1) ? "TERRORIST" : "CT");
    for(new i = 0; i < count; i++) show_vote_menu(players[i]);
    new param[1]; param[0] = team; set_task(get_pcvar_float(cvar_menu_time), "end_team_vote", 0, param, 1);
}

public show_vote_menu(id) {
    new menu = menu_create("\yCine este Impostorul?", "vote_handler");
    new players[32], count, name[32], str_id[3];
    get_players(players, count, "ae", (cs_get_user_team(id) == CS_TEAM_T) ? "TERRORIST" : "CT");
    for(new i = 0; i < count; i++) {
        get_user_name(players[i], name, 31); num_to_str(players[i], str_id, 2);
        menu_additem(menu, name, str_id);
    }
    menu_display(id, menu, 0);
}

public vote_handler(id, menu, item) {
    if(item == MENU_EXIT) return PLUGIN_HANDLED;
    new data[6], name[64], access, callback;
    menu_item_getinfo(menu, item, access, data, 5, name, 63, callback);
    
    new target = str_to_num(data);
    g_Votes[target]++;
    
    new voter_name[32], target_name[32];
    get_user_name(id, voter_name, 31); get_user_name(target, target_name, 31);
    client_print(0, print_chat, "[AMONG US] %s l-a votat pe %s ca fiind Impostor!", voter_name, target_name);
    
    return PLUGIN_HANDLED;
}

public end_team_vote(param[]) {
    new team = param[0]; g_VoteActive[team] = false;
    for(new i = 1; i <= 32; i++) {
        if(is_user_alive(i)) set_pev(i, pev_flags, pev(i, pev_flags) & ~FL_FROZEN);
    }
    new players[32], count, most_votes = 0, eject_id = 0;
    get_players(players, count, "e", (team == 1) ? "TERRORIST" : "CT");
    
    for(new i = 0; i < count; i++) {
        new pid = players[i];
        if(g_Votes[pid] > most_votes) { most_votes = g_Votes[pid]; eject_id = pid; }
        show_menu(pid, 0, "^n", 1);
    }
    
    if(eject_id != 0 && most_votes > 0) {
        new n[32]; get_user_name(eject_id, n, 31);
        client_print(0, print_chat, "[AMONG US] %s a fost ejectat cu %d voturi. Rol: %s.", n, most_votes, g_IsImpostor[eject_id] ? "Impostor" : "Inocent");
        user_kill(eject_id); 
    } else {
        client_print(0, print_chat, "[AMONG US] S-a dat skip la vot fiindca nimeni nu a votat!");
    }
    
    for(new i = 1; i <= 32; i++) g_Votes[i] = 0;
}

public assign_roles() {
    new mode = get_pcvar_num(cvar_team_mode);
    if (mode == 1 || mode == 3) assign_team_impostors("TERRORIST");
    if (mode == 2 || mode == 3) assign_team_impostors("CT");
}

assign_team_impostors(const team[]) {
    new players[32], count; get_players(players, count, "ae", team);
    if (count <= 1) return;
    for (new i = count - 1; i > 0; i--) {
        new j = random_num(0, i), temp = players[i];
        players[i] = players[j]; players[j] = temp;
    }
    new max_imp = get_pcvar_num(cvar_max_imp);
    if (max_imp >= count) max_imp = count - 1;
    if (max_imp < 1) max_imp = 1;
    for (new i = 0; i < max_imp; i++) {
        new t = players[i]; g_IsImpostor[t] = true; cs_set_user_nvg(t, 1);
        client_print(t, print_center, "ESTI IMPOSTOR!");
    }
}
