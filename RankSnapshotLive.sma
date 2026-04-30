#include <amxmodx>
#include <amxmisc>
#include <nvault>
#include <nvault_util>

new g_Kills[33], g_Deaths[33], g_HS[33], g_Planted[33], g_Defused[33], g_LastRank[33]
new g_Vault, g_pBots

public plugin_init() {
    register_plugin("Rank Snapshot Live", "1.0", "AI")
    register_clcmd("say /rank", "cmd_rank")
    register_clcmd("say /top", "cmd_top")
    register_concmd("amx_xrank_reset", "cmd_reset_rank", ADMIN_RCON)
    register_event("DeathMsg", "event_death", "a")
    register_logevent("log_b_p", 3, "2=Planted_The_Bomb")
    register_logevent("log_b_d", 3, "2=Defused_The_Bomb")
    
    g_pBots = register_cvar("xrank_bots", "1")
    g_Vault = nvault_open("rank_snapshot_pro")
}

public plugin_end() {
    if (g_Vault != INVALID_HANDLE) nvault_close(g_Vault)
}

public client_putinserver(id) {
    g_Kills[id] = 0; g_Deaths[id] = 0; g_HS[id] = 0; g_Planted[id] = 0; g_Defused[id] = 0;
    if (should_h(id)) load_p(id);
    g_LastRank[id] = get_pos(id);
}

public client_disconnected(id) if (should_h(id)) save_p(id);

bool:should_h(id) {
    // Daca e bot si cvar-ul e 0, il ignoram. Altfel (daca e player sau bot cu cvar 1), il procesam[cite: 1, 3].
    if (is_user_bot(id) && get_pcvar_num(g_pBots) == 0) return false;
    return true;
}

public event_death() {
    new k = read_data(1), v = read_data(2), hs = read_data(3)
    if (k && k != v && k <= 32) { g_Kills[k]++; if (hs) g_HS[k]++; check_r(k); }
    if (v && v <= 32) { g_Deaths[v]++; check_r(v); }
}

check_r(id) {
    if (!should_h(id)) return;
    
    save_p(id); // Salveaza datele (si pentru boti daca cvar e 1)[cite: 3].
    
    if (is_user_bot(id)) return; // Oprim aici pentru boti (nu le trimitem mesaje in chat)[cite: 1].
    
    new cur = get_pos(id);
    if (cur < g_LastRank[id]) client_print_color(id, print_team_default, "^4[Rank]^1 Ai ^3URCAT ^1pe locul ^4#%d^1!", cur);
    else if (cur > g_LastRank[id]) client_print_color(id, print_team_default, "^4[Rank]^1 Ai ^2COBORAT ^1pe locul ^4#%d^1.", cur);
    g_LastRank[id] = cur;
}

get_pos(id) {
    new sc = (g_Kills[id] * 2) + g_HS[id] - g_Deaths[id], r = 1;
    
    // Fortam scrierea pe disc (Live Update)[cite: 3].
    nvault_close(g_Vault); 
    g_Vault = nvault_open("rank_snapshot_pro");
    
    new vU = nvault_util_open("rank_snapshot_pro");
    if (vU != INVALID_HANDLE) {
        new count = nvault_util_count(vU), pos = 0, k[35], v[128], ts, pk[16], pd[16], phs[16];
        for (new i = 1; i <= count; i++) {
            pos = nvault_util_read(vU, pos, k, 34, v, 127, ts);
            parse(v, pk, 15, pd, 15, phs, 15);
            if (((str_to_num(pk) * 2) + str_to_num(phs) - str_to_num(pd)) > sc) r++;
        }
        nvault_util_close(vU);
    }
    return r;
}

get_s(k, d) {
    if (d == 0) return (k > 0) ? 7 : 1;
    new Float:kd = float(k) / floatmax(1.0, float(d));
    if (kd >= 2.5) return 7; if (kd >= 2.0) return 6; if (kd >= 1.5) return 5;
    if (kd >= 1.0) return 3; return (kd >= 0.7) ? 2 : 1;
}

public cmd_rank(id) {
    save_p(id);
    new name[32], sStr[16] = ""; get_user_name(id, name, 31);
    new p = get_pos(id), st = get_s(g_Kills[id], g_Deaths[id]);
    for(new i=0; i<st; i++) add(sStr, 15, "*");
    new motd[1024], len = 0;
    len += formatex(motd[len], 1023-len, "<style>body{background:#0d1117;color:#ccc;font:12px sans-serif}table{width:100%%;border-collapse:collapse}th{background:#161b22;color:#58a6ff}td{text-align:center;border:1px solid #222}.t3{color:#fd0}.st{color:#fe0}</style>");
    len += formatex(motd[len], 1023-len, "<table><tr><th>Rank<th>Nume<th>K<th>D<th>HS<th>P<th>Df<th>Stars");
    len += formatex(motd[len], 1023-len, "<tr><td class=t3>#%d<td>%s<td>%d<td>%d<td>%d<td>%d<td>%d<td class=st>%s", p, name, g_Kills[id], g_Deaths[id], g_HS[id], g_Planted[id], g_Defused[id], sStr);
    show_motd(id, motd, "Rank");
    return PLUGIN_HANDLED;
}

public cmd_top(id) {
    nvault_close(g_Vault); 
    g_Vault = nvault_open("rank_snapshot_pro");
    
    new vU = nvault_util_open("rank_snapshot_pro");
    if (vU == INVALID_HANDLE) return PLUGIN_HANDLED;
    new count = nvault_util_count(vU), tN[10][32], tK[10], tD[10], tH[10], tP[10], tDf[10], tS[10];
    for (new i = 0; i < 10; i++) tS[i] = -999999;
    new v_p = 0, v_k[35], v_v[128], v_t, pk[16], pd[16], phs[16], pp[16], pdf[16];
    for (new i = 1; i <= count; i++) {
        v_p = nvault_util_read(vU, v_p, v_k, 34, v_v, 127, v_t);
        parse(v_v, pk, 15, pd, 15, phs, 15, pp, 15, pdf, 15);
        new sc = (str_to_num(pk) * 2) + str_to_num(phs) - str_to_num(pd);
        if (sc > tS[9]) {
            new ins = 9; while (ins > 0 && sc > tS[ins-1]) ins--;
            for (new j = 9; j > ins; j--) { copy(tN[j], 31, tN[j-1]); tK[j]=tK[j-1]; tD[j]=tD[j-1]; tH[j]=tH[j-1]; tP[j]=tP[j-1]; tDf[j]=tDf[j-1]; tS[j]=tS[j-1]; }
            copy(tN[ins], 31, v_k); tK[ins]=str_to_num(pk); tD[ins]=str_to_num(pd); tH[ins]=str_to_num(phs); tP[ins]=str_to_num(pp); tDf[ins]=str_to_num(pdf); tS[ins]=sc;
        }
    }
    nvault_util_close(vU);
    
    new motd[1536], len = 0;
    len += formatex(motd[len], 1535-len, "<style>body{background:#0d1117;color:#ccc;font:11px Tahoma}table{width:100%%;border-collapse:collapse}th{background:#161b22;color:#58a6ff}td{text-align:center;border:1px solid #222}.c1{color:#f6b}.c2{color:red}.c3{color:#fd0}.st{color:#fe0}</style>");
    len += formatex(motd[len], 1535-len, "<table><tr><th>#<th>Nume<th>K<th>D<th>HS<th>P<th>Df<th>Stars");
    for (new i = 0; i < 10; i++) {
        if (tS[i] == -999999) break;
        new st = get_s(tK[i], tD[i]), sStr[10] = ""; for(new s=0; s<st; s++) sStr[s] = '*';
        new cl[4] = ""; if(i==0) cl="c1"; else if(i==1) cl="c2"; else if(i==2) cl="c3";
        len += formatex(motd[len], 1535-len, "<tr><td class=%s>%d<td class=%s>%s<td>%d<td>%d<td>%d<td>%d<td>%d<td class=st>%s", cl, i+1, cl, tN[i], tK[i], tD[i], tH[i], tP[i], tDf[i], sStr);
    }
    len += formatex(motd[len], 1535-len, "</table>"); show_motd(id, motd, "Top 10");
    return PLUGIN_HANDLED;
}

public log_b_p() { new id = get_l_i(); if (id) g_Planted[id]++; }
public log_b_d() { new id = get_l_i(); if (id) g_Defused[id]++; }
get_l_i() { new log[80], name[32]; read_logargv(0, log, 79); parse_loguser(log, name, 31); return get_user_index(name); }

public cmd_reset_rank(id, level, cid) {
    if (!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;

    // 1. Închidem mânerul bazei de date pentru a permite ștergerea fișierului[cite: 3]
    if (g_Vault != INVALID_HANDLE) {
        nvault_close(g_Vault);
    }

    // 2. Construim calea către fișierul vault
    new vault_path[128];
    get_datadir(vault_path, charsmax(vault_path));
    format(vault_path, charsmax(vault_path), "%s/vault/rank_snapshot_pro.vault", vault_path);

    // 3. Ștergem fișierul de pe disc
    if (file_exists(vault_path)) {
        delete_file(vault_path);
        
        // Ștergem și fișierul .idx dacă există (indexul nvault)
        new idx_path[128];
        format(idx_path, charsmax(idx_path), "%s.idx", vault_path);
        if (file_exists(idx_path)) delete_file(idx_path);
    }

    // 4. Redeschidem baza de date (va fi creată una nouă, goală)[cite: 3]
    g_Vault = nvault_open("rank_snapshot_pro");

    // 5. Resetăm statisticile jucătorilor aflați în acest moment pe server
    new players[32], num, player;
    get_players(players, num);
    for (new i = 0; i < num; i++) {
        player = players[i];
        g_Kills[player] = 0;
        g_Deaths[player] = 0;
        g_HS[player] = 0;
        g_Planted[player] = 0;
        g_Defused[player] = 0;
        g_LastRank[player] = 1;
    }

    client_print_color(0, print_team_default, "^4[Rank]^1 Toate statisticile au fost resetate de către administrator!");
    return PLUGIN_HANDLED;
}

save_p(id) {
    new n[35], d[128]; get_user_name(id, n, 34);
    formatex(d, 127, "%d %d %d %d %d 0", g_Kills[id], g_Deaths[id], g_HS[id], g_Planted[id], g_Defused[id]);
    nvault_set(g_Vault, n, d);
}

load_p(id) {
    new n[35], d[128]; get_user_name(id, n, 34);
    if (nvault_get(g_Vault, n, d, 127)) {
        new k[16], de[16], h[16], p[16], df[16];
        parse(d, k, 15, de, 15, h, 15, p, 15, df, 15);
        g_Kills[id]=str_to_num(k); g_Deaths[id]=str_to_num(de); g_HS[id]=str_to_num(h);
        g_Planted[id]=str_to_num(p); g_Defused[id]=str_to_num(df);
    }
}

public client_infochanged(id) {
    if (!is_user_connected(id)) return;

    static new_name[32], old_name[32];
    get_user_info(id, "name", new_name, charsmax(new_name));
    get_user_name(id, old_name, charsmax(old_name));

    // Verificăm dacă jucătorul chiar își schimbă numele
    if (!equal(new_name, old_name)) {
        
        // 1. Salvăm progresul pe numele vechi înainte de schimbare
        save_p(id); 

        // 2. Resetăm datele locale pentru a începe "curat" pe noul nume
        g_Kills[id] = 0; g_Deaths[id] = 0; g_HS[id] = 0; 
        g_Planted[id] = 0; g_Defused[id] = 0;

        // 3. Utilizăm nvault_util pentru a căuta datele noului nume direct pe disc
        // Închidem bolta principală pentru a forța flush-ul datelor[cite: 3]
        nvault_close(g_Vault);
        g_Vault = nvault_open("rank_snapshot_pro");

        new vU = nvault_util_open("rank_snapshot_pro");
        if (vU != INVALID_HANDLE) {
            new count = nvault_util_count(vU);
            new pos = 0, k[35], v[128], ts;
            new pk[16], pd[16], phs[16], pp[16], pdf[16];

            // Scanăm fișierul pentru a vedea dacă noul nume are deja rank[cite: 2]
            for (new i = 1; i <= count; i++) {
                pos = nvault_util_read(vU, pos, k, 34, v, 127, ts);
                
                if (equal(k, new_name)) {
                    parse(v, pk, 15, pd, 15, phs, 15, pp, 15, pdf, 15);
                    
                    g_Kills[id] = str_to_num(pk);
                    g_Deaths[id] = str_to_num(pd);
                    g_HS[id] = str_to_num(phs);
                    g_Planted[id] = str_to_num(pp);
                    g_Defused[id] = str_to_num(pdf);
                    break;
                }
            }
            nvault_util_close(vU);
        }
        
        // Actualizăm poziția în rank pentru noul nume
        g_LastRank[id] = get_pos(id);
        
        // Opțional: Anunțăm schimbarea în chat
        client_print_color(id, print_team_default, "^4[Rank]^1 Datele au fost încărcate pentru noul nume: ^3%s", new_name);
    }
}
