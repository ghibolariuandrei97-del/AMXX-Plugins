#pragma semicolon 1
#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <xs>

#define PLUGIN  "Counter-strike RTS"
#define VERSION "1.0"
#define AUTHOR  "Ai"

#define FREEZE_TIME 20.0
#define BRIBE_COST 10000

new cvar_min_players, cvar_mod_enabled;
new g_Commander[3], g_TeamMoney[3], g_SelectedPlayer[33], g_TargetTakeover[33]; 
new g_Votes[3][33], g_VoteAttempts[3];
new bool:g_IsVoting[3], g_GameState = 0;
new g_CurrentOrder[3][64];
new bool:g_ForcedHold[33], g_TargetManage[33];
new bool:g_BuyIsMass[33], g_BuyPrimary[33], g_BuyPistol[33];
new g_HudSync_Global, g_HudSync_Phase;

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    cvar_mod_enabled = register_cvar("amx_rts_enable", "1");
    cvar_min_players = register_cvar("amx_rts_players", "8");
    
    register_clcmd("say /menu", "Cmd_OpenMainMenu");
    register_clcmd("say /c", "Cmd_OpenMainMenu");
    register_clcmd("say /n", "Cmd_ToggleNoclip"); 
    register_clcmd("SetOrder", "Handle_OrderChat"); // Pentru messagemode
    
    RegisterHookChain(RG_CBasePlayer_Spawn, "RG_PlayerSpawn_Post", 1);
    RegisterHookChain(RG_CSGameRules_RestartRound, "RG_RestartRound_Post", 1);
    RegisterHookChain(RG_CBasePlayer_AddAccount, "RG_PlayerAddAccount_Pre", 0);
    
    g_HudSync_Global = CreateHudSyncObj();
    g_HudSync_Phase = CreateHudSyncObj();
    set_task(1.0, "Task_GlobalHUD", 1000, _, _, "b");
}

bool:IsModActive() {
    if(!get_pcvar_num(cvar_mod_enabled)) return false;
    if(get_playersnum() < get_pcvar_num(cvar_min_players)) return false;
    return true;
}

public client_disconnected(id) {
    new team = _:get_member(id, m_iTeam);
    if((team == 1 || team == 2) && g_Commander[team] == id) AssignRandomCommander(team);
}

stock AssignRandomCommander(team) {
    new players[32], pnum;
    get_players(players, pnum, "e", (team == 1) ? "TERRORIST" : "CT");
    if(pnum > 0) {
        g_Commander[team] = players[random_num(0, pnum - 1)];
        CollectMoneyToBank(team);
        NotifyCommander(g_Commander[team]);
        client_print_color(0, print_team_default, "^4[TACTICS]^1 Commander nou pentru ^3%s^1: ^3%n^1!", (team == 1) ? "TERO" : "CT", g_Commander[team]);
    } else g_Commander[team] = 0;
}

stock NotifyCommander(id) {
    if(!is_user_connected(id)) return;
    client_print_color(id, print_team_default, "^4[TACTICS]^1 Ai fost ales ^3COMMANDER^1!");
    client_print_color(id, print_team_default, "^4[INFO]^1 Foloseste ^3/menu^1 sau ^3/c^1 pentru control si ^3/n^1 pentru Noclip.");
}

public RG_PlayerAddAccount_Pre(const id, amount, RewardType:type, bool:bForced) {
    if(!IsModActive()) return HC_CONTINUE;
    new team = _:get_member(id, m_iTeam);
    if(team != 1 && team != 2 || g_Commander[team] == 0) return HC_CONTINUE;
    if(amount > 0) { g_TeamMoney[team] += amount; return HC_SUPERCEDE; }
    return HC_CONTINUE;
}

public RG_RestartRound_Post() {
    if(!IsModActive()) return;
    g_TeamMoney[1] += 1000; g_TeamMoney[2] += 1000;
    formatex(g_CurrentOrder[1], 63, "Asteptare...");
    formatex(g_CurrentOrder[2], 63, "Asteptare...");
    g_GameState = 0; 
    for(new i = 1; i <= 32; i++) {
        g_ForcedHold[i] = false;
        if(is_user_connected(i)) set_entvar(i, var_movetype, MOVETYPE_WALK);
    }
    g_Commander[1] = 0; g_Commander[2] = 0;
    g_VoteAttempts[1] = 0; g_VoteAttempts[2] = 0;
    StartVoteForTeam(1); StartVoteForTeam(2);
    set_task(10.0, "EndVoteTimer"); 
}

public StartVoteForTeam(team) {
    g_IsVoting[team] = true;
    for(new j = 0; j <= 32; j++) g_Votes[team][j] = 0;
    for(new i = 1; i <= 32; i++) {
        if(is_user_connected(i) && _:get_member(i, m_iTeam) == team) {
            ShowVoteMenu(i, team);
            set_entvar(i, var_flags, get_entvar(i, var_flags) | FL_FROZEN); 
        }
    }
}

public ShowVoteMenu(id, team) {
    new menu = menu_create("\yAlege Commander:", "VoteHandler");
    menu_additem(menu, "\rFARA COMMANDER (Bani individuali)", "0");
    new players[32], pnum, tempid;
    get_players(players, pnum, "e", (team == 1) ? "TERRORIST" : "CT");
    for(new i = 0; i < pnum; i++) {
        tempid = players[i];
        new name[32], info[10]; get_user_name(tempid, name, 31); num_to_str(tempid, info, 9);
        menu_additem(menu, name, info);
    }
    menu_display(id, menu);
}

public VoteHandler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[10], access, callback;
    menu_item_getinfo(menu, item, access, data, 9, _, _, callback);
    g_Votes[_:get_member(id, m_iTeam)][str_to_num(data)]++;
    menu_destroy(menu); return PLUGIN_HANDLED;
}

public EndVoteTimer() { EndVote(1); EndVote(2); }

public EndVote(team) {
    if(!g_IsVoting[team]) return;
    g_IsVoting[team] = false;
    new best_id = -1, max_votes = -1, total_votes = 0;
    for(new i = 0; i <= 32; i++) {
        total_votes += g_Votes[team][i];
        if(g_Votes[team][i] > max_votes) { max_votes = g_Votes[team][i]; best_id = i; }
    }
    if(total_votes > 0 && max_votes <= floatround(total_votes / 2.0, floatround_floor) && g_VoteAttempts[team] < 2) {
        g_VoteAttempts[team]++;
        StartVoteForTeam(team); return;
    }
    if(best_id <= 0) {
        g_Commander[team] = 0; DistributeTeamMoney(team);
        client_print_color(0, print_team_default, "^4[TACTICS]^1 Echipa ^3%s^1 joaca ^3FARA COMMANDER^1!", (team == 1) ? "TERO" : "CT");
    } else {
        g_Commander[team] = best_id; CollectMoneyToBank(team);
        NotifyCommander(best_id);
        client_print_color(0, print_team_default, "^4[TACTICS]^3 %n^1 este noul Commander la ^3%s^1!", best_id, (team == 1) ? "TERO" : "CT");
    }
    if(g_GameState == 0) { g_GameState = 1; set_task(FREEZE_TIME - 10.0, "Task_UnfreezePlayers"); }
}

stock CollectMoneyToBank(team) {
    new players[32], pnum; get_players(players, pnum, "e", (team == 1) ? "TERRORIST" : "CT");
    for(new i = 0; i < pnum; i++) { g_TeamMoney[team] += get_member(players[i], m_iAccount); rg_add_account(players[i], 0, AS_SET); }
}

stock DistributeTeamMoney(team) {
    new players[32], pnum; get_players(players, pnum, "e", (team == 1) ? "TERRORIST" : "CT");
    if(pnum > 0) { new share = g_TeamMoney[team] / pnum; for(new i = 0; i < pnum; i++) rg_add_account(players[i], share, AS_ADD); g_TeamMoney[team] = 0; }
}

public Task_UnfreezePlayers() {
    g_GameState = 2; 
    for(new i = 1; i <= 32; i++) if(is_user_alive(i) && !g_ForcedHold[i]) set_entvar(i, var_flags, get_entvar(i, var_flags) & ~FL_FROZEN);
}

public Cmd_ToggleNoclip(id) {
    if(is_user_alive(id) && g_Commander[_:get_member(id, m_iTeam)] == id) {
        new mv = get_entvar(id, var_movetype);
        set_entvar(id, var_movetype, (mv == MOVETYPE_NOCLIP) ? MOVETYPE_WALK : MOVETYPE_NOCLIP);
    }
    return PLUGIN_HANDLED;
}

public Cmd_OpenMainMenu(id) {
    if(!IsModActive()) return PLUGIN_HANDLED;
    new team = _:get_member(id, m_iTeam);
    if(g_Commander[team] != id) return PLUGIN_HANDLED;
    new title[128]; formatex(title, 127, "\yTactics Control Panel^n\wBanca: \r%d$", g_TeamMoney[team]);
    new menu = menu_create(title, "MainHandler");
    menu_additem(menu, "\wCumpara Arme \r(Individual)", "1");
    menu_additem(menu, "\yCumpara Arme \r(ECHIPA)", "2");
    menu_additem(menu, "\wSchimb/Takeover \y(Viu pe Mort)", "3"); 
    menu_additem(menu, "\wTeleportare \y(Regroup)", "4");
    menu_additem(menu, "\wManagement Jucatori", "5");
    menu_additem(menu, "\rSCRIE ORDIN NOU (Chat)", "6");
    menu_additem(menu, "\rMituieste Inamic (8000$)", "7");
    menu_display(id, menu); return PLUGIN_HANDLED;
}

public MainHandler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    switch(item) {
        case 0: ShowPlayerList(id, 1);
        case 1: { g_BuyIsMass[id] = true; Step1_Primary(id); }
        case 2: ShowPlayerList(id, 2); 
        case 3: ShowTeleportMenu(id);
        case 4: ShowManagementMenu(id); 
        case 5: client_cmd(id, "messagemode SetOrder");
        case 6: ShowEnemyList(id);
    }
    menu_destroy(menu); return PLUGIN_HANDLED;
}

public Handle_OrderChat(id) {
    new team = _:get_member(id, m_iTeam);
    if(g_Commander[team] != id) return PLUGIN_HANDLED;
    read_args(g_CurrentOrder[team], 63); remove_quotes(g_CurrentOrder[team]);
    if(strlen(g_CurrentOrder[team]) < 2) formatex(g_CurrentOrder[team], 63, "Asteptare...");
    client_print_color(0, print_team_default, "^4[ORDIN NOU]^1 Commander-ul a ordonat: ^3%s", g_CurrentOrder[team]);
    return PLUGIN_HANDLED;
}

// ====================== CUMPARARE CU CALCUL BANI ======================
stock GetTargetCount(team) {
    new players[32], pnum; get_players(players, pnum, "ae", (team == 1) ? "TERRORIST" : "CT");
    return pnum;
}

public Step1_Primary(id) {
    new team = _:get_member(id, m_iTeam);
    new mult = g_BuyIsMass[id] ? GetTargetCount(team) : 1;
    new menu = menu_create("\yPas 1: Arma Principala:", "HndPrimary");
    
    new str[64]; 
    formatex(str, 63, "AK47 / M4A1 \y[%d$]", 2500 * mult);
    menu_additem(menu, str, "1", 0, (g_TeamMoney[team] < 2500 * mult) ? ITEM_DISABLED : -1);
    
    formatex(str, 63, "AWP \y[%d$]", 4750 * mult);
    menu_additem(menu, str, "2", 0, (g_TeamMoney[team] < 4750 * mult) ? ITEM_DISABLED : -1);
    
    formatex(str, 63, "MP5 Navy \y[%d$]", 1500 * mult);
    menu_additem(menu, str, "3", 0, (g_TeamMoney[team] < 1500 * mult) ? ITEM_DISABLED : -1);
    
    menu_additem(menu, "Fara Arma Principala", "0");
    menu_display(id, menu);
}

public HndPrimary(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[10], access, callback; menu_item_getinfo(menu, item, access, data, 9, _, _, callback);
    g_BuyPrimary[id] = str_to_num(data); menu_destroy(menu); Step2_Pistol(id); return PLUGIN_HANDLED;
}

public Step2_Pistol(id) {
    new team = _:get_member(id, m_iTeam);
    new mult = g_BuyIsMass[id] ? GetTargetCount(team) : 1;
    new menu = menu_create("\yPas 2: Pistol:", "HndPistol");
    new str[64];
    formatex(str, 63, "Desert Eagle \y[%d$]", 650 * mult);
    menu_additem(menu, str, "1", 0, (g_TeamMoney[team] < 650 * mult) ? ITEM_DISABLED : -1);
    formatex(str, 63, "USP \y[%d$]", 500 * mult);
    menu_additem(menu, str, "2", 0, (g_TeamMoney[team] < 500 * mult) ? ITEM_DISABLED : -1);
    menu_additem(menu, "Fara Pistol", "0");
    menu_display(id, menu);
}

public HndPistol(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[10], access, callback; menu_item_getinfo(menu, item, access, data, 9, _, _, callback);
    g_BuyPistol[id] = str_to_num(data); menu_destroy(menu); Step3_Items(id); return PLUGIN_HANDLED;
}

public Step3_Items(id) {
    new team = _:get_member(id, m_iTeam);
    new mult = g_BuyIsMass[id] ? GetTargetCount(team) : 1;
    new menu = menu_create("\yPas 3: Echipament:", "HndItems");
    new str[64];
    formatex(str, 63, "Full (Armor+Nades) \y[%d$]", 1600 * mult);
    menu_additem(menu, str, "1", 0, (g_TeamMoney[team] < 1600 * mult) ? ITEM_DISABLED : -1);
    formatex(str, 63, "Doar Armor \y[%d$]", 1000 * mult);
    menu_additem(menu, str, "2", 0, (g_TeamMoney[team] < 1000 * mult) ? ITEM_DISABLED : -1);
    menu_additem(menu, "Fara Echipament", "0");
    menu_display(id, menu);
}

public HndItems(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[10], access, callback; menu_item_getinfo(menu, item, access, data, 9, _, _, callback);
    new items_choice = str_to_num(data); menu_destroy(menu); FinalizeBuy(id, g_BuyPrimary[id], g_BuyPistol[id], items_choice); return PLUGIN_HANDLED;
}

stock FinalizeBuy(id, prim, sec, items) {
    new team = _:get_member(id, m_iTeam);
    new unit_cost = 0;
    if(prim == 1) unit_cost += 2500; else if(prim == 2) unit_cost += 4750; else if(prim == 3) unit_cost += 1500;
    if(sec == 1) unit_cost += 650; else if(sec == 2) unit_cost += 500;
    if(items == 1) unit_cost += 1600; else if(items == 2) unit_cost += 1000;
    
    new players[32], pnum;
    if(g_BuyIsMass[id]) { get_players(players, pnum, "ae", (team == 1) ? "TERRORIST" : "CT"); } 
    else { players[0] = g_SelectedPlayer[id]; pnum = 1; if(!is_user_alive(players[0])) return; }
    
    new total_cost = unit_cost * pnum;
    if(g_TeamMoney[team] >= total_cost) {
        g_TeamMoney[team] -= total_cost;
        for(new i = 0; i < pnum; i++) {
            new target = players[i]; rg_remove_all_items(target); rg_give_item(target, "weapon_knife");
            if(prim == 1) { rg_give_item(target, team == 1 ? "weapon_ak47" : "weapon_m4a1"); rg_set_user_bpammo(target, team == 1 ? WEAPON_AK47 : WEAPON_M4A1, 90); }
            else if(prim == 2) { rg_give_item(target, "weapon_awp"); rg_set_user_bpammo(target, WEAPON_AWP, 30); }
            else if(prim == 3) { rg_give_item(target, "weapon_mp5navy"); rg_set_user_bpammo(target, WEAPON_MP5N, 120); }
            if(sec == 1) { rg_give_item(target, "weapon_deagle"); rg_set_user_bpammo(target, WEAPON_DEAGLE, 35); }
            else if(sec == 2) { rg_give_item(target, "weapon_usp"); rg_set_user_bpammo(target, WEAPON_USP, 100); }
            else { rg_give_item(target, "weapon_glock18"); rg_set_user_bpammo(target, WEAPON_GLOCK18, 120); }
            if(items == 1 || items == 2) rg_give_item(target, "item_assaultsuit");
            if(items == 1) { rg_give_item(target, "weapon_hegrenade"); rg_give_item(target, "weapon_flashbang"); rg_give_item(target, "weapon_flashbang"); }
        }
    }
    if(is_user_connected(id)) Cmd_OpenMainMenu(id);
}

// [LOGICA TAKEOVER SI MANAGEMENT RAMANE NESCHIMBATA CONFORM CERINTEI]
public ShowPlayerList(id, mode) {
    new team = _:get_member(id, m_iTeam);
    if(mode == 1) { 
        new menu = menu_create("\yAlege jucator pentru Buy:", "BuyPlayerHandler");
        new players[32], pnum, tempid; get_players(players, pnum, "ae", (team == 1) ? "TERRORIST" : "CT");
        for(new i = 0; i < pnum; i++) {
            tempid = players[i]; if(tempid == id) continue;
            new name[32], info[10]; get_user_name(tempid, name, 31); num_to_str(tempid, info, 9);
            menu_additem(menu, name, info);
        }
        menu_display(id, menu);
    } else if(mode == 2) { 
        new menu = menu_create("\yPAS 1: Alege jucator MORT:", "Takeover_Step1_Handler");
        new players[32], pnum, tempid; get_players(players, pnum, "be", (team == 1) ? "TERRORIST" : "CT");
        for(new i = 0; i < pnum; i++) {
            tempid = players[i];
            new name[32], info[10]; get_user_name(tempid, name, 31); num_to_str(tempid, info, 9);
            menu_additem(menu, name, info);
        }
        if(pnum == 0) client_print_color(id, print_team_default, "^4[TACTICS]^1 Nu sunt morti."); else menu_display(id, menu);
    }
}

public Takeover_Step1_Handler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[10], access, callback; menu_item_getinfo(menu, item, access, data, 9, _, _, callback);
    g_TargetTakeover[id] = str_to_num(data); menu_destroy(menu);
    new team = _:get_member(id, m_iTeam);
    new menu2 = menu_create("\yPAS 2: Pe cine sacrifici (VIU)?", "Takeover_Step2_Handler");
    new players[32], pnum, tempid; get_players(players, pnum, "ae", (team == 1) ? "TERRORIST" : "CT");
    for(new i = 0; i < pnum; i++) {
        tempid = players[i];
        new name[32], info[10]; get_user_name(tempid, name, 31); num_to_str(tempid, info, 9);
        menu_additem(menu2, name, info);
    }
    menu_display(id, menu2); return PLUGIN_HANDLED;
}

public Takeover_Step2_Handler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[10], access, callback; menu_item_getinfo(menu, item, access, data, 9, _, _, callback);
    new victim = str_to_num(data), dead_guy = g_TargetTakeover[id];
    if(is_user_alive(victim) && !is_user_alive(dead_guy)) {
        new Float:origin[3], Float:angles[3]; get_entvar(victim, var_origin, origin); get_entvar(victim, var_v_angle, angles);
        user_kill(victim, 1); rg_round_respawn(dead_guy);
        set_entvar(dead_guy, var_origin, origin); set_entvar(dead_guy, var_angles, angles); set_entvar(dead_guy, var_fixangle, 1);
    }
    menu_destroy(menu); return PLUGIN_HANDLED;
}

public BuyPlayerHandler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[10], access, callback; menu_item_getinfo(menu, item, access, data, 9, _, _, callback);
    g_SelectedPlayer[id] = str_to_num(data); g_BuyIsMass[id] = false; Step1_Primary(id); menu_destroy(menu); return PLUGIN_HANDLED;
}

public ShowManagementMenu(id) {
    new team = _:get_member(id, m_iTeam);
    new menu = menu_create("\yManagement Jucatori:", "ManagePlayerHandler");
    new players[32], pnum, tempid; get_players(players, pnum, "ae", (team == 1) ? "TERRORIST" : "CT");
    for(new i = 0; i < pnum; i++) {
        tempid = players[i]; if(tempid == id) continue;
        new name[32], info[10]; get_user_name(tempid, name, 31); num_to_str(tempid, info, 9);
        menu_additem(menu, name, info);
    }
    menu_display(id, menu);
}

public ManagePlayerHandler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[10], access, callback; menu_item_getinfo(menu, item, access, data, 9, _, _, callback);
    g_TargetManage[id] = str_to_num(data); menu_destroy(menu);
    new menuA = menu_create("\yOrdin Fortat:", "ManageActionHandler");
    menu_additem(menuA, "Force HOLD", "1"); menu_additem(menuA, "Force PUSH", "2"); menu_additem(menuA, "Force RETREAT", "3");
    menu_display(id, menuA); return PLUGIN_HANDLED;
}

public ManageActionHandler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new target = g_TargetManage[id];
    if(is_user_alive(target)) {
        switch(item) {
            case 0: { g_ForcedHold[target] = true; set_entvar(target, var_flags, get_entvar(target, var_flags) | FL_FROZEN); }
            case 1: { g_ForcedHold[target] = false; set_entvar(target, var_flags, get_entvar(target, var_flags) & ~FL_FROZEN); }
            case 2: rg_round_respawn(target);
        }
    }
    menu_destroy(menu); return PLUGIN_HANDLED;
}

public ShowTeleportMenu(id) {
    new menu = menu_create("\yTeleportare la tine:", "TeleportHandler");
    menu_additem(menu, "\rToata Echipa", "0");
    new players[32], pnum, tempid; get_players(players, pnum, "ae", (_:get_member(id, m_iTeam) == 1) ? "TERRORIST" : "CT");
    for(new i = 0; i < pnum; i++) {
        tempid = players[i]; if(tempid == id) continue;
        new name[32], info[10]; get_user_name(tempid, name, 31); num_to_str(tempid, info, 9);
        menu_additem(menu, name, info);
    }
    menu_display(id, menu);
}

public TeleportHandler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[10], access, callback; menu_item_getinfo(menu, item, access, data, 9, _, _, callback);
    new target = str_to_num(data); new Float:origin[3]; get_entvar(id, var_origin, origin);
    if(target == 0) {
        new players[32], pnum; get_players(players, pnum, "ae", (_:get_member(id, m_iTeam) == 1) ? "TERRORIST" : "CT");
        for(new i = 0; i < pnum; i++) if(players[i] != id) TeleportPlayer(players[i], origin);
    } else if(is_user_alive(target)) TeleportPlayer(target, origin);
    menu_destroy(menu); return PLUGIN_HANDLED;
}

stock TeleportPlayer(target, Float:origin[3]) {
    new Float:new_origin[3]; new_origin[0] = origin[0] + random_float(-50.0, 50.0); new_origin[1] = origin[1] + random_float(-50.0, 50.0); new_origin[2] = origin[2] + 30.0;
    set_entvar(target, var_origin, new_origin);
}

public ShowEnemyList(id) {
    new team = _:get_member(id, m_iTeam);
    new menu = menu_create("\yMituire Inamic (8000$):", "BribeHandler");
    new players[32], pnum, tempid; get_players(players, pnum, "e", (team == 1) ? "CT" : "TERRORIST");
    for(new i = 0; i < pnum; i++) {
        tempid = players[i]; new name[32], info[10]; get_user_name(tempid, name, 31); num_to_str(tempid, info, 9);
        menu_additem(menu, name, info);
    }
    menu_display(id, menu);
}

public BribeHandler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new team = _:get_member(id, m_iTeam);
    new data[10], access, callback; menu_item_getinfo(menu, item, access, data, 9, _, _, callback);
    new target = str_to_num(data);
    if(is_user_connected(target) && g_TeamMoney[team] >= BRIBE_COST) {
        g_TeamMoney[team] -= BRIBE_COST; rg_set_user_team(target, TeamName:team); rg_round_respawn(target);
    }
    menu_destroy(menu); return PLUGIN_HANDLED;
}

public Task_GlobalHUD() {
    if(!IsModActive()) return;
    for(new i = 1; i <= 32; i++) {
        if(!is_user_connected(i)) continue;
        new team = _:get_member(i, m_iTeam);
        if(team != 1 && team != 2) continue;
        
        if(g_GameState == 0) {
            set_hudmessage(255, 255, 255, -1.0, 0.05, 0, 1.0, 1.1, 0.1, 0.1);
            ShowSyncHudMsg(i, g_HudSync_Phase, "--- FAZA DE VOT ---^nAlege Commander-ul!");
            continue; // Nu mai aratam restul in timpul votului
        }
        
        set_hudmessage(0, 255, 0, 0.02, 0.70, 0, 1.0, 1.1, 0.1, 0.1);
        if(g_Commander[team] == 0) {
            ShowSyncHudMsg(i, g_HudSync_Global, "[TACTICS]^nECHIPA NU ARE COMMANDER^nBanii sunt individuali.");
        } else {
            ShowSyncHudMsg(i, g_HudSync_Global, "[%s]^nBanca: %d$^nOrdin: %s", (g_Commander[team] == i) ? "COMMANDER" : "TACTICS", g_TeamMoney[team], g_CurrentOrder[team]);
        }
    }
}

public RG_PlayerSpawn_Post(id) {
    if(!IsModActive()) return;
    if(is_user_alive(id)) {
        new team = _:get_member(id, m_iTeam);
        if(g_Commander[team] != 0) rg_add_account(id, 0, AS_SET);
        if(g_Commander[team] == id) set_entvar(id, var_movetype, MOVETYPE_NOCLIP);
    }
}
