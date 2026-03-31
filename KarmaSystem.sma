#include <amxmodx>
#include <amxmisc>
#include <nvault>
#include <nvault_util>
#include <cellarray>

#define PLUGIN "Karma System"
#define VERSION "1.0"
#define AUTHOR "AI"

new gCvar_ConnectBonus;
new gVault;
new g_iKarma[33];
new bool:g_bUsedRep[33]; 

// To store which player was selected in the first menu
new g_iMenuTarget[33];

enum _:TopDataStruct {
    TD_PLAYERNAME[32],
    TD_PLAYERKARMA
};

enum _:RankStruct {
    RK_VALUE,
    RK_NAME[32]
};

new const g_Ranks[][RankStruct] = {
    {100, "Saint"}, {70, "King"}, {50, "Noble"}, {30,  "Knight"},
    {10,  "Squire"}, {0,  "Peasant"}, {-1, "Thief"}, {-20,"Bandit"},
    {-40,"Assassin"}, {-70,"Warlock"}, {-100,"Demon"}
};

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    gCvar_ConnectBonus = register_cvar("karma_connect_bonus", "1");

    register_clcmd("say /karma", "Cmd_KarmaMenu");
    register_clcmd("say /karmas", "Cmd_OnlineList");
    register_clcmd("say /karmatop", "Cmd_GlobalTop");
    
    // New Commands
    register_clcmd("say /km", "Cmd_QuickKarma");
    register_clcmd("say /kmhelp", "Cmd_Help");

    register_event("HLTV", "Event_RoundStart", "a", "1=0", "2=0");

    gVault = nvault_open("medieval_karma");
    if(gVault == INVALID_HANDLE) set_fail_state("Vault error!");
}

public Event_RoundStart()
{
    // Get the actual max slots of the server (e.g., 20, 24, or 32)
    new iMaxPlayers = get_maxplayers();

    for(new i = 1; i <= iMaxPlayers; i++)
    {
        g_bUsedRep[i] = false;
    }
}
public client_putinserver(id)
{
    LoadKarma(id);
    g_bUsedRep[id] = false;
    
    new bonus = get_pcvar_num(gCvar_ConnectBonus);
    if (bonus > 0)
    {
        g_iKarma[id] += bonus;
        SaveKarma(id);
    }
}

public client_disconnected(id) SaveKarma(id);

public client_infochanged(id)
{
    if(!is_user_connected(id)) return;
    new oldname[32], newname[32];
    get_user_name(id, oldname, charsmax(oldname));
    get_user_info(id, "name", newname, charsmax(newname));
    if(!equal(oldname, newname)) LoadKarma(id);
}

// ========================================
// QUICK COMMANDS (/km & /kmhelp)
// ========================================

public Cmd_QuickKarma(id)
{
    new szRank[32];
    GetRank(g_iKarma[id], szRank, charsmax(szRank));
    client_print_color(id, print_team_default, "^1[^3Karma^1] Your Rank: ^4%s ^1| Karma points: ^4%d", szRank, g_iKarma[id]);
    return PLUGIN_HANDLED;
}

public Cmd_Help(id)
{
    new motd[2048], len;
    len += formatex(motd[len], charsmax(motd) - len, "<body bgcolor=#121212 style='color:#e0e0e0; font-family: Tahoma, sans-serif;'>");
    len += formatex(motd[len], charsmax(motd) - len, "<h1 style='color:#d4af37; text-align:center;'>Medieval Karma System</h1><hr style='border: 1px solid #d4af37;'>");
    len += formatex(motd[len], charsmax(motd) - len, "<p>Welcome to the realm! Your reputation dictates your Medieval Rank. Respect others, or become a Demon.</p>");
    len += formatex(motd[len], charsmax(motd) - len, "<h3 style='color:#d4af37;'>Commands:</h3>");
    len += formatex(motd[len], charsmax(motd) - len, "<ul>");
    len += formatex(motd[len], charsmax(motd) - len, "<li><b>/km</b> - Silently check your current Rank and Karma points.</li>");
    len += formatex(motd[len], charsmax(motd) - len, "<li><b>/karma</b> - Opens the Voting Menu. You can vote for a player once per round. <i>(Warning: Voting costs you 1 Karma point)</i></li>");
    len += formatex(motd[len], charsmax(motd) - len, "<li><b>/karmas</b> - Shows the Online Players Leaderboard.</li>");
    len += formatex(motd[len], charsmax(motd) - len, "<li><b>/karmatop</b> - Shows the Global Top 15 Players.</li>");
    len += formatex(motd[len], charsmax(motd) - len, "</ul>");
    len += formatex(motd[len], charsmax(motd) - len, "<h3 style='color:#d4af37;'>Rank Ladder:</h3>");
    len += formatex(motd[len], charsmax(motd) - len, "<p style='font-size: 12px; color:#a0a0a0;'>");
    len += formatex(motd[len], charsmax(motd) - len, "Demon (-100) &raquo; Warlock (-70) &raquo; Assassin (-40) &raquo; Bandit (-20) &raquo; Thief (-1) &raquo; Peasant (0)<br><br>");
    len += formatex(motd[len], charsmax(motd) - len, "Squire (10) &raquo; Knight (30) &raquo; Noble (50) &raquo; King (70) &raquo; Saint (100)");
    len += formatex(motd[len], charsmax(motd) - len, "</p></body>");
    
    show_motd(id, motd, "Karma Help");
    return PLUGIN_HANDLED;
}

// ========================================
// THE MAIN MENU (/karma)
// ========================================

public Cmd_KarmaMenu(id)
{
    if(g_bUsedRep[id])
    {
        client_print_color(id, print_team_default, "^1[^3Karma^1] ^4You already voted this round!");
        return PLUGIN_HANDLED;
    }

    new szRank[32];
    GetRank(g_iKarma[id], szRank, charsmax(szRank));

    new szTitle[128];
    formatex(szTitle, charsmax(szTitle), "\yKarma System^n\wRank: \r%s \w| Karma: \r%d^n\wSelect a Player:", szRank, g_iKarma[id]);

    new menu = menu_create(szTitle, "Handle_KarmaMenu");

    new players[32], pnum, szName[32], szUserId[10];
    get_players(players, pnum, "h");

    new added_players = 0;

    for (new i = 0; i < pnum; i++)
    {
        new target = players[i];
        if (target == id) continue; // Don't show yourself

        get_user_name(target, szName, charsmax(szName));
        num_to_str(get_user_userid(target), szUserId, charsmax(szUserId));
        menu_additem(menu, szName, szUserId, 0);
        added_players++;
    }

    if (added_players == 0)
    {
        client_print_color(id, print_team_default, "^1[^3Karma^1] ^4There are no other players to vote for.");
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public Handle_KarmaMenu(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[10], name[32], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), name, charsmax(name), callback);

    new userid = str_to_num(data);
    new target = find_player("k", userid);

    if (target)
    {
        g_iMenuTarget[id] = target;
        ShowVoteSubMenu(id);
    }
    else
    {
        client_print_color(id, print_team_default, "^4[Karma] ^1Player left the ^3server.");
    }

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// ========================================
// SUB-MENU (Positive or Negative)
// ========================================

public ShowVoteSubMenu(id)
{
    new target = g_iMenuTarget[id];
    if(!is_user_connected(target)) return;

    new szTargetName[32], szTitle[64];
    get_user_name(target, szTargetName, charsmax(szTargetName));
    formatex(szTitle, charsmax(szTitle), "Vote for \r%s:", szTargetName);

    new menu = menu_create(szTitle, "Handle_SubMenu");
    menu_additem(menu, "Give Positive (+1)", "1");
    menu_additem(menu, "Give Negative (-1)", "2");

    menu_display(id, menu, 0);
}

public Handle_SubMenu(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new target = g_iMenuTarget[id];
    if (!is_user_connected(target))
    {
        client_print_color(id, print_team_default, "^1[^3Karma^1] Target no longer online.");
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[10], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), _, _, callback);

    new choice = str_to_num(data);
    new tName[32]; get_user_name(target, tName, charsmax(tName));

    if (choice == 1)
    {
        g_iKarma[target] += 1;
        client_print_color(0, print_team_default, "^1[^3Karma^1] ^4%s^1 received ^4+1^1 reputation!", tName);
    }
    else if (choice == 2)
    {
        g_iKarma[target] -= 1;
        client_print_color(0, print_team_default, "^1[^4Karma^1] ^4%s^1 received^4 -1^1 reputation!", tName);
    }

    // Cost to the Voter
    g_iKarma[id] -= 1;
    client_print_color(id, print_team_default, "^1[^4Karma^1] You spent^4 1^1 Karma to vote.");

    SaveKarma(target);
    SaveKarma(id);
    g_bUsedRep[id] = true;
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// ========================================
// ONLINE TOP (/karmas)
// ========================================

public Cmd_OnlineList(id)
{
    new Array:aOnline = ArrayCreate(TopDataStruct);
    new eData[TopDataStruct];
    new players[32], pnum;
    
    get_players(players, pnum, "h");

    for (new i = 0; i < pnum; i++)
    {
        new player = players[i];
        get_user_name(player, eData[TD_PLAYERNAME], charsmax(eData[TD_PLAYERNAME]));
        eData[TD_PLAYERKARMA] = g_iKarma[player];
        ArrayPushArray(aOnline, eData);
    }

    if (ArraySize(aOnline) == 0)
    {
        ArrayDestroy(aOnline);
        return PLUGIN_HANDLED;
    }

    ArraySort(aOnline, "Sort_TopData");

    new motd[2048], len;
    len += formatex(motd[len], charsmax(motd) - len, "<body bgcolor=black style='color:white;font-family:Tahoma;'>");
    len += formatex(motd[len], charsmax(motd) - len, "<h2 style='color:orange;'>Online Karma Leaderboard</h2><hr>");

    new szRank[32];
    for (new i = 0; i < ArraySize(aOnline); i++)
    {
        ArrayGetArray(aOnline, i, eData);
        GetRank(eData[TD_PLAYERKARMA], szRank, charsmax(szRank)); // Fetch their rank
        
        len += formatex(motd[len], charsmax(motd) - len, "<p>#%d <b>%s</b> - %s (<span style='color:yellow;'>%d</span>)</p>", (i+1), eData[TD_PLAYERNAME], szRank, eData[TD_PLAYERKARMA]);
    }

    ArrayDestroy(aOnline);
    show_motd(id, motd, "Online Players");
    return PLUGIN_HANDLED;
}

// ========================================
// GLOBAL TOP (/karmatop)
// ========================================

public Cmd_GlobalTop(id)
{
    new iVaultUtil = nvault_util_open("medieval_karma");
    if (iVaultUtil == INVALID_HANDLE) return PLUGIN_HANDLED;

    new iCount = nvault_util_count(iVaultUtil);
    if (iCount <= 0) { nvault_util_close(iVaultUtil); return PLUGIN_HANDLED; }

    new Array:aGlobal = ArrayCreate(TopDataStruct);
    new eData[TopDataStruct], szKey[32], szValue[16], iTS, iPos;

    for (new i = 0; i < iCount; i++)
    {
        iPos = nvault_util_read(iVaultUtil, iPos, szKey, charsmax(szKey), szValue, charsmax(szValue), iTS);
        copy(eData[TD_PLAYERNAME], charsmax(eData[TD_PLAYERNAME]), szKey);
        eData[TD_PLAYERKARMA] = str_to_num(szValue);
        ArrayPushArray(aGlobal, eData);
    }
    nvault_util_close(iVaultUtil);
    ArraySort(aGlobal, "Sort_TopData");

    new motd[2048], len;
    len += formatex(motd[len], charsmax(motd) - len, "<body bgcolor=black style='color:white;font-family:Tahoma;'>");
    len += formatex(motd[len], charsmax(motd) - len, "<h2 style='color:red;'>Global Top 15</h2><hr>");

    new szRank[32];
    new iLimit = min(ArraySize(aGlobal), 15);
    for (new i = 0; i < iLimit; i++)
    {
        ArrayGetArray(aGlobal, i, eData);
        GetRank(eData[TD_PLAYERKARMA], szRank, charsmax(szRank)); // Fetch their rank
        
        len += formatex(motd[len], charsmax(motd) - len, "<p>#%d <b>%s</b> - %s (<span style='color:orange;'>%d</span>)</p>", (i+1), eData[TD_PLAYERNAME], szRank, eData[TD_PLAYERKARMA]);
    }

    ArrayDestroy(aGlobal);
    show_motd(id, motd, "Global Top");
    return PLUGIN_HANDLED;
}

// ========================================
// HELPERS
// ========================================

LoadKarma(id)
{
    new name[32], data[16];
    get_user_name(id, name, charsmax(name));
    if(nvault_get(gVault, name, data, charsmax(data))) g_iKarma[id] = str_to_num(data);
    else g_iKarma[id] = 0;
}

SaveKarma(id)
{
    new name[32], data[16];
    get_user_name(id, name, charsmax(name));
    num_to_str(g_iKarma[id], data, charsmax(data));
    nvault_set(gVault, name, data);
}

public Sort_TopData(Array:array, item1, item2)
{
    new d1[TopDataStruct], d2[TopDataStruct];
    ArrayGetArray(array, item1, d1);
    ArrayGetArray(array, item2, d2);
    if (d1[TD_PLAYERKARMA] > d2[TD_PLAYERKARMA]) return -1;
    if (d1[TD_PLAYERKARMA] < d2[TD_PLAYERKARMA]) return 1;
    return 0;
}

GetRank(karma, rank[], len)
{
    for(new i = 0; i < sizeof(g_Ranks); i++)
    {
        if(karma >= g_Ranks[i][RK_VALUE])
        {
            copy(rank, len, g_Ranks[i][RK_NAME]);
            return;
        }
    }
}
