/*  
*   Advanced Auto-Team-Balancer (ATB) - ReAPI Modern
*   Fixat & Optimizat
*/

#include <amxmodx>
#include <amxmisc>
#include <reapi>

#pragma semicolon 1

#define MAX_HISTORY 5
#define IMMUNITY_FLAG ADMIN_IMMUNITY
#define MIN_ECONOMY 3500

enum _:PlayerDataEnum {
    Float:f_DmgDealt,
    i_Kills,
    i_Deaths,
    i_ObjPoints,
    bool:b_AliveAtEnd,
    i_HistIdx,
    i_Cooldown,
    Float:f_FinalSTI
}

new g_ePlayerData[33][PlayerDataEnum];
new Float:g_fHistorySTI[33][MAX_HISTORY];
new g_iWinStreak[3]; // Index 1: T, Index 2: CT

// PCVARs
new p_atb_active, p_atb_min_players, p_atb_win_streak, p_atb_cooldown_rounds;
new p_atb_money_comp, p_atb_admin_imm;

public plugin_init() {
    register_plugin("Advanced ReAPI ATB", "1.0", "Astarasefk");

    p_atb_active          = register_cvar("atb_active", "1");
    p_atb_min_players     = register_cvar("atb_min_players", "6");
    p_atb_win_streak      = register_cvar("atb_win_streak", "3");
    p_atb_cooldown_rounds = register_cvar("atb_cooldown_rounds", "5");
    p_atb_money_comp      = register_cvar("atb_money_compensation", "1");
    p_atb_admin_imm       = register_cvar("atb_admin_immunity", "0");

    RegisterHookChain(RG_CBasePlayer_TakeDamage, "OnPlayerTakeDamage", 1);
    RegisterHookChain(RG_CBasePlayer_Killed, "OnPlayerKilled", 1);
    RegisterHookChain(RG_CSGameRules_RestartRound, "OnRestartRound", 0);
    RegisterHookChain(RG_RoundEnd, "OnRoundEnd", 1);
    
    register_clcmd("amx_atb_status", "CmdAtbStatus", ADMIN_KICK);
}

public client_putinserver(id) {
    ResetPlayerData(id);
}

public client_disconnected(id) {
    ResetPlayerData(id);
}

ResetPlayerData(id) {
    new i;
    for(i = 0; i < PlayerDataEnum; i++) g_ePlayerData[id][i] = 0;
    for(i = 0; i < MAX_HISTORY; i++) g_fHistorySTI[id][i] = 0.0;
}

public OnPlayerTakeDamage(id, inflictor, attacker, Float:damage, damagebits) {
    if(is_user_connected(attacker) && id != attacker && get_user_team(id) != get_user_team(attacker)) {
        g_ePlayerData[attacker][f_DmgDealt] += damage;
    }
}

public OnPlayerKilled(iVictim, iKiller, iGib) {
    if(is_user_connected(iKiller) && iVictim != iKiller) {
        g_ePlayerData[iKiller][i_Kills]++;
    }
    g_ePlayerData[iVictim][i_Deaths]++;
}

Float:CalculateInstantSTI(id) {
    // Normalizăm damage-ul: 100 dmg = 10 puncte de skill
    new Float:f_NormalizedDmg = g_ePlayerData[id][f_DmgDealt] * 0.1; 
    
    // Kill / Death Ratio balansat
    new Float:f_KF = float(g_ePlayerData[id][i_Kills] + 1) / float(g_ePlayerData[id][i_Deaths] + 1);
    new Float:f_Obj = float(g_ePlayerData[id][i_ObjPoints]);
    
    return f_NormalizedDmg + (f_KF * 8.0) + (f_Obj * 5.0) + (g_ePlayerData[id][b_AliveAtEnd] ? 3.0 : 0.0);
}

public OnRoundEnd(WinStatus:status) {
    if(!get_pcvar_num(p_atb_active)) return;

    if(status == WINSTATUS_CTS) {
        g_iWinStreak[2]++; 
        g_iWinStreak[1] = 0;
    } else if(status == WINSTATUS_TERRORISTS) {
        g_iWinStreak[1]++; 
        g_iWinStreak[2] = 0;
    }

    new i_Players[32], i_Num, id, i, j;
    get_players(i_Players, i_Num, "ch");

    for(i = 0; i < i_Num; i++) {
        id = i_Players[i];
        if(is_user_alive(id)) g_ePlayerData[id][b_AliveAtEnd] = true;

        new Float:f_CurrentSTI = CalculateInstantSTI(id);
        
        // Salvăm în istoric
        new idx = g_ePlayerData[id][i_HistIdx];
        g_fHistorySTI[id][idx] = f_CurrentSTI;
        g_ePlayerData[id][i_HistIdx] = (idx + 1) % MAX_HISTORY;

        // Calculăm media ultimelor runde
        new Float:f_Sum = 0.0;
        for(j = 0; j < MAX_HISTORY; j++) {
            f_Sum += g_fHistorySTI[id][j];
        }
        g_ePlayerData[id][f_FinalSTI] = f_Sum / float(MAX_HISTORY);

        // Resetăm datele rundei
        g_ePlayerData[id][f_DmgDealt] = 0.0;
        g_ePlayerData[id][i_Kills] = 0;
        g_ePlayerData[id][i_Deaths] = 0;
        g_ePlayerData[id][i_ObjPoints] = 0;
        g_ePlayerData[id][b_AliveAtEnd] = false;
        
        if(g_ePlayerData[id][i_Cooldown] > 0) g_ePlayerData[id][i_Cooldown]--;
    }
}

public OnRestartRound() {
    if(!get_pcvar_num(p_atb_active)) return;
    
    // Resetăm winstreak la Game Commencing
    if(get_member_game(m_bCompleteReset)) {
        g_iWinStreak[1] = 0;
        g_iWinStreak[2] = 0;
        return;
    }

    if(get_playersnum() < get_pcvar_num(p_atb_min_players)) return;

    new Float:f_SkillCT = GetTeamSkill(2);
    new Float:f_SkillT = GetTeamSkill(1);

    new Float:f_Delta = floatabs(f_SkillCT - f_SkillT);
    new Float:f_Max = floatmax(f_SkillCT, f_SkillT);
    if(f_Max == 0.0) f_Max = 1.0;

    new i_MaxStreak = (g_iWinStreak[1] > g_iWinStreak[2]) ? g_iWinStreak[1] : g_iWinStreak[2];
    new Float:f_Strain = (f_Delta / f_Max) * 0.7 + (float(i_MaxStreak) * 0.1);

    if(f_Strain > 0.35 && i_MaxStreak >= get_pcvar_num(p_atb_win_streak)) {
        BalanceAction(f_SkillCT > f_SkillT ? 2 : 1);
    }
}

Float:GetTeamSkill(team) {
    new i_Players[32], i_Num, id, i;
    new Float:f_Total = 0.0;
    get_players(i_Players, i_Num, "ch");
    for(i = 0; i < i_Num; i++) {
        id = i_Players[i];
        if(get_user_team(id) == team) f_Total += g_ePlayerData[id][f_FinalSTI];
    }
    return f_Total;
}

BalanceAction(iStrongTeam) {
    new iWeakTeam = (iStrongTeam == 2) ? 1 : 2;
    new i_StrongPlayers[32], i_SCount = 0;
    new i_Players[32], i_Num, id, i;
    
    get_players(i_Players, i_Num, "ch");
    for(i = 0; i < i_Num; i++) {
        id = i_Players[i];
        if(get_user_team(id) != iStrongTeam) continue;
        if(get_pcvar_num(p_atb_admin_imm) && (get_user_flags(id) & IMMUNITY_FLAG)) continue;
        if(g_ePlayerData[id][i_Cooldown] > 0) continue;
        
        i_StrongPlayers[i_SCount++] = id;
    }

    if(i_SCount == 0) return;

    // Căutăm cel mai bun jucător eligibil
    new iTarget = i_StrongPlayers[0];
    for(i = 1; i < i_SCount; i++) {
        if(g_ePlayerData[i_StrongPlayers[i]][f_FinalSTI] > g_ePlayerData[iTarget][f_FinalSTI])
            iTarget = i_StrongPlayers[i];
    }

    MovePlayer(iTarget, iWeakTeam);
}

MovePlayer(id, iNewTeam) {
    new TeamName:eTeam = (iNewTeam == 2) ? TEAM_CT : TEAM_TERRORIST;
    
    rg_set_user_team(id, eTeam);
    g_ePlayerData[id][i_Cooldown] = get_pcvar_num(p_atb_cooldown_rounds);
    
    new szName[32];
    get_user_name(id, szName, charsmax(szName));
    client_print_color(0, print_team_default, "^4[ATB]^1 Jucatorul ^3%s^1 a fost mutat la ^3%s^1 pentru echilibrare.", szName, (iNewTeam == 2) ? "CT" : "T");

    if(get_pcvar_num(p_atb_money_comp)) {
        rg_add_account(id, MIN_ECONOMY, AS_SET);
    }
}

public CmdAtbStatus(id, level, cid) {
    if(!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;

    client_print(id, print_console, "--- ATB Engine Status ---");
    client_print(id, print_console, "Skill CT: %.2f | Skill T: %.2f", GetTeamSkill(2), GetTeamSkill(1));
    client_print(id, print_console, "Win Streak: CT %d - T %d", g_iWinStreak[2], g_iWinStreak[1]);
    
    new i_Players[32], i_Num, target, i;
    get_players(i_Players, i_Num, "ch");
    for(i = 0; i < i_Num; i++) {
        target = i_Players[i];
        new szName[32]; get_user_name(target, szName, charsmax(szName));
        client_print(id, print_console, "[%s] STI: %.2f | Cooldown: %d", szName, g_ePlayerData[target][f_FinalSTI], g_ePlayerData[target][i_Cooldown]);
    }
    return PLUGIN_HANDLED;
}
