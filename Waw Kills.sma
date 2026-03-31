#include <amxmodx>
#include <fakemeta>

#define PLUGIN "Waw KILLs"
#define VERSION "1.0"
#define AUTHOR "Terra_FanClub"

new g_kills[33], g_objectives[33], g_total_kills[33]
new g_max_players
new g_msgScreenFade
new g_winning_team // 1 = T, 2 = CT, 0 = Draw

#define TEAM_T 1
#define TEAM_CT 2

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)

    register_event("DeathMsg", "on_death", "a")
    register_event("HLTV", "on_new_round", "a", "1=0", "2=0")
    
    // Catching the winner from the audio/text events
    register_event("SendAudio", "t_win", "a", "2=%!MRAD_terwin")
    register_event("SendAudio", "ct_win", "a", "2=%!MRAD_ctwin")
    register_event("SendAudio", "draw_win", "a", "2=%!MRAD_rounddraw")
    
    register_event("SendAudio", "on_round_end", "a", "2=%!MRAD_ctwin", "2=%!MRAD_terwin", "2=%!MRAD_rounddraw")

    register_logevent("log_objective", 3, "2=Planted_The_Bomb", "2=Defused_The_Bomb", "2=Rescued_A_Hostage")

    g_max_players = get_maxplayers()
    g_msgScreenFade = get_user_msgid("ScreenFade")
}

public t_win() g_winning_team = TEAM_T
public ct_win() g_winning_team = TEAM_CT
public draw_win() g_winning_team = 0

public on_new_round()
{
    arrayset(g_kills, 0, sizeof(g_kills))
    arrayset(g_objectives, 0, sizeof(g_objectives))
    g_winning_team = 0
}

public client_disconnected(id)
{
    g_kills[id] = 0
    g_objectives[id] = 0
    g_total_kills[id] = 0
}

public log_objective()
{
    new loguser[80], name[32]
    read_logargv(0, loguser, charsmax(loguser))
    parse_loguser(loguser, name, charsmax(name))
    new id = get_user_index(name)
    if (id && is_user_connected(id)) g_objectives[id]++
}

// ================= KILL LOGIC (COMBO + GLOBAL TRACKING) =================

public on_death()
{
    new killer = read_data(1)
    new victim = read_data(2)
    new headshot = read_data(3)
    new weapon[32]
    read_data(4, weapon, charsmax(weapon))

    if (!(1 <= killer <= g_max_players) || !is_user_connected(killer) || killer == victim)
        return

    g_kills[killer]++
    g_total_kills[killer]++ // Permanent tracker for the map
    
    new combo = g_kills[killer]
    if (combo > 10) combo = 10 

    new v_name[32]
    get_user_name(victim, v_name, charsmax(v_name))

    new Float:o1[3], Float:o2[3]
    pev(killer, pev_origin, o1)
    pev(victim, pev_origin, o2)
    new Float:distance = get_distance_f(o1, o2) * 0.0254 

    new type[16]

    if (headshot)
    {
        copy(type, charsmax(type), "HEADSHOT")
        client_cmd(killer, "spk weapons/hegrenade-1.wav")
        screen_fade(killer, 255, 0, 0, 110 + (combo * 15), combo) 
        create_glow(killer, 255, 0, 0, 20 + combo) 
    }
    else if (equal(weapon, "knife"))
    {
        copy(type, charsmax(type), "KNIFE")
        client_cmd(killer, "spk weapons/flashbang-1.wav")
        screen_fade(killer, 200, 200, 200, 140 + (combo * 15), combo)
        create_glow(killer, 255, 255, 255, 25 + combo)
    }
    else
    {
        copy(type, charsmax(type), "KILL")
        client_cmd(killer, "spk weapons/sg_explode.wav")
        screen_fade(killer, 0, 255, 0, 60 + (combo * 15), combo)
        create_glow(killer, 0, 255, 0, 15 + combo)
    }

    set_hudmessage(0, 255, 255, 0.02, 0.2, 0, 0.1, 3.0, 0.1, 0.1)
    show_hudmessage(killer, "KILL INFO^nVictim: %s^nType: %s^nDistance: %.1fm^nRound Kills: %d", 
        v_name, type, distance, g_kills[killer])
}

// ================= ENHANCED SUMMARY =================

public on_round_end()
{
    new best_k_t, best_k_ct, best_o_t, best_o_ct, server_best
    new max_k_t = 0, max_k_ct = 0, max_o_t = 0, max_o_ct = 0, max_server = 0

    for (new i = 1; i <= g_max_players; i++)
    {
        if (!is_user_connected(i)) continue
        
        // Check for Server MVP (Total kills since map start)
        if (g_total_kills[i] > max_server) { max_server = g_total_kills[i]; server_best = i; }

        new team = get_user_team(i)
        if (team == TEAM_T)
        {
            if (g_kills[i] > max_k_t) { max_k_t = g_kills[i]; best_k_t = i; }
            if (g_objectives[i] > max_o_t) { max_o_t = g_objectives[i]; best_o_t = i; }
        }
        else if (team == TEAM_CT)
        {
            if (g_kills[i] > max_k_ct) { max_k_ct = g_kills[i]; best_k_ct = i; }
            if (g_objectives[i] > max_o_ct) { max_o_ct = g_objectives[i]; best_o_ct = i; }
        }
    }

    new kname_t[32], kname_ct[32], oname_t[32], oname_ct[32], sname[32], winname[32]
    
    (max_k_t > 0) ? get_user_name(best_k_t, kname_t, 31) : copy(kname_t, 31, "None")
    (max_k_ct > 0) ? get_user_name(best_k_ct, kname_ct, 31) : copy(kname_ct, 31, "None")
    (max_o_t > 0) ? get_user_name(best_o_t, oname_t, 31) : copy(oname_t, 31, "None")
    (max_o_ct > 0) ? get_user_name(best_o_ct, oname_ct, 31) : copy(oname_ct, 31, "None")
    (max_server > 0) ? get_user_name(server_best, sname, 31) : copy(sname, 31, "None")

    if (g_winning_team == TEAM_T) copy(winname, 31, "TERRORISTS WIN")
    else if (g_winning_team == TEAM_CT) copy(winname, 31, "CTs WIN")
    else copy(winname, 31, "ROUND DRAW")

    set_hudmessage(255, 210, 0, -1.0, 0.25, 1, 6.0, 6.0, 0.5, 0.5)
    show_hudmessage(0, "--- %s ---^n^n\
        T MVP: %s (%d Kills)^n\
        CT MVP: %s (%d Kills)^n\
        T HERO: %s (%d Obj)^n\
        CT HERO: %s (%d Obj)^n^n\
        [ SERVER BEST: %s with %d total kills ]", 
        winname, kname_t, max_k_t, kname_ct, max_k_ct, oname_t, max_o_t, oname_ct, max_o_ct, sname, max_server)
}

// ================= FX HELPERS =================

stock screen_fade(id, r, g, b, alpha, combo)
{
    if (alpha > 255) alpha = 255
    message_begin(MSG_ONE_UNRELIABLE, g_msgScreenFade, _, id)
    write_short((1 << 11) + (combo * 200)) 
    write_short((1 << 10) + (combo * 100)) 
    write_short(0x0000) 
    write_byte(r); write_byte(g); write_byte(b); write_byte(alpha)
    message_end()
}

stock create_glow(id, r, g, b, radius)
{
    static Float:fOrigin[3]; pev(id, pev_origin, fOrigin)
    static iOrigin[3]
    iOrigin[0] = floatround(fOrigin[0]); iOrigin[1] = floatround(fOrigin[1]); iOrigin[2] = floatround(fOrigin[2])

    message_begin(MSG_PVS, SVC_TEMPENTITY, iOrigin) 
    write_byte(TE_DLIGHT) 
    write_coord(iOrigin[0]); write_coord(iOrigin[1]); write_coord(iOrigin[2])
    write_byte(radius); write_byte(r); write_byte(g); write_byte(b) 
    write_byte(5); write_byte(40)
    message_end()
}
