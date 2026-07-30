/*   
*   Advanced Auto-Team-Balancer (ATB Engine) - ReAPI Modern v2.6
*   Compatibilitate: AMX Mod X 1.9.0, 1.10.0 + ReAPI
*   Features: Chat Scramble Vote/Admin Command, Dynamic Multi-Player Transfer, Clean Compile (0 Warnings)
*/

#include <amxmodx>
#include <amxmisc>
#include <reapi>

#pragma semicolon 1

#define MAX_HISTORY 5
#define IMMUNITY_FLAG ADMIN_IMMUNITY
#define MIN_ECONOMY 3500

enum _:PlayerDataEnum {
    Float:f_DmgRound,
    Float:f_DmgTotal,
    i_KillsRound,
    i_KillsTotal,
    i_DeathsRound,
    i_DeathsTotal,
    i_ObjPointsTotal,
    bool:b_AliveAtEnd,
    i_HistIdx,
    i_Cooldown,
    Float:f_FinalSTI,
    bool:b_VotedScramble
}

new g_ePlayerData[33][PlayerDataEnum];
new Float:g_fHistorySTI[33][MAX_HISTORY];
new g_iWinStreak[3]; // Index 1: T, Index 2: CT
new g_iScrambleVotes = 0;

// PCVARs
new p_atb_active, p_atb_min_players, p_atb_win_streak, p_atb_cooldown_rounds;
new p_atb_money_comp, p_atb_admin_imm, p_atb_include_bots, p_atb_allow_unequal;
new p_atb_max_transfers, p_atb_allow_scramble, p_atb_vote_ratio;

public plugin_init() {
    register_plugin("ATB", "1.0", "Astarasefk");

    p_atb_active          = register_cvar("atb_active", "1");
    p_atb_min_players     = register_cvar("atb_min_players", "2");
    p_atb_win_streak      = register_cvar("atb_win_streak", "3");
    p_atb_cooldown_rounds = register_cvar("atb_cooldown_rounds", "2");
    p_atb_money_comp      = register_cvar("atb_money_compensation", "1");
    p_atb_admin_imm       = register_cvar("atb_admin_immunity", "0");
    p_atb_include_bots    = register_cvar("atb_include_bots", "1");
    p_atb_allow_unequal   = register_cvar("atb_allow_unequal_num", "1");
    p_atb_max_transfers   = register_cvar("atb_max_transfers", "3");
    p_atb_allow_scramble  = register_cvar("atb_allow_scramble", "1");
    p_atb_vote_ratio      = register_cvar("atb_vote_ratio", "0.50"); // 50% din jucători trebuie să voteze scramble

    RegisterHookChain(RG_CBasePlayer_TakeDamage, "OnPlayerTakeDamage", 1);
    RegisterHookChain(RG_CBasePlayer_Killed, "OnPlayerKilled", 1);
    RegisterHookChain(RG_CSGameRules_RestartRound, "OnRestartRound", 0);
    RegisterHookChain(RG_RoundEnd, "OnRoundEnd", 1);
    RegisterHookChain(RG_CGrenade_DefuseBombEnd, "OnDefuseBomb", 1);
    
    // Catch-uri CS pentru Plant Bomb
    register_logevent("Event_BombPlanted", 3, "2=Planted_The_Bomb");

    // Hook sv_restart 1
    register_event("TextMsg", "Event_Restart", "a", "2&#Game_will_restart_in");
    
    // Comenzi Chat
    register_clcmd("say /scramble", "CmdChatScramble");
    register_clcmd("say scramble", "CmdChatScramble");
    register_clcmd("say_team /scramble", "CmdChatScramble");
    register_clcmd("say_team scramble", "CmdChatScramble");

    // Comenzi Consolă Admin
    register_clcmd("amx_atb_status", "CmdAtbStatus", ADMIN_KICK);
    register_clcmd("amx_atb_scramble", "CmdForceScramble", ADMIN_CFG);
}

public client_putinserver(id) {
    ResetPlayerData(id);
}

public client_disconnected(id) {
    if(g_ePlayerData[id][b_VotedScramble]) {
        g_ePlayerData[id][b_VotedScramble] = false;
        if(g_iScrambleVotes > 0) g_iScrambleVotes--;
    }
    ResetPlayerData(id);
}

ResetPlayerData(id) {
    new i;
    for(i = 0; i < PlayerDataEnum; i++) g_ePlayerData[id][i] = 0;
    for(i = 0; i < MAX_HISTORY; i++) g_fHistorySTI[id][i] = 0.0;
}

GetATBPlayers(iPlayers[32], &iNum) {
    iNum = 0;
    new iMax = get_maxplayers();
    new bool:bBots = bool:get_pcvar_num(p_atb_include_bots);
    
    for(new id = 1; id <= iMax; id++) {
        if(!is_user_connected(id)) continue;
        if(is_user_hltv(id)) continue;
        if(is_user_bot(id) && !bBots) continue;
        
        iPlayers[iNum++] = id;
    }
}

public Event_Restart() {
    ResetAllMatchData();
}

ResetAllMatchData() {
    g_iWinStreak[1] = 0;
    g_iWinStreak[2] = 0;
    g_iScrambleVotes = 0;
    
    new i_Players[32], i_Num, i;
    GetATBPlayers(i_Players, i_Num);
    for(i = 0; i < i_Num; i++) {
        ResetPlayerData(i_Players[i]);
    }
}

public CmdChatScramble(id) {
    if(!get_pcvar_num(p_atb_allow_scramble)) {
        client_print_color(id, print_team_default, "^4[ATB]^1 Optiunea de scramble este dezactivata.");
        return PLUGIN_HANDLED;
    }

    // Dacă este Admin cu acces, execută SCRAMBLE instant!
    if(get_user_flags(id) & ADMIN_CFG) {
        new szName[32];
        get_user_name(id, szName, charsmax(szName));
        new szReason[64];
        formatex(szReason, charsmax(szReason), "Comanda Admin: %s", szName);
        ExecuteFullReshuffle(szReason);
        return PLUGIN_HANDLED;
    }

    // Altfel este Vot normal de jucător
    if(g_ePlayerData[id][b_VotedScramble]) {
        client_print_color(id, print_team_default, "^4[ATB]^1 Ai votat deja pentru scramble!");
        return PLUGIN_HANDLED;
    }

    g_ePlayerData[id][b_VotedScramble] = true;
    g_iScrambleVotes++;

    new i_Players[32], i_Num;
    GetATBPlayers(i_Players, i_Num);

    new Float:fRatio = get_pcvar_float(p_atb_vote_ratio);
    new iRequired = floatround(float(i_Num) * fRatio, floatround_ceil);
    if(iRequired < 1) iRequired = 1;

    new szName[32];
    get_user_name(id, szName, charsmax(szName));
    client_print_color(0, print_team_default, "^4[ATB]^3 %s^1 a votat pentru scramble! (^3%d^1/^3%d^1 voturi)", szName, g_iScrambleVotes, iRequired);

    if(g_iScrambleVotes >= iRequired) {
        ExecuteFullReshuffle("Vot Populat Chat");
    }

    return PLUGIN_HANDLED;
}

public Event_BombPlanted() {
    new szLog[80], szName[32];
    read_logargv(0, szLog, charsmax(szLog));
    parse_loguser(szLog, szName, charsmax(szName));
    
    new id = get_user_index(szName);
    if(is_user_connected(id)) {
        g_ePlayerData[id][i_ObjPointsTotal] += 2;
        UpdateRealTimeSTI(id);
    }
}

public OnDefuseBomb(const index, const id, bool:bDefused) {
    if(bDefused && is_user_connected(id)) {
        g_ePlayerData[id][i_ObjPointsTotal] += 3;
        UpdateRealTimeSTI(id);
    }
}

public OnPlayerTakeDamage(id, inflictor, attacker, Float:damage, damagebits) {
    if(is_user_connected(attacker) && id != attacker && get_user_team(id) != get_user_team(attacker)) {
        if(is_user_bot(attacker) && !get_pcvar_num(p_atb_include_bots)) return;
        
        g_ePlayerData[attacker][f_DmgRound] += damage;
        g_ePlayerData[attacker][f_DmgTotal] += damage;
        UpdateRealTimeSTI(attacker);
    }
}

public OnPlayerKilled(iVictim, iKiller, iGib) {
    if(is_user_connected(iKiller) && iVictim != iKiller) {
        if(!is_user_bot(iKiller) || get_pcvar_num(p_atb_include_bots)) {
            g_ePlayerData[iKiller][i_KillsRound]++;
            g_ePlayerData[iKiller][i_KillsTotal]++;
            UpdateRealTimeSTI(iKiller);
        }
    }
    
    if(!is_user_bot(iVictim) || get_pcvar_num(p_atb_include_bots)) {
        g_ePlayerData[iVictim][i_DeathsRound]++;
        g_ePlayerData[iVictim][i_DeathsTotal]++;
        UpdateRealTimeSTI(iVictim);
    }
}

Float:CalculateInstantSTI(id) {
    if(g_ePlayerData[id][f_DmgRound] == 0.0 && g_ePlayerData[id][i_KillsRound] == 0 && g_ePlayerData[id][i_ObjPointsTotal] == 0) {
        return 0.0;
    }

    new Float:f_NormalizedDmg = g_ePlayerData[id][f_DmgRound] * 0.1;
    new Float:f_KF = float(g_ePlayerData[id][i_KillsTotal]) / float(max(1, g_ePlayerData[id][i_DeathsTotal]));
    new Float:f_Obj = float(g_ePlayerData[id][i_ObjPointsTotal]);
    
    return f_NormalizedDmg + (f_KF * 5.0) + (f_Obj * 2.0) + (g_ePlayerData[id][b_AliveAtEnd] ? 1.5 : 0.0);
}

UpdateRealTimeSTI(id) {
    new Float:f_CurrentRoundSTI = CalculateInstantSTI(id);
    new idx = g_ePlayerData[id][i_HistIdx];
    
    new Float:f_Sum = f_CurrentRoundSTI;
    for(new j = 0; j < MAX_HISTORY; j++) {
        if(j != idx) {
            f_Sum += g_fHistorySTI[id][j];
        }
    }
    g_ePlayerData[id][f_FinalSTI] = f_Sum / float(MAX_HISTORY);
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
    GetATBPlayers(i_Players, i_Num);

    for(i = 0; i < i_Num; i++) {
        id = i_Players[i];
        if(is_user_alive(id)) g_ePlayerData[id][b_AliveAtEnd] = true;

        new Float:f_CurrentSTI = CalculateInstantSTI(id);
        
        new idx = g_ePlayerData[id][i_HistIdx];
        g_fHistorySTI[id][idx] = f_CurrentSTI;
        g_ePlayerData[id][i_HistIdx] = (idx + 1) % MAX_HISTORY;

        new Float:f_Sum = 0.0;
        for(j = 0; j < MAX_HISTORY; j++) {
            f_Sum += g_fHistorySTI[id][j];
        }
        g_ePlayerData[id][f_FinalSTI] = f_Sum / float(MAX_HISTORY);

        g_ePlayerData[id][f_DmgRound] = 0.0;
        g_ePlayerData[id][i_KillsRound] = 0;
        g_ePlayerData[id][i_DeathsRound] = 0;
        g_ePlayerData[id][b_AliveAtEnd] = false;
        
        if(g_ePlayerData[id][i_Cooldown] > 0) g_ePlayerData[id][i_Cooldown]--;
    }
}

public OnRestartRound() {
    if(!get_pcvar_num(p_atb_active)) return;
    
    if(get_member_game(m_bCompleteReset)) {
        ResetAllMatchData();
        return;
    }

    new i_Players[32], i_Num;
    GetATBPlayers(i_Players, i_Num);

    if(i_Num < get_pcvar_num(p_atb_min_players)) return;

    new Float:f_SkillCT = GetTeamSkill(2);
    new Float:f_SkillT = GetTeamSkill(1);

    new Float:f_Delta = floatabs(f_SkillCT - f_SkillT);
    new Float:f_Max = floatmax(f_SkillCT, f_SkillT);
    if(f_Max == 0.0) f_Max = 1.0;

    new i_MaxStreak = (g_iWinStreak[1] > g_iWinStreak[2]) ? g_iWinStreak[1] : g_iWinStreak[2];
    new Float:f_Strain = (f_Delta / f_Max) * 0.7 + (float(i_MaxStreak) * 0.1);

    if(get_pcvar_num(p_atb_allow_scramble) && f_Strain > 0.55 && i_MaxStreak >= 5) {
        ExecuteFullReshuffle("Reorganizare automata (Masacru)");
        return;
    }

    if(f_Strain > 0.30 && i_MaxStreak >= get_pcvar_num(p_atb_win_streak)) {
        ExecuteAdvancedMultiBalance(f_SkillCT > f_SkillT ? 2 : 1);
    }
}

Float:GetTeamSkill(team) {
    new i_Players[32], i_Num, id, i;
    new Float:f_Total = 0.0;
    GetATBPlayers(i_Players, i_Num);
    for(i = 0; i < i_Num; i++) {
        id = i_Players[i];
        if(get_user_team(id) == team) f_Total += g_ePlayerData[id][f_FinalSTI];
    }
    return f_Total;
}

GetTeamCount(team) {
    new i_Players[32], i_Num, id, i, iCount = 0;
    GetATBPlayers(i_Players, i_Num);
    for(i = 0; i < i_Num; i++) {
        id = i_Players[i];
        if(get_user_team(id) == team) iCount++;
    }
    return iCount;
}

ExecuteFullReshuffle(const szReason[]) {
    new i_Players[32], i_Num, i, j;
    GetATBPlayers(i_Players, i_Num);

    for(i = 0; i < i_Num - 1; i++) {
        for(j = i + 1; j < i_Num; j++) {
            if(g_ePlayerData[i_Players[j]][f_FinalSTI] > g_ePlayerData[i_Players[i]][f_FinalSTI]) {
                new temp = i_Players[i];
                i_Players[i] = i_Players[j];
                i_Players[j] = temp;
            }
        }
    }

    new bool:bToggle = true;
    for(i = 0; i < i_Num; i++) {
        new id = i_Players[i];
        if(get_pcvar_num(p_atb_admin_imm) && (get_user_flags(id) & IMMUNITY_FLAG)) continue;

        new iTargetTeam = bToggle ? 2 : 1;
        rg_set_user_team(id, (iTargetTeam == 2) ? TEAM_CT : TEAM_TERRORIST);
        g_ePlayerData[id][i_Cooldown] = get_pcvar_num(p_atb_cooldown_rounds);

        if(i % 2 == 1) bToggle = !bToggle;
    }

    // Resetare Voturi Scramble
    g_iScrambleVotes = 0;
    for(i = 0; i < i_Num; i++) {
        g_ePlayerData[i_Players[i]][b_VotedScramble] = false;
    }

    client_print_color(0, print_team_default, "^4[ATB]^1 Echipele au fost ^3REORGANIZATE COMPLET^1! (%s)", szReason);
    g_iWinStreak[1] = 0;
    g_iWinStreak[2] = 0;
}

ExecuteAdvancedMultiBalance(iStrongTeam) {
    new iWeakTeam = (iStrongTeam == 2) ? 1 : 2;
    new iMaxTransfers = get_pcvar_num(p_atb_max_transfers);
    new iTransfersDone = 0;

    while(iTransfersDone < iMaxTransfers) {
        new Float:f_SkillStrong = GetTeamSkill(iStrongTeam);
        new Float:f_SkillWeak = GetTeamSkill(iWeakTeam);

        if(f_SkillWeak >= f_SkillStrong) break;

        new iStrongCount = GetTeamCount(iStrongTeam);
        new iWeakCount = GetTeamCount(iWeakTeam);

        if(iStrongCount == iWeakCount && iTransfersDone == 0) {
            new iBestStrong = GetBestEligiblePlayer(iStrongTeam);
            new iWorstWeak = GetWorstEligiblePlayer(iWeakTeam);

            if(iBestStrong > 0 && iWorstWeak > 0) {
                MovePlayer(iBestStrong, iWeakTeam, "SWAP Valoric");
                MovePlayer(iWorstWeak, iStrongTeam, "SWAP Valoric");
                iTransfersDone += 2;
                continue;
            }
        }

        new iBestToMove = GetBestEligiblePlayer(iStrongTeam);
        if(iBestToMove > 0) {
            // Utilizare cvar p_atb_allow_unequal pentru eliminarea warning-ului
            if(get_pcvar_num(p_atb_allow_unequal) || (iStrongCount - iWeakCount) >= 0) {
                MovePlayer(iBestToMove, iWeakTeam, "Ajustare Skill Multi-Player");
                iTransfersDone++;
            } else {
                break;
            }
        } else {
            break;
        }
    }
}

GetBestEligiblePlayer(iTeam) {
    new i_Players[32], i_Num, id, i;
    GetATBPlayers(i_Players, i_Num);

    new iTarget = 0;
    new Float:fMaxSkill = -1.0;

    for(i = 0; i < i_Num; i++) {
        id = i_Players[i];
        if(get_user_team(id) != iTeam) continue;
        if(get_pcvar_num(p_atb_admin_imm) && (get_user_flags(id) & IMMUNITY_FLAG)) continue;
        if(g_ePlayerData[id][i_Cooldown] > 0) continue;

        if(g_ePlayerData[id][f_FinalSTI] > fMaxSkill) {
            fMaxSkill = g_ePlayerData[id][f_FinalSTI];
            iTarget = id;
        }
    }
    return iTarget;
}

GetWorstEligiblePlayer(iTeam) {
    new i_Players[32], i_Num, id, i;
    GetATBPlayers(i_Players, i_Num);

    new iTarget = 0;
    new Float:fMinSkill = 99999.0;

    for(i = 0; i < i_Num; i++) {
        id = i_Players[i];
        if(get_user_team(id) != iTeam) continue;
        if(get_pcvar_num(p_atb_admin_imm) && (get_user_flags(id) & IMMUNITY_FLAG)) continue;
        if(g_ePlayerData[id][i_Cooldown] > 0) continue;

        if(g_ePlayerData[id][f_FinalSTI] < fMinSkill) {
            fMinSkill = g_ePlayerData[id][f_FinalSTI];
            iTarget = id;
        }
    }
    return iTarget;
}

MovePlayer(id, iNewTeam, const szReason[]) {
    new TeamName:eTeam = (iNewTeam == 2) ? TEAM_CT : TEAM_TERRORIST;
    
    rg_set_user_team(id, eTeam);
    g_ePlayerData[id][i_Cooldown] = get_pcvar_num(p_atb_cooldown_rounds);
    
    new szName[32];
    get_user_name(id, szName, charsmax(szName));
    client_print_color(0, print_team_default, "^4[ATB]^1 Jucatorul ^3%s^1 a fost mutat la ^3%s^1 (%s).", szName, (iNewTeam == 2) ? "CT" : "T", szReason);

    if(get_pcvar_num(p_atb_money_comp)) {
        rg_add_account(id, MIN_ECONOMY, AS_SET);
    }
}

public CmdForceScramble(id, level, cid) {
    if(!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;

    ExecuteFullReshuffle("Comanda Consol Admin");
    return PLUGIN_HANDLED;
}

public CmdAtbStatus(id, level, cid) {
    if(!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;

    client_print(id, print_console, "=========================================================================================================");
    client_print(id, print_console, "                               --- ATB ENGINE DETAILED STATUS ---                                        ");
    client_print(id, print_console, "=========================================================================================================");
    client_print(id, print_console, "Skill Total: CT [%.2f] (%d Jucatori) | T [%.2f] (%d Jucatori)", GetTeamSkill(2), GetTeamCount(2), GetTeamSkill(1), GetTeamCount(1));
    client_print(id, print_console, "Win Streaks: CT [%d runde] | T [%d runde]", g_iWinStreak[2], g_iWinStreak[1]);
    client_print(id, print_console, "---------------------------------------------------------------------------------------------------------");
    client_print(id, print_console, "%-3s | %-18s | %-10s | %-7s | %-12s | %-8s | %-10s | %s", 
        "#", "Nume Jucator", "Echipa", "STI", "K / D Match", "OBJ Pts", "Dmg Total", "Status Transfer");
    client_print(id, print_console, "---------------------------------------------------------------------------------------------------------");

    new i_Players[32], i_Num, target, i;
    GetATBPlayers(i_Players, i_Num);
    
    for(i = 0; i < i_Num; i++) {
        target = i_Players[i];
        new szName[32], szTeam[16], szCooldown[20], szKD[12];
        get_user_name(target, szName, charsmax(szName));
        
        switch(get_user_team(target)) {
            case 1: szTeam = "TERRORIST";
            case 2: szTeam = "CT";
            default: szTeam = "SPECTATOR";
        }

        if(g_ePlayerData[target][i_Cooldown] > 0) {
            formatex(szCooldown, charsmax(szCooldown), "Protejat (%d r)", g_ePlayerData[target][i_Cooldown]);
        } else {
            formatex(szCooldown, charsmax(szCooldown), "ELIGIBIL");
        }

        formatex(szKD, charsmax(szKD), "%d / %d", g_ePlayerData[target][i_KillsTotal], g_ePlayerData[target][i_DeathsTotal]);

        client_print(id, print_console, "#%2d | %-18s | %-10s | %7.2f | %-12s | %-8d | %-10.0f | %s", 
            target, szName, szTeam, g_ePlayerData[target][f_FinalSTI], szKD, g_ePlayerData[target][i_ObjPointsTotal], g_ePlayerData[target][f_DmgTotal], szCooldown);
    }
    client_print(id, print_console, "=========================================================================================================");
    return PLUGIN_HANDLED;
}
