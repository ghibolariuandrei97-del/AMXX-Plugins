#include <amxmodx>
#include <amxmisc>
#include <easy_http>

#define PLUGIN "GameTracker Stats"
#define VERSION "1.0"
#define AUTHOR "AI"

new g_pCvarIp;
static g_szPageData[35000];

new g_szUserRank[33][64];
new g_szUserMinutes[33][16];

enum _:StatData {
    ST_FirstSeen[32],
    ST_LastSeen[32],
    ST_Score[16],
    ST_Minutes[16],
    ST_SPM[16],
    ST_Rank[64]
}

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("say /gt", "cmd_show_motd");
    register_clcmd("say /gtstats", "cmd_fetch_stats");
    register_clcmd("say /ore", "cmd_show_hours");
    register_clcmd("say /gtrank", "cmd_show_rank");
    register_clcmd("say /gttop", "cmd_fetch_top");

    g_pCvarIp = register_cvar("gt_ip", "81.181.244.37:27015");
}

// --- TOP 10 INTERACTIVE MENU ---
public cmd_fetch_top(id) {
    new szIp[64], szUrl[256];
    get_pcvar_string(g_pCvarIp, szIp, charsmax(szIp));
    formatex(szUrl, charsmax(szUrl), "https://www.gametracker.com/server_info/%s/top_players/", szIp);
    
    client_print_color(id, print_team_default, "^4[GT]^1 Se incarca Top 10 Jucatori...");

    new EzHttpOptions:opt = ezhttp_create_options();
    ezhttp_option_set_user_agent(opt, "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/119.0.0.0 Safari/537.36");
    
    new userData[1]; userData[0] = id;
    ezhttp_option_set_user_data(opt, userData, 1);
    ezhttp_get(szUrl, "OnTopDownloaded", opt);
    return PLUGIN_HANDLED;
}

public OnTopDownloaded(EzHttpRequest:request_id) {
    new userData[1], id;
    ezhttp_get_user_data(request_id, userData);
    id = userData[0];

    if (ezhttp_get_error_code(request_id) != EZH_OK || !is_user_connected(id)) return;
    ezhttp_get_data(request_id, g_szPageData, charsmax(g_szPageData));

    new menu = menu_create("\yGT Top 10 \rPlayers \d(Click for Banner)", "menu_top_handler");
    new szLine[128], szName[32], szScore[16], iCurrentPos = 0;

    new iHeader = containi(g_szPageData, "item_list");
    if (iHeader != -1) iCurrentPos = iHeader;

    for(new i = 1; i <= 10; i++) {
        new iFound = containi(g_szPageData[iCurrentPos], "/player/");
        if (iFound == -1) break;
        
        iCurrentPos += iFound + 8;

        new n = 0;
        while(g_szPageData[iCurrentPos] != '/' && g_szPageData[iCurrentPos] != '^"' && n < charsmax(szName) - 1) {
            szName[n++] = g_szPageData[iCurrentPos++];
        }
        szName[n] = 0;
        
        // Find Score
        new iScoreTag = containi(g_szPageData[iCurrentPos], "<td>");
        if (iScoreTag != -1) {
            iCurrentPos += iScoreTag + 4;
            if (!isdigit(g_szPageData[iCurrentPos+1])) {
                 new iNextTd = containi(g_szPageData[iCurrentPos], "<td>");
                 if (iNextTd != -1) iCurrentPos += iNextTd + 4;
            }
            new k = 0;
            while(g_szPageData[iCurrentPos] != '<' && k < charsmax(szScore) - 1) {
                if(isdigit(g_szPageData[iCurrentPos]) || g_szPageData[iCurrentPos] == ',') szScore[k++] = g_szPageData[iCurrentPos];
                iCurrentPos++;
            }
            szScore[k] = 0;
        } else { copy(szScore, charsmax(szScore), "0"); }

        // We pass the Name as the info string so the handler knows which banner to show
        formatex(szLine, charsmax(szLine), "\w%s \d- \yScore: %s", szName, szScore);
        menu_additem(menu, szLine, szName);
        
        new iEndRow = containi(g_szPageData[iCurrentPos], "</tr>");
        if (iEndRow != -1) iCurrentPos += iEndRow;
    }

    if (menu_items(menu) == 0) menu_additem(menu, "\dNu s-au gasit date.");
    menu_display(id, menu, 0);
}

// --- HANDLER: OPENS MOTD FOR THE SELECTED PLAYER ---
public menu_top_handler(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szName[64], _unused;
    menu_item_getinfo(menu, item, _unused, szName, charsmax(szName), _, _, _unused);
    
    // Open banner for the selected name
    show_player_banner(id, szName);
    
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// --- SHARED MOTD FUNCTION ---
stock show_player_banner(id, const name[]) {
    new szIp[64], szUrl[256], szEncName[64];
    get_pcvar_string(g_pCvarIp, szIp, charsmax(szIp));
    
    copy(szEncName, charsmax(szEncName), name);
    replace_all(szEncName, charsmax(szEncName), " ", "%%20");
    
    formatex(szUrl, charsmax(szUrl), "https://cache.gametracker.com/player/%s/%s/b_560x95.png", szEncName, szIp);
    
    new szMotd[512];
    formatex(szMotd, charsmax(szMotd), "<html><body style=^"background:#000;margin:0;display:flex;align-items:center;justify-content:center;height:100vh;^"><img src=^"%s^"></body></html>", szUrl);
    
    new szTitle[64];
    formatex(szTitle, charsmax(szTitle), "GT: %s", name);
    show_motd(id, szMotd, szTitle);
}

// --- OTHER COMMANDS ---
public cmd_show_motd(id) {
    new szName[32]; get_user_name(id, szName, charsmax(szName));
    show_player_banner(id, szName);
    return PLUGIN_HANDLED;
}

public cmd_show_hours(id) {
    if (g_szUserMinutes[id][0] == 0) { client_print_color(id, print_team_default, "^4[GT]^1 Foloseste intai ^3/gtstats^1!"); return PLUGIN_HANDLED; }
    new iMinutes = str_to_num(g_szUserMinutes[id]);
    client_print_color(id, print_team_default, "^4[GT]^1 Timp total: ^3%d^1 minute (aprox. ^4%.2f^1 ore).", iMinutes, float(iMinutes) / 60.0);
    return PLUGIN_HANDLED;
}

public cmd_show_rank(id) {
    if (g_szUserRank[id][0] == 0) { client_print_color(id, print_team_default, "^4[GT]^1 Foloseste intai ^3/gtstats^1!"); return PLUGIN_HANDLED; }
    client_print_color(id, print_team_default, "^4[GT]^1 Pozitia ta: ^3%s", g_szUserRank[id]);
    return PLUGIN_HANDLED;
}

public cmd_fetch_stats(id) {
    new szName[32], szIp[64], szUrl[256];
    get_user_name(id, szName, charsmax(szName));
    get_pcvar_string(g_pCvarIp, szIp, charsmax(szIp));
    new szEncName[64]; copy(szEncName, charsmax(szEncName), szName);
    replace_all(szEncName, charsmax(szEncName), " ", "%%20");
    formatex(szUrl, charsmax(szUrl), "https://www.gametracker.com/player/%s/%s/", szEncName, szIp);
    new EzHttpOptions:opt = ezhttp_create_options();
    ezhttp_option_set_user_agent(opt, "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/119.0.0.0 Safari/537.36");
    new userData[1]; userData[0] = id;
    ezhttp_option_set_user_data(opt, userData, 1);
    ezhttp_get(szUrl, "OnStatsDownloaded", opt);
    return PLUGIN_HANDLED;
}

public OnStatsDownloaded(EzHttpRequest:request_id) {
    new userData[1], id;
    ezhttp_get_user_data(request_id, userData);
    id = userData[0];
    if (ezhttp_get_error_code(request_id) != EZH_OK || !is_user_connected(id)) return;
    ezhttp_get_data(request_id, g_szPageData, charsmax(g_szPageData));
    new stats[StatData];
    parse_gt_value(g_szPageData, "First Seen:", stats[ST_FirstSeen], charsmax(stats[ST_FirstSeen]));
    parse_gt_value(g_szPageData, "Last Seen:", stats[ST_LastSeen], charsmax(stats[ST_LastSeen]));
    parse_gt_value(g_szPageData, "Score:", stats[ST_Score], charsmax(stats[ST_Score]));
    parse_gt_value(g_szPageData, "Minutes Played:", stats[ST_Minutes], charsmax(stats[ST_Minutes]));
    parse_gt_value(g_szPageData, "Score per Minute:", stats[ST_SPM], charsmax(stats[ST_SPM]));
    parse_gt_rank(g_szPageData, "Rank on Server:", stats[ST_Rank], charsmax(stats[ST_Rank]));
    if (stats[ST_Score][0] != 0) {
        copy(g_szUserRank[id], charsmax(g_szUserRank[]), stats[ST_Rank]);
        copy(g_szUserMinutes[id], charsmax(g_szUserMinutes[]), stats[ST_Minutes]);
        show_stats_menu(id, stats);
    }
}

public show_stats_menu(id, stats[StatData]) {
    new szTitle[128], szName[32]; 
    get_user_name(id, szName, charsmax(szName));
    formatex(szTitle, charsmax(szTitle), "\yGT Stats: \w%s^n\dDate in timp real", szName);
    new menu = menu_create(szTitle, "menu_ignore");
    new szItem[128];
    formatex(szItem, charsmax(szItem), "First Seen: \y%s", stats[ST_FirstSeen]); menu_additem(menu, szItem);
    formatex(szItem, charsmax(szItem), "Last Seen: \y%s", stats[ST_LastSeen]); menu_additem(menu, szItem);
    formatex(szItem, charsmax(szItem), "Score: \y%s", stats[ST_Score]); menu_additem(menu, szItem);
    formatex(szItem, charsmax(szItem), "Minutes Played: \y%s", stats[ST_Minutes]); menu_additem(menu, szItem);
    formatex(szItem, charsmax(szItem), "Score per Minute: \y%s", stats[ST_SPM]); menu_additem(menu, szItem);
    formatex(szItem, charsmax(szItem), "Rank on Server: \r%s", stats[ST_Rank]); menu_additem(menu, szItem);
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

stock parse_gt_rank(const buffer[], const label[], output[], len) {
    new iPos = containi(buffer, label);
    if (iPos == -1) return;
    iPos += strlen(label);
    new iEndLabel = containi(buffer[iPos], "</span>") + iPos;
    new bool:inTag = false, j = 0;
    for (new i = iPos; i < iEndLabel + 200 && buffer[i] != 0 && j < len - 1; i++) {
        if (buffer[i] == '<') { inTag = true; continue; }
        if (buffer[i] == '>') { inTag = false; continue; }
        if (!inTag) {
            if (buffer[i] > 32) output[j++] = buffer[i];
            else if (j > 0 && output[j-1] != ' ') output[j++] = ' ';
        }
    }
    output[j] = 0; trim(output);
}

stock parse_gt_value(const buffer[], const label[], output[], len) {
    new iPos = containi(buffer, label);
    if (iPos == -1) return;
    iPos += strlen(label);
    new iLimit = 0;
    while (buffer[iPos] != 0 && iLimit < 200) {
        if (buffer[iPos] == '>') { if (buffer[iPos+1] != '<') { iPos++; break; } }
        iPos++; iLimit++;
    }
    while (buffer[iPos] != 0 && buffer[iPos] <= 32) iPos++;
    new j = 0;
    while (buffer[iPos] != '<' && buffer[iPos] != 0 && j < len - 1) { output[j++] = buffer[iPos++]; }
    output[j] = 0; replace_all(output, len, "&nbsp;", ""); trim(output);
}

public menu_ignore(id, menu, item) { menu_destroy(menu); return PLUGIN_HANDLED; }
