/*
 * ============================================================================
 * Plugin: Admin Hierarchy (Advanced MOTD)
 * Autor: Gemini (AI)
 * ============================================================================
 * * --- LISTA DE CULORI SUPORTATE (Pentru who.ini) ---
 * Poti folosi orice nume de culoare HTML standard sau coduri HEX:
 * * Nume culori (Exemple):
 * - Red (Rosu)
 * - Blue (Albastru)
 * - Green (Verde)
 * - Yellow (Galben)
 * - Orange (Portocaliu)
 * - Purple (Mov)
 * - Cyan (Turcoaz)
 * - Magenta (Roz)
 * - White (Alb)
 * - Gray (Gri)
 * - Black (Negru)
 * - Pink (Roz deschis)
 * - Lime (Verde deschis)
 * - Gold (Auriu)
 * * Coduri HEX (Exemple):
 * - #FF0000 (Rosu pur)
 * - #00FF00 (Verde pur)
 * - #00BFFF (Albastru deschis / DeepSkyBlue)
 * - #FFD700 (Auriu)
 * ============================================================================
 */

#include <amxmodx>
#include <amxmisc>

#define PLUGIN "Admin Hierarchy MOTD"
#define VERSION "1.1"
#define AUTHOR "AI"

#define MAX_RANKS 32
#define MAX_MOTD_LEN 1535

new g_RankNames[MAX_RANKS][32];
new g_RankColors[MAX_RANKS][32];
new g_RankFlags[MAX_RANKS];
new g_RankCount = 0;

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("say /who", "cmd_who");
    register_clcmd("say who", "cmd_who");
    register_clcmd("say_team /who", "cmd_who");
    register_clcmd("say_team who", "cmd_who");
    register_clcmd("say /admins", "cmd_who");
    register_clcmd("say_team /admins", "cmd_who");
    register_clcmd("say /admin", "cmd_who");
    register_clcmd("say_team /admin", "cmd_who");
    register_clcmd("amx_who", "cmd_who");
    register_clcmd("amx_admins", "cmd_who");

    LoadRanks();
}

public LoadRanks() {
    new configdir[128], filepath[128];
    get_configsdir(configdir, charsmax(configdir));
    formatex(filepath, charsmax(filepath), "%s/who.ini", configdir);

    if(!file_exists(filepath)) {
        new f = fopen(filepath, "w");
        if(f) {
            fputs(f, "; Configurare Admin Hierarchy^n");
            fputs(f, "Red ^t^"Owner^" ^t^"abcdefghijklmnopqrstu^"^n");
            fputs(f, "Yellow ^t^"Co-Owner^" ^t^"abcdefijmnopqrstu^"^n");
            fputs(f, "#00FF00 ^t^"Moderator^" ^t^"abcdefijmnopqr^"^n");
            fputs(f, "Cyan ^t^"Admin^" ^t^"abcdefijmnop^"^n");
            fputs(f, "White ^t^"Slot^" ^t^"b^"^n");
            fclose(f);
        }
    }

    new f = fopen(filepath, "rt");
    if(!f) return;

    new line[128], color[32], name[32], flags[32];
    while(!feof(f) && g_RankCount < MAX_RANKS) {
        fgets(f, line, charsmax(line));
        trim(line);
        if(!line[0] || line[0] == ';' || line[0] == '/') continue;
        parse(line, color, charsmax(color), name, charsmax(name), flags, charsmax(flags));
        copy(g_RankColors[g_RankCount], 31, color);
        copy(g_RankNames[g_RankCount], 31, name);
        g_RankFlags[g_RankCount] = read_flags(flags);
        g_RankCount++;
    }
    fclose(f);
}

public cmd_who(id) {
    new motd[MAX_MOTD_LEN + 1], len = 0;
    len += formatex(motd[len], MAX_MOTD_LEN - len, "<style>body{background:#111827;color:#fff;font-family:Tahoma,sans-serif;margin:15px}h2{text-align:center;color:#F9FAFB;border-bottom:1px solid #374151;padding-bottom:10px;margin-top:0}.r{margin-top:15px;padding:8px 12px;background:#1F2937;border-radius:6px;font-weight:bold;font-size:16px;text-transform:uppercase;box-shadow:0 4px 6px rgba(0,0,0,0.3)}.p{margin:4px 0 0 15px;padding:6px 12px;background:#111827;border-left:2px solid #4B5563;font-size:14px;color:#D1D5DB}</style><h2>Admini Online</h2>");

    new bool:has_admins = false, players[32], pnum, player;
    get_players(players, pnum, "ch");

    for(new i = 0; i < g_RankCount; i++) {
        if(len >= MAX_MOTD_LEN - 150) break;
        new bool:rank_displayed = false;

        for(new j = 0; j < pnum; j++) {
            player = players[j];
            new pflags = get_user_flags(player);
            if (pflags != ADMIN_USER && (pflags & ADMIN_USER)) pflags &= ~ADMIN_USER;

            if(pflags == g_RankFlags[i]) {
                if(len >= MAX_MOTD_LEN - 100) break; 
                if(!rank_displayed) {
                    len += formatex(motd[len], MAX_MOTD_LEN - len, "<div class='r' style='color:%s;border-left:4px solid %s'>%s</div>", g_RankColors[i], g_RankColors[i], g_RankNames[i]);
                    rank_displayed = true;
                    has_admins = true;
                }
                new name[32];
                get_user_name(player, name, charsmax(name));
                replace_all(name, charsmax(name), "<", "&lt;");
                replace_all(name, charsmax(name), ">", "&gt;");
                len += formatex(motd[len], MAX_MOTD_LEN - len, "<div class='p'>&#8227; %s</div>", name);
            }
        }
    }

    if(!has_admins) len += formatex(motd[len], MAX_MOTD_LEN - len, "<div class='p' style='border-left-color:#EF4444'>Nu este niciun admin online.</div>");

    show_motd(id, motd, "Staff Online");
    return PLUGIN_HANDLED;
}
