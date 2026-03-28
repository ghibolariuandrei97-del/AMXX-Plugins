#include <amxmodx>
#include <fakemeta>

#define PLUGIN "Elite Kill Simple"
#define VERSION "1.0"
#define AUTHOR "ChatGPT"

// Data
new g_kills[33], g_objectives[33]
new g_max_players

#define TEAM_T 1
#define TEAM_CT 2

// ================= INIT =================
public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)

    register_event("DeathMsg", "on_death", "a")
    register_event("HLTV", "on_new_round", "a", "1=0", "2=0")
    register_event("SendAudio", "on_round_end", "a",
        "2=%!MRAD_ctwin",
        "2=%!MRAD_terwin",
        "2=%!MRAD_rounddraw"
    )

    register_logevent("log_bomb_planted", 3, "2=Planted_The_Bomb")
    register_logevent("log_bomb_defused", 3, "2=Defused_The_Bomb")
    register_logevent("log_hostage_rescued", 3, "2=Rescued_A_Hostage")

    g_max_players = get_maxplayers()
}

// ================= RESET =================
public on_new_round()
{
    for (new i = 1; i <= g_max_players; i++)
    {
        g_kills[i] = 0
        g_objectives[i] = 0
    }
}

public client_disconnected(id)
{
    g_kills[id] = 0
    g_objectives[id] = 0
}

// ================= OBJECTIVES =================
public log_bomb_planted()
{
    new name[32]; read_logargv(0, name, charsmax(name))
    new id = get_user_index(name)
    if (id) g_objectives[id]++
}

public log_bomb_defused()
{
    new name[32]; read_logargv(0, name, charsmax(name))
    new id = get_user_index(name)
    if (id) g_objectives[id]++
}

public log_hostage_rescued()
{
    new name[32]; read_logargv(0, name, charsmax(name))
    new id = get_user_index(name)
    if (id) g_objectives[id]++
}

// ================= KILL =================
public on_death()
{
    new killer = read_data(1)
    new victim = read_data(2)

    if (!is_user_connected(killer) || killer == victim)
        return

    new headshot = read_data(3)
    new weapon[32]
    read_data(4, weapon, charsmax(weapon))

    g_kills[killer]++

    new v_name[32]
    get_user_name(victim, v_name, charsmax(v_name))

    // Distance (meters)
    new Float:o1[3], Float:o2[3]
    pev(killer, pev_origin, o1)
    pev(victim, pev_origin, o2)
    new Float:distance = get_distance_f(o1, o2) * 0.0254

    new type[16]

    // ================= EFFECT =================
    if (headshot)
    {
        copy(type, charsmax(type), "HEADSHOT")
        client_cmd(killer, "spk weapons/hegrenade-1.wav")
        screen_fade(killer, 255, 0, 0, 120)
    }
    else if (equal(weapon, "knife"))
    {
        copy(type, charsmax(type), "KNIFE")
        client_cmd(killer, "spk weapons/flashbang-1.wav")
        screen_fade(killer, 150, 150, 150, 120)
    }
    else
    {
        copy(type, charsmax(type), "KILL")
        client_cmd(killer, "spk weapons/sg_explode.wav")
        screen_fade(killer, 0, 255, 0, 120)
    }

    // ================= HUD =================
    set_hudmessage(0, 255, 255, 0.02, 0.18, 0, 0.1, 4.0, 0.1, 0.1)
    show_hudmessage(killer,
        "KILL INFO^nVictim: %s^nType: %s^nDistance: %.1f m^nKills: %d",
        v_name,
        type,
        distance,
        g_kills[killer]
    )
}

// ================= ROUND END =================
public on_round_end()
{
    new best_t = 0, best_ct = 0
    new best_obj_t = 0, best_obj_ct = 0

    new max_k_t = -1, max_k_ct = -1
    new max_o_t = 0, max_o_ct = 0

    for (new i = 1; i <= g_max_players; i++)
    {
        if (!is_user_connected(i))
            continue

        new team = get_user_team(i)

        if (team == TEAM_T)
        {
            if (g_kills[i] > max_k_t)
            {
                max_k_t = g_kills[i]
                best_t = i
            }

            if (g_objectives[i] > max_o_t)
            {
                max_o_t = g_objectives[i]
                best_obj_t = i
            }
        }
        else if (team == TEAM_CT)
        {
            if (g_kills[i] > max_k_ct)
            {
                max_k_ct = g_kills[i]
                best_ct = i
            }

            if (g_objectives[i] > max_o_ct)
            {
                max_o_ct = g_objectives[i]
                best_obj_ct = i
            }
        }
    }

    new msg[256]
    new t_name[32], ct_name[32], obj_t_name[32], obj_ct_name[32]

    if (best_t) get_user_name(best_t, t_name, charsmax(t_name))
    if (best_ct) get_user_name(best_ct, ct_name, charsmax(ct_name))
    if (best_obj_t) get_user_name(best_obj_t, obj_t_name, charsmax(obj_t_name))
    if (best_obj_ct) get_user_name(best_obj_ct, obj_ct_name, charsmax(obj_ct_name))

    if (max_o_t == 0 && max_o_ct == 0)
    {
        format(msg, charsmax(msg),
            "ROUND SUMMARY^nT MVP: %s (%d kills)^nCT MVP: %s (%d kills)^nNo helpful players this round!",
            best_t ? t_name : "None", max_k_t,
            best_ct ? ct_name : "None", max_k_ct
        )
    }
    else
    {
        format(msg, charsmax(msg),
            "ROUND SUMMARY^nT MVP: %s (%d kills)^nCT MVP: %s (%d kills)^nT HERO: %s (%d obj)^nCT HERO: %s (%d obj)",
            best_t ? t_name : "None", max_k_t,
            best_ct ? ct_name : "None", max_k_ct,
            best_obj_t ? obj_t_name : "None", max_o_t,
            best_obj_ct ? obj_ct_name : "None", max_o_ct
        )
    }

    set_hudmessage(255, 200, 0, -1.0, 0.30, 1, 6.0, 6.0)
    show_hudmessage(0, msg)
}

// ================= FADE =================
stock screen_fade(id, r, g, b, alpha)
{
    static msg
    if (!msg) msg = get_user_msgid("ScreenFade")

    message_begin(MSG_ONE, msg, _, id)
    write_short(1<<12)
    write_short(1<<10)
    write_short(0)
    write_byte(r)
    write_byte(g)
    write_byte(b)
    write_byte(alpha)
    message_end()
}
