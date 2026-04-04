#include <amxmodx>
#include <amxmisc>
#include <engine>
#include <fakemeta>

#define PLUGIN "Admin Portals"
#define VERSION "1.0"
#define AUTHOR "AI"

#define PORTAL_CLASSNAME "admin_portal"

new const g_SpriteModel[] = "sprites/flare1.spr";
new const g_SoundTeleport[] = "debris/beamstart1.wav"; // Sunet default de zap electric

new g_CvarSave, g_CvarTeamsOnly;
new g_LastPrimaryEnt = 0;
new bool:g_WaitingForSecondary = false;
new g_DataPath[128];
new g_MsgScreenFade;

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
    register_clcmd("amx_portalmenu", "cmd_portal_menu", ADMIN_KICK, "- Deschide meniul de gestiune a portalelor");

    register_event("HLTV", "event_round_start", "a", "1=0", "2=0");
    
    // Atingeri pentru Jucatori si Grenade
    register_touch(PORTAL_CLASSNAME, "player", "fw_PortalTouch_Player");
    register_touch(PORTAL_CLASSNAME, "grenade", "fw_PortalTouch_Grenade");

    g_MsgScreenFade = get_user_msgid("ScreenFade");

    setup_data_path();
    set_task(2.0, "load_portals");
}

public plugin_precache() {
    precache_model(g_SpriteModel);
    precache_sound(g_SoundTeleport);
}

setup_data_path() {
    new dataDir[64], mapName[32];
    get_datadir(dataDir, charsmax(dataDir));
    get_mapname(mapName, charsmax(mapName));
    formatex(g_DataPath, charsmax(g_DataPath), "%s/Portals", dataDir);
    if(!dir_exists(g_DataPath)) mkdir(g_DataPath);
    formatex(g_DataPath, charsmax(g_DataPath), "%s/%s.txt", g_DataPath, mapName);
}

// --- MENIU DE GESTIUNE ---

public cmd_portal_menu(id, level, cid) {
    if(!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;

    new menu = menu_create("\yMeniu Gestiune Portale", "menu_handler");

    menu_additem(menu, g_WaitingForSecondary ? "\dCreaza Portal Primar (In Asteptare)" : "\w1. Creaza Portal Primar", "1");
    menu_additem(menu, g_WaitingForSecondary ? "\w2. Creaza Portal Secundar" : "\dCreaza Portal Secundar (Asteapta Primar)", "2");
    menu_additem(menu, "\w3. Sterge cel mai apropiat portal (Pereche)", "3");
    menu_additem(menu, "\r4. Sterge TOATE portalele", "4");

    new teamMode[64];
    formatex(teamMode, charsmax(teamMode), "\w5. Mod Echipe: \y%s", get_pcvar_num(g_CvarTeamsOnly) ? "ACTIVAT" : "DEZACTIVAT");
    menu_additem(menu, teamMode, "5");

    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public menu_handler(id, menu, item) {
    if(item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, 5, iName, 63, callback);
    new key = str_to_num(data);

    switch(key) {
        case 1: client_cmd(id, "amx_primaryportal");
        case 2: client_cmd(id, "amx_secondaryportal");
        case 3: cmd_delete_nearest(id);
        case 4: client_cmd(id, "amx_clearportals");
        case 5: set_pcvar_num(g_CvarTeamsOnly, !get_pcvar_num(g_CvarTeamsOnly));

    }
    menu_destroy(menu);
    cmd_portal_menu(id, 0, 0);
    return PLUGIN_HANDLED;
}

// --- COMENZI DE CREARE ---

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

    if(get_pcvar_num(g_CvarSave)) resave_all_portals(); // Re-salvam mereu curat cand adaugam

    g_WaitingForSecondary = false;
    client_print(id, print_chat, "[Portal] Pereche finalizata!");
    return PLUGIN_HANDLED;
}

// --- LOGICA ENTITATI ---

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

    new Float:color[3];
    if(team == 1) {
        if(type == 1) { color[0] = 255.0; color[1] = 0.0; color[2] = 0.0; }
        else { color[0] = 255.0; color[1] = 150.0; color[2] = 0.0; }
    } else if(team == 2) {
        if(type == 1) { color[0] = 0.0; color[1] = 0.0; color[2] = 255.0; }
        else { color[0] = 0.0; color[1] = 200.0; color[2] = 255.0; }
    } else {
        if(type == 1) { color[0] = 0.0; color[1] = 100.0; color[2] = 255.0; }
        else { color[0] = 255.0; color[1] = 165.0; color[2] = 0.0; }
    }

    entity_set_vector(ent, EV_VEC_rendercolor, color);
    entity_set_origin(ent, origin);
    
    return ent;
}

// --- TELEPORTARE JUCATORI ---

public fw_PortalTouch_Player(ent, id) {
    if(!is_user_alive(id)) return;

    if(get_pcvar_num(g_CvarTeamsOnly)) {
        new pTeam = entity_get_int(ent, EV_INT_iuser3);
        if(pTeam != 0 && get_user_team(id) != pTeam) return;
    }

    new partner = entity_get_int(ent, EV_INT_iuser2);
    if(!is_valid_ent(partner)) return;

    static Float:lastTeleport[33];
    
    // ANTI-CAMPING & ANTI-LOOP (Cooldown 1.5s)
    if(get_gametime() - lastTeleport[id] < 1.5) {
        // Daca inca e pe cooldown si il atinge, il impingem afara ca sa nu blocheze zona
        new Float:pOrigin[3], Float:entOrigin[3], Float:push[3];
        entity_get_vector(id, EV_VEC_origin, pOrigin);
        entity_get_vector(ent, EV_VEC_origin, entOrigin);
        
        push[0] = pOrigin[0] - entOrigin[0];
        push[1] = pOrigin[1] - entOrigin[1];
        push[2] = 0.0; // Fara inaltime

        new Float:len = floatsqroot(push[0]*push[0] + push[1]*push[1]);
        if(len < 1.0) { push[0] = 1.0; len = 1.0; } // Evita impartirea la 0

        push[0] = (push[0] / len) * 200.0; // Forta de impingere
        push[1] = (push[1] / len) * 200.0;
        
        entity_set_vector(id, EV_VEC_velocity, push);
        return;
    }

    // TELEPORTARE EFECTIVA
    new Float:targetOrigin[3], Float:velocity[3];
    
    // Preluam momentul (viteza)
    entity_get_vector(id, EV_VEC_velocity, velocity);
    entity_get_vector(partner, EV_VEC_origin, targetOrigin);
    
    targetOrigin[2] += 36.0;
    entity_set_origin(id, targetOrigin);
    
    // Reaplicam momentul
    entity_set_vector(id, EV_VEC_velocity, velocity);

    // EFECTE: Sunet si Screen Fade Negru
    emit_sound(id, CHAN_STATIC, g_SoundTeleport, VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
    apply_screen_fade(id);

    // Verificare blocaj
    new data[2]; data[0] = id;
    set_task(0.1, "task_check_stuck", 0, data, 1);

    lastTeleport[id] = get_gametime();
}

// --- TELEPORTARE GRENADE ---

public fw_PortalTouch_Grenade(ent, grenade) {
    if(!is_valid_ent(grenade)) return;

    new partner = entity_get_int(ent, EV_INT_iuser2);
    if(!is_valid_ent(partner)) return;

    // Folosim fuser1 pt a pastra timpul ultimei teleportari a grenadei
    new Float:lastGrenadeTp = entity_get_float(grenade, EV_FL_fuser1);
    if(get_gametime() - lastGrenadeTp < 0.5) return; // Cooldown scurt

    new Float:targetOrigin[3], Float:velocity[3];
    entity_get_vector(grenade, EV_VEC_velocity, velocity);
    entity_get_vector(partner, EV_VEC_origin, targetOrigin);
    
    targetOrigin[2] += 20.0; // Offset usor mai jos decat jucatorii

    entity_set_origin(grenade, targetOrigin);
    entity_set_vector(grenade, EV_VEC_velocity, velocity);

    emit_sound(grenade, CHAN_WEAPON, g_SoundTeleport, VOL_NORM, ATTN_NORM, 0, PITCH_HIGH); // Sunet mai ascutit

    entity_set_float(grenade, EV_FL_fuser1, get_gametime());
}

// --- SISTEM ANTI-STUCK ---

public task_check_stuck(data[]) {
    new id = data[0];
    if(!is_user_alive(id)) return;
    if(is_player_stuck(id)) find_free_space(id);
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

// --- UTILAJE SI EFECTE ---

apply_screen_fade(id) {
    message_begin(MSG_ONE_UNRELIABLE, g_MsgScreenFade, _, id);
    write_short(1<<11); // Durata aprox 0.5s
    write_short(1<<9);  // Hold time
    write_short(0x0000); // FFADE_IN (Fade out spre transparenta)
    write_byte(0); // R
    write_byte(0); // G
    write_byte(0); // B
    write_byte(255); // Alpha total opac
    message_end();
}

// --- SALVARE / INCARCARE / STERGERE ---

cmd_delete_nearest(id) {
    new Float:pOrigin[3], Float:entOrigin[3], ent = -1, nearestEnt = -1;
    new Float:minDist = 9999.0, Float:dist;
    
    entity_get_vector(id, EV_VEC_origin, pOrigin);

    while((ent = find_ent_by_class(ent, PORTAL_CLASSNAME))) {
        entity_get_vector(ent, EV_VEC_origin, entOrigin);
        dist = get_distance_f(pOrigin, entOrigin); // Functie sigura integrata
        if(dist < minDist) {
            minDist = dist;
            nearestEnt = ent;
        }
    }

    if(nearestEnt != -1 && minDist < 200.0) { // Cauta la maxim 200 unitati
        new partner = entity_get_int(nearestEnt, EV_INT_iuser2);
        if(is_valid_ent(partner)) remove_entity(partner);
        remove_entity(nearestEnt);
        
        resave_all_portals();
        client_print(id, print_chat, "[Portal] Perechea cea mai apropiata a fost stearsa cu succes.");
    } else {
        client_print(id, print_chat, "[Portal] Nu s-a gasit niciun portal in apropiere.");
    }
}

resave_all_portals() {
    if(file_exists(g_DataPath)) delete_file(g_DataPath);
    
    new ent = -1;
    while((ent = find_ent_by_class(ent, PORTAL_CLASSNAME))) {
        if(entity_get_int(ent, EV_INT_iuser1) == 1) { // Salvam doar de la primar spre secundar
            new partner = entity_get_int(ent, EV_INT_iuser2);
            if(is_valid_ent(partner)) {
                save_portal_pair(ent, partner, entity_get_int(ent, EV_INT_iuser3));
            }
        }
    }
}

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
    client_print(id, print_chat, "[Portal] S-au sters TOATE portalele!");
    return PLUGIN_HANDLED;
}

remove_all_portals() {
    new ent = -1;
    while((ent = find_ent_by_class(ent, PORTAL_CLASSNAME))) remove_entity(ent);
    g_WaitingForSecondary = false;
}
