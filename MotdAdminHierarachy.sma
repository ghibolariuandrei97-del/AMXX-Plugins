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
// Plugin-ul va genera un fisier who.ini in configs, acolo poti sa creezi ce Rang-uri de admin vrei cu culori.

#include <amxmodx>
#include <amxmisc>

#define PLUGIN "Admin Hierarchy MOTD"
#define VERSION "1.0"
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
    register_clcmd("say_team /who", "cmd_who");
    register_clcmd("say /admins", "cmd_who");
    register_clcmd("say_team /admins", "cmd_who");

    LoadRanks();
}

public LoadRanks() {
    new configdir[128], filepath[128];
    get_configsdir(configdir, charsmax(configdir));
    formatex(filepath, charsmax(filepath), "%s/who.ini", configdir);

    // Dacă fișierul nu există, îl creăm cu câteva exemple default
    if(!file_exists(filepath)) {
        new f = fopen(filepath, "w");
        if(f) {
            fputs(f, "; Configurare Admin Hierarchy^n");
            fputs(f, "; Format: Culoare  Nume_Grad  Flaguri^n");
            fputs(f, "; Poti folosi nume de culori (Red, Yellow) sau HEX (#FFD700)^n^n");
            fputs(f, "Red ^t^"Owner^" ^t^"abcdefghijklmnopqrstu^"^n");
            fputs(f, "Yellow ^t^"Co-Owner^" ^t^"abcdefijmnopqrstu^"^n");
            fputs(f, "#00FF00 ^t^"Moderator^" ^t^"abcdefijmnopqr^"^n");
            fputs(f, "Cyan ^t^"Admin^" ^t^"abcdefijmnop^"^n");
            fputs(f, "White ^t^"Slot^" ^t^"b^"^n");
            fclose(f);
        }
    }

    // Citim fișierul
    new f = fopen(filepath, "rt");
    if(!f) return;

    new line[128], color[32], name[32], flags[32];
    while(!feof(f) && g_RankCount < MAX_RANKS) {
        fgets(f, line, charsmax(line));
        trim(line);

        // Ignorăm comentariile și liniile goale
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
    new motd[MAX_MOTD_LEN + 1];
    new len = 0;

    // Design CSS Modern & Stilat
    len += formatex(motd[len], MAX_MOTD_LEN - len, "<style>");
    len += formatex(motd[len], MAX_MOTD_LEN - len, "body{background:#111827;color:#fff;font-family:Tahoma,sans-serif;margin:15px}");
    len += formatex(motd[len], MAX_MOTD_LEN - len, "h2{text-align:center;color:#F9FAFB;border-bottom:1px solid #374151;padding-bottom:10px;margin-top:0}");
    len += formatex(motd[len], MAX_MOTD_LEN - len, ".rank{margin-top:15px;padding:8px 12px;background:#1F2937;border-radius:6px;font-weight:bold;font-size:16px;text-transform:uppercase;box-shadow:0 4px 6px rgba(0,0,0,0.3)}");
    len += formatex(motd[len], MAX_MOTD_LEN - len, ".player{margin:4px 0 0 15px;padding:6px 12px;background:#111827;border-left:2px solid #4B5563;font-size:14px;color:#D1D5DB}");
    len += formatex(motd[len], MAX_MOTD_LEN - len, "</style><h2>Admini Online</h2>");

    new bool:has_admins = false;
    new players[32], pnum, player;
    
    // Luăm doar jucătorii reali (ignorăm boții)
    get_players(players, pnum, "ch");

    for(new i = 0; i < g_RankCount; i++) {
        new bool:rank_has_players = false;
        new rank_html[1024];
        new r_len = 0;

        for(new j = 0; j < pnum; j++) {
            player = players[j];
            new pflags = get_user_flags(player);

            // Ignorăm flag-ul 'z' (user normal) dacă jucătorul are și alte accese
            if (pflags != ADMIN_USER && (pflags & ADMIN_USER)) {
                pflags &= ~ADMIN_USER;
            }

            // Verificăm dacă accesul jucătorului se potrivește exact cu gradul
            if(pflags == g_RankFlags[i]) {
                new name[32];
                get_user_name(player, name, charsmax(name));

                // Evităm stricarea codului HTML dacă numele conține < sau >
                replace_all(name, charsmax(name), "<", "&lt;");
                replace_all(name, charsmax(name), ">", "&gt;");

                r_len += formatex(rank_html[r_len], sizeof(rank_html) - 1 - r_len, "<div class='player'>&#8227; %s</div>", name);
                rank_has_players = true;
                has_admins = true;
            }
        }

        // Dacă avem admini online la acest grad, îl adăugăm în MOTD
        if(rank_has_players) {
            if (MAX_MOTD_LEN - len > 0) {
                len += formatex(motd[len], MAX_MOTD_LEN - len, "<div class='rank' style='color:%s; border-left: 4px solid %s;'>%s</div>", g_RankColors[i], g_RankColors[i], g_RankNames[i]);
                len += formatex(motd[len], MAX_MOTD_LEN - len, "%s", rank_html);
            }
        }
    }

    if(!has_admins) {
        len += formatex(motd[len], MAX_MOTD_LEN - len, "<div class='player' style='border-left-color: #EF4444;'>Nu este niciun admin online in acest moment.</div>");
    }

    // Afișăm MOTD-ul
    show_motd(id, motd, "Admini Online");
    return PLUGIN_HANDLED;
}
