#include <amxmodx>
#include <amxmisc>
#include <engine>
#include <fakemeta>

#define PLUGIN "Admin Portals"
#define VERSION "1.0"
#define AUTHOR "AI"

#define PORTAL_CLASSNAME "admin_portal"

new const g_SpriteModel[] = "sprites/flare1.spr";

new g_CvarSave, g_CvarTeamsOnly;
new g_LastPrimaryEnt = 0;
new bool:g_WaitingForSecondary = false;
new g_DataPath[128];

// Pentru Anti-Stuck
new Float:g_StuckOffsets[][] = {
    {0.0, 0.0, 0.0}, {0.0, 0.0, 32.0}, {32.0, 0.0, 0.0}, {-32.0, 0.0, 0.0},
    {0.0, 32.0, 0.0}, {0.0, -32.0, 0.0}, {32.0, 32.0, 0.0}, {-32.0, -32.0, 0.0}
};

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);

    g_CvarSave = register_cvar("amx_save_portals", "1");
    g_CvarTeamsOnly = register_cvar("amx_portal_teamsonly", "1");

    register_concmd("amx_primaryportal", "cmd_create_primary", ADMIN_KICK);
    register_concmd("amx_secondaryportal", "cmd_create_secondary", ADMIN_KICK);
    register_concmd("amx_clearportals", "cmd_clear_all", ADMIN_KICK);

    register_event("HLTV", "event_round_start", "a", "1=0", "2=0");
    register_touch(PORTAL_CLASSNAME, "player", "fw_PortalTouch");

    setup_data_path();
    set_task(2.0, "load_portals");
}

public plugin_precache() {
    precache_model(g_SpriteModel);
}

setup_data_path() {
    new dataDir[64], mapName[32];
    get_datadir(dataDir, charsmax(dataDir));
    get_mapname(mapName, charsmax(mapName));
    formatex(g_DataPath, charsmax(g_DataPath), "%s/Portals", dataDir);
    if(!dir_exists(g_DataPath)) mkdir(g_DataPath);
    formatex(g_DataPath, charsmax(g_DataPath), "%s/%s.txt", g_DataPath, mapName);
}

// --- COMENZI ---

public cmd_create_primary(id, level, cid) {
    if(!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    if(g_WaitingForSecondary) {
        client_print(id, print_chat, "[Portal] Eroare: Pune intai portalul SECUNDAR!");
        return PLUGIN_HANDLED;
    }

    new Float:origin[3];
    entity_get_vector(id, EV_VEC_origin, origin);
    
    new team = get_pcvar_num(g_CvarTeamsOnly) ? get_user_team(id) : 0;
    g_LastPrimaryEnt = create_portal_entity(origin, 1, team);
    g_WaitingForSecondary = true;

    client_print(id, print_chat, "[Portal] Primar creat (%s). Acum pune Secundar!", team == 1 ? "Tero" : (team == 2 ? "CT" : "Toate"));
    return PLUGIN_HANDLED;
}

public cmd_create_secondary(id, level, cid) {
    if(!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    if(!g_WaitingForSecondary) {
        client_print(id, print_chat, "[Portal] Eroare: Pune intai portalul PRIMAR!");
        return PLUGIN_HANDLED;
    }

    new Float:origin[3];
    entity_get_vector(id, EV_VEC_origin, origin);
    
    new team = entity_get_int(g_LastPrimaryEnt, EV_INT_iuser3);
    new secondaryEnt = create_portal_entity(origin, 2, team);

    entity_set_int(g_LastPrimaryEnt, EV_INT_iuser2, secondaryEnt);
    entity_set_int(secondaryEnt, EV_INT_iuser2, g_LastPrimaryEnt);

    if(get_pcvar_num(g_CvarSave)) save_portal_pair(g_LastPrimaryEnt, secondaryEnt, team);

    g_WaitingForSecondary = false;
    client_print(id, print_chat, "[Portal] Pereche finalizata!");
    return PLUGIN_HANDLED;
}

// --- LOGICA ENTITATE ---

create_portal_entity(Float:origin[3], type, team) {
    new ent = create_entity("info_target");
    if(!is_valid_ent(ent)) return 0;

    entity_set_string(ent, EV_SZ_classname, PORTAL_CLASSNAME);
    entity_set_int(ent, EV_INT_iuser1, type); // 1-Primar, 2-Secundar
    entity_set_int(ent, EV_INT_iuser3, team); // 0-All, 1-T, 2-CT
    
    entity_set_model(ent, g_SpriteModel);
    entity_set_size(ent, Float:{-20.0, -20.0, -10.0}, Float:{20.0, 20.0, 10.0});
    entity_set_int(ent, EV_INT_solid, SOLID_TRIGGER);
    entity_set_int(ent, EV_INT_movetype, MOVETYPE_NONE);
    entity_set_int(ent, EV_INT_rendermode, kRenderTransAdd);
    entity_set_float(ent, EV_FL_renderamt, 220.0);
    entity_set_float(ent, EV_FL_scale, 1.3);

    // FIX COMPILATOR: Am scos listele dinamice de vectori pentru a evita eroarea
    new Float:color[3];
    
    if(team == 1) { // TERO - Nuante de Rosu
        if(type == 1) { color[0] = 255.0; color[1] = 0.0; color[2] = 0.0; }
        else { color[0] = 255.0; color[1] = 150.0; color[2] = 0.0; }
    } 
    else if(team == 2) { // CT - Nuante de Albastru
        if(type == 1) { color[0] = 0.0; color[1] = 0.0; color[2] = 255.0; }
        else { color[0] = 0.0; color[1] = 200.0; color[2] = 255.0; }
    } 
    else { // ALL - Clasicul Portal (Albastru / Portocaliu)
        if(type == 1) { color[0] = 0.0; color[1] = 100.0; color[2] = 255.0; }
        else { color[0] = 255.0; color[1] = 165.0; color[2] = 0.0; }
    }

    entity_set_vector(ent, EV_VEC_rendercolor, color);
    entity_set_origin(ent, origin);
    
    return ent;
}

public fw_PortalTouch(ent, id) {
    if(!is_user_alive(id)) return;

    // Verificare echipa
    if(get_pcvar_num(g_CvarTeamsOnly)) {
        new pTeam = entity_get_int(ent, EV_INT_iuser3);
        if(pTeam != 0 && get_user_team(id) != pTeam) return;
    }

    new partner = entity_get_int(ent, EV_INT_iuser2);
    if(!is_valid_ent(partner)) return;

    static Float:lastTeleport[33];
    if(get_gametime() - lastTeleport[id] < 1.5) return;

    new Float:targetOrigin[3];
    entity_get_vector(partner, EV_VEC_origin, targetOrigin);
    
    // Teleportare initiala
    targetOrigin[2] += 36.0;
    entity_set_origin(id, targetOrigin);
    
    // Verificare Anti-Stuck dupa 0.1 secunde
    new data[2]; data[0] = id;
    set_task(0.1, "task_check_stuck", 0, data, 1);

    lastTeleport[id] = get_gametime();
}

public task_check_stuck(data[]) {
    new id = data[0];
    if(!is_user_alive(id)) return;

    if(is_player_stuck(id)) {
        find_free_space(id);
    }
}

bool:is_player_stuck(id) {
    new Float:origin[3];
    entity_get_vector(id, EV_VEC_origin, origin);
    
    new hull = (entity_get_int(id, EV_INT_flags) & FL_DUCKING) ? HULL_HEAD : HULL_HUMAN;
    
    engfunc(EngFunc_TraceHull, origin, origin, 0, hull, id, 0);
    
    if(get_tr2(0, TR_StartSolid) || get_tr2(0, TR_AllSolid) || !get_tr2(0, TR_InOpen))
        return true;
        
    return false;
}

find_free_space(id) {
    new Float:origin[3], Float:newOrigin[3];
    entity_get_vector(id, EV_VEC_origin, origin);

    for(new i = 0; i < sizeof(g_StuckOffsets); i++) {
        newOrigin[0] = origin[0] + g_StuckOffsets[i][0];
        newOrigin[1] = origin[1] + g_StuckOffsets[i][1];
        newOrigin[2] = origin[2] + g_StuckOffsets[i][2];

        new hull = (entity_get_int(id, EV_INT_flags) & FL_DUCKING) ? HULL_HEAD : HULL_HUMAN;
        engfunc(EngFunc_TraceHull, newOrigin, newOrigin, 0, hull, id, 0);

        if(!get_tr2(0, TR_StartSolid) && !get_tr2(0, TR_AllSolid) && get_tr2(0, TR_InOpen)) {
            entity_set_origin(id, newOrigin);
            return 1;
        }
    }
    return 0;
}

// --- SALVARE / INCARCARE ---

save_portal_pair(ent1, ent2, team) {
    new Float:orig1[3], Float:orig2[3];
    entity_get_vector(ent1, EV_VEC_origin, orig1);
    entity_get_vector(ent2, EV_VEC_origin, orig2);

    new line[192];
    formatex(line, charsmax(line), "%f %f %f %f %f %f %d", orig1[0], orig1[1], orig1[2], orig2[0], orig2[1], orig2[2], team);
    write_file(g_DataPath, line);
}

public load_portals() {
    if(!file_exists(g_DataPath)) return;
    new file = fopen(g_DataPath, "rt");
    if(!file) return;

    new line[192], sO1[3][16], sO2[3][16], sTeam[4];
    new Float:fO1[3], Float:fO2[3], iTeam;

    while(!feof(file)) {
        fgets(file, line, charsmax(line));
        trim(line);
        if(!line[0]) continue;

        parse(line, sO1[0], 15, sO1[1], 15, sO1[2], 15, sO2[0], 15, sO2[1], 15, sO2[2], 15, sTeam, 3);

        for(new i=0; i<3; i++) {
            fO1[i] = str_to_float(sO1[i]);
            fO2[i] = str_to_float(sO2[i]);
        }
        iTeam = str_to_num(sTeam);

        new p1 = create_portal_entity(fO1, 1, iTeam);
        new p2 = create_portal_entity(fO2, 2, iTeam);
        entity_set_int(p1, EV_INT_iuser2, p2);
        entity_set_int(p2, EV_INT_iuser2, p1);
    }
    fclose(file);
}

public event_round_start() {
    if(!get_pcvar_num(g_CvarSave)) remove_all_portals();
}

public cmd_clear_all(id, level, cid) {
    if(!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    remove_all_portals();
    if(file_exists(g_DataPath)) delete_file(g_DataPath);
    g_WaitingForSecondary = false;
    client_print(id, print_chat, "[Portal] Sters tot!");
    return PLUGIN_HANDLED;
}

remove_all_portals() {
    new ent = -1;
    while((ent = find_ent_by_class(ent, PORTAL_CLASSNAME))) remove_entity(ent);
    g_WaitingForSecondary = false;
}
