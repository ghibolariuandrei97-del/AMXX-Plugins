#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <nvault>

new const PLUGIN_NAME[]    = "Tournament";
new const PLUGIN_VERSION[] = "1.0";
new const PLUGIN_AUTHOR[]  = "Ai";

#define TOP_LIMIT 10
#define VAULT_NAME "tournament_stats"
#define INI_FILE "tournament_info.ini"

enum _:TopStruct { TOP_NAME[32], TOP_FRAGS };

new g_Vault, g_iTournamentStart;
new g_iPlayerFrags[MAX_PLAYERS + 1];
new g_szTopCache[TOP_LIMIT][TopStruct];
new g_pCvarActive, g_pCvarDuration, g_pCvarAdInterval, g_pCvarAllowBots;

public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    register_clcmd("say /tournament", "cmd_show_top");
    register_clcmd("say /t", "cmd_show_top");
    register_clcmd("say /tinfo", "cmd_show_info");
    register_clcmd("say /place", "cmd_show_place");
    register_concmd("amx_tournament_reset", "cmd_reset_tournament", ADMIN_RCON);

    g_pCvarActive = create_cvar("tournament_enabled", "1", FCVAR_SERVER);
    g_pCvarDuration = create_cvar("tournament_duration_days", "30", FCVAR_SERVER);
    g_pCvarAdInterval = create_cvar("tournament_ad_interval", "240.0", FCVAR_SERVER);
    g_pCvarAllowBots = create_cvar("tournament_allow_bots", "1", FCVAR_SERVER);

    RegisterHookChain(RG_CBasePlayer_Killed, "OnPlayerKilled", 1);
    RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawn", 1);

    g_Vault = nvault_open(VAULT_NAME);
    load_tournament_data();
    check_ini_file();
}

public plugin_cfg() {
    set_task(get_pcvar_float(g_pCvarAdInterval), "task_advertisement", 666, _, _, "b");
}

public plugin_end() {
    save_top_to_vault();
    nvault_close(g_Vault);
}

public OnPlayerKilled(victim, killer) {
    if (!get_pcvar_num(g_pCvarActive) || !is_user_connected(killer) || victim == killer) return;
    if (is_user_bot(killer) && !get_pcvar_num(g_pCvarAllowBots)) return;

    g_iPlayerFrags[killer]++;
    save_player_data(killer);
    update_top_cache(killer);
}

public OnPlayerSpawn(id) {
    if (!get_pcvar_num(g_pCvarActive) || !is_user_alive(id)) return;
    if (is_user_bot(id) && !get_pcvar_num(g_pCvarAllowBots)) return;

    static szName[32]; get_user_name(id, szName, charsmax(szName));
    for (new i = 0; i < TOP_LIMIT; i++) {
        if (g_szTopCache[i][TOP_FRAGS] > 0 && equal(g_szTopCache[i][TOP_NAME], szName)) {
            rg_add_account(id, (TOP_LIMIT - i) * 500, AS_ADD);
            break;
        }
    }
}

public cmd_show_top(id) {
    static szHtml[1536];
    new iLen = 0, iDuration = get_pcvar_num(g_pCvarDuration) * 86400;
    static szEndDate[24]; format_time(szEndDate, charsmax(szEndDate), "%d/%m/%Y", g_iTournamentStart + iDuration);

    // Ultra-compresie HTML/CSS pentru a evita limitarea de 1536 caractere din CS 1.6
    iLen = formatex(szHtml, charsmax(szHtml), "<style>body{background:#111;color:#ccc;font-family:Arial}th{color:#F00;text-align:left}.r{text-align:right;color:#0F0}.a{color:#FD0}.b{color:#CCC}.c{color:#C83}</style>");
    iLen += format(szHtml[iLen], charsmax(szHtml)-iLen, "<div style='background:#D11;color:#FFF;text-align:center;padding:2px'><b>TOP 10 TOURNAMENT</b><br><font size=1>Ends: %s</font></div>", szEndDate);
    iLen += format(szHtml[iLen], charsmax(szHtml)-iLen, "<table width=100%%><tr><th>#<th>PLAYER<th class=r>FRAGS");

    for (new i = 0; i < TOP_LIMIT; i++) {
        if (g_szTopCache[i][TOP_FRAGS] <= 0) continue;

        static szClass[2];
        if (i == 0) szClass = "a";
        else if (i == 1) szClass = "b";
        else if (i == 2) szClass = "c";
        else szClass = "";

        // Format minimalist extrem: fara </tr> inchis (motorul HTML CS il inchide automat)
        iLen += format(szHtml[iLen], charsmax(szHtml)-iLen, "<tr><td>%d<td class=%s>%s<td class=r>%d", i + 1, szClass, g_szTopCache[i][TOP_NAME], g_szTopCache[i][TOP_FRAGS]);
    }
    
    iLen += format(szHtml[iLen], charsmax(szHtml)-iLen, "</table>");
    show_motd(id, szHtml, "Tournament");
    return PLUGIN_HANDLED;
}

public cmd_show_info(id) {
    static szPath[128]; get_configsdir(szPath, charsmax(szPath));
    format(szPath, charsmax(szPath), "%s/%s", szPath, INI_FILE);
    new f = fopen(szPath, "rt");
    if (!f) return PLUGIN_HANDLED;

    static szHtml[1536], szLine[128], iLen;
    iLen = formatex(szHtml, charsmax(szHtml), "<style>body{background:#111;color:#FFF;font-family:Arial}h3{color:#F00}</style><div style='border:1px solid #F00;padding:10px;background:#181818'><h3>INFO</h3><hr>");

    while (!feof(f)) {
        fgets(f, szLine, charsmax(szLine)); trim(szLine);
        if (!szLine[0] || szLine[0] == ';' || szLine[0] == '[') continue;
        iLen += format(szHtml[iLen], charsmax(szHtml)-iLen, "<p>- %s</p>", szLine);
        if (iLen > 1400) break; // prevent crash
    }
    fclose(f);
    iLen += format(szHtml[iLen], charsmax(szHtml)-iLen, "</div>");
    show_motd(id, szHtml, "Info");
    return PLUGIN_HANDLED;
}

public cmd_show_place(id) {
    static szName[32]; get_user_name(id, szName, charsmax(szName));
    new iPos = 0;
    for(new i = 0; i < TOP_LIMIT; i++) {
        if(equal(g_szTopCache[i][TOP_NAME], szName)) { iPos = i + 1; break; }
    }
    if (iPos > 0) client_print_color(id, print_team_default, "^4[Turneu]^1 Esti pe locul ^3%d^1 in Top 10!", iPos);
    else client_print_color(id, print_team_default, "^4[Turneu]^1 Ai ^3%d^1 fraguri. Lupta pentru Top 10!", g_iPlayerFrags[id]);
    return PLUGIN_HANDLED;
}

update_top_cache(id) {
    static szName[32]; get_user_name(id, szName, charsmax(szName));
    new iFrags = g_iPlayerFrags[id], iExistingPos = -1;
    for (new i = 0; i < TOP_LIMIT; i++) {
        if (equal(g_szTopCache[i][TOP_NAME], szName)) { iExistingPos = i; break; }
    }
    if (iExistingPos != -1) g_szTopCache[iExistingPos][TOP_FRAGS] = iFrags;
    else if (iFrags > g_szTopCache[TOP_LIMIT - 1][TOP_FRAGS]) {
        copy(g_szTopCache[TOP_LIMIT - 1][TOP_NAME], 31, szName);
        g_szTopCache[TOP_LIMIT - 1][TOP_FRAGS] = iFrags;
    }
    static tempName[32], tempFrags;
    for (new i = 0; i < TOP_LIMIT - 1; i++) {
        for (new j = i + 1; j < TOP_LIMIT; j++) {
            if (g_szTopCache[i][TOP_FRAGS] < g_szTopCache[j][TOP_FRAGS]) {
                tempFrags = g_szTopCache[i][TOP_FRAGS]; g_szTopCache[i][TOP_FRAGS] = g_szTopCache[j][TOP_FRAGS]; g_szTopCache[j][TOP_FRAGS] = tempFrags;
                copy(tempName, 31, g_szTopCache[i][TOP_NAME]); copy(g_szTopCache[i][TOP_NAME], 31, g_szTopCache[j][TOP_NAME]); copy(g_szTopCache[j][TOP_NAME], 31, tempName);
            }
        }
    }
}

save_top_to_vault() {
    static szData[1024], iLen; iLen = 0;
    for (new i = 0; i < TOP_LIMIT; i++) iLen += formatex(szData[iLen], charsmax(szData)-iLen, "^"%s^":%d|", g_szTopCache[i][TOP_NAME], g_szTopCache[i][TOP_FRAGS]);
    nvault_set(g_Vault, "__TOP10_CACHE__", szData);
}

load_tournament_data() {
    g_iTournamentStart = nvault_get(g_Vault, "Tournament_StartTimestamp");
    if (g_iTournamentStart == 0) {
        g_iTournamentStart = get_systime();
        static szTime[16]; num_to_str(g_iTournamentStart, szTime, charsmax(szTime));
        nvault_set(g_Vault, "Tournament_StartTimestamp", szTime);
    }
    static szData[1024], szEntry[64], szName[32], szFrags[16];
    nvault_get(g_Vault, "__TOP10_CACHE__", szData, charsmax(szData));
    if (szData[0]) {
        new i = 0;
        while (szData[0] && i < TOP_LIMIT) {
            strtok(szData, szEntry, charsmax(szEntry), szData, charsmax(szData), '|');
            if (szEntry[0]) {
                strtok(szEntry, szName, charsmax(szName), szFrags, charsmax(szFrags), ':');
                remove_quotes(szName); copy(g_szTopCache[i][TOP_NAME], 31, szName);
                g_szTopCache[i][TOP_FRAGS] = str_to_num(szFrags); i++;
            }
        }
    }
}

check_ini_file() {
    static szPath[128]; get_configsdir(szPath, charsmax(szPath));
    format(szPath, charsmax(szPath), "%s/%s", szPath, INI_FILE);
    if (!file_exists(szPath)) {
        new f = fopen(szPath, "wt");
        if (f) {
            fputs(f, "Locul 1: 50 Euro PayPal^nLocul 2: Admin + VIP^nLocul 3: VIP Gold^n");
            fclose(f);
        }
    }
}

public client_putinserver(id) {
    g_iPlayerFrags[id] = 0;
    static szName[32]; get_user_name(id, szName, charsmax(szName));
    g_iPlayerFrags[id] = nvault_get(g_Vault, szName);
}

save_player_data(id) {
    static szName[32], szFrags[10]; get_user_name(id, szName, charsmax(szName));
    num_to_str(g_iPlayerFrags[id], szFrags, charsmax(szFrags));
    nvault_set(g_Vault, szName, szFrags);
}

public task_advertisement() {
    if (get_pcvar_num(g_pCvarActive))
        client_print_color(0, print_team_default, "^4[Turneu]^1 Scrie ^3/t^1 sa vezi clasamentul turneului!");
}

public cmd_reset_tournament(id, level, cid) {
    if (!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    
    // Golește complet nVault
    nvault_prune(g_Vault, 0, get_systime() + 864000);
    
    // Resetare Jucători Online
    static szName[32];
    for (new i = 1; i <= MaxClients; i++) {
        if (is_user_connected(i)) {
            g_iPlayerFrags[i] = 0;
            get_user_name(i, szName, charsmax(szName));
            nvault_remove(g_Vault, szName); // Șterge fizic jucătorii conectați
        }
    }
    
    // Resetare Timp
    g_iTournamentStart = get_systime();
    static szTime[16]; num_to_str(g_iTournamentStart, szTime, charsmax(szTime));
    nvault_set(g_Vault, "Tournament_StartTimestamp", szTime);
    
    // Resetare Cache Top 10
    for (new i = 0; i < TOP_LIMIT; i++) { 
        g_szTopCache[i][TOP_NAME][0] = 0; 
        g_szTopCache[i][TOP_FRAGS] = 0; 
    }
    save_top_to_vault();
    
    client_print_color(0, print_team_default, "^4[Turneu]^1 Adminul a resetat turneul! Toate fragurile au fost sterse.");
    return PLUGIN_HANDLED;
}
