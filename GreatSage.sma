#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <fun>

#define MAX_ENTS 2048

new const LASER_CLASS[] = "sage_laser";

new bool:g_IsSage[33];
new bool:g_IsFrozen;
new Float:g_LastKillTime[33];
new Float:g_LastHud[33];
new Float:g_LaserEnd[MAX_ENTS][3];
new g_Sprite;

public plugin_init()
{
    register_plugin("Great Sage", "6.2", "ChatGPT");

    register_clcmd("say /sage", "cmd_sage");
    register_clcmd("say", "handle_say");
    register_clcmd("say_team", "handle_say");
    register_clcmd("drop", "cmd_laser");
    register_impulse(100, "cmd_freeze");

    register_forward(FM_CmdStart, "fw_CmdStart");
    register_forward(FM_Think, "fw_Think");

    register_event("HLTV", "round_start", "a", "1=0", "2=0");
}

public plugin_precache()
{
    g_Sprite = precache_model("sprites/laserbeam.spr");
}

public cmd_sage(id)
{
    if (!is_user_alive(id))
        return PLUGIN_HANDLED;

    for (new i = 1; i <= 32; i++)
    {
        if (g_IsSage[i])
        {
            client_print(id, print_chat, "Exista deja un Great Sage!");
            return PLUGIN_HANDLED;
        }
    }

    g_IsSage[id] = true;
    set_user_godmode(id, 1);
    set_user_noclip(id, 1);
    client_print(0, print_chat, "Great Sage activat!");
    return PLUGIN_HANDLED;
}

public handle_say(id)
{
    if (!g_IsSage[id])
        return PLUGIN_CONTINUE;

    new msg[192];
    read_args(msg, charsmax(msg));
    remove_quotes(msg);

    if (!msg[0] || msg[0] == '/')
        return PLUGIN_CONTINUE;

    if (get_gametime() - g_LastHud[id] >= 1.0)
    {
        g_LastHud[id] = get_gametime();
        set_hudmessage(0, 255, 0, -1.0, 0.3, 0, 0.0, 4.0, 0.1, 0.1, -1);
        show_hudmessage(0, "GREAT SAGE:^n%s", msg);
    }

    return PLUGIN_HANDLED;
}

public cmd_freeze(id)
{
    if (!g_IsSage[id])
        return PLUGIN_CONTINUE;

    g_IsFrozen = !g_IsFrozen;

    for (new i = 1; i <= 32; i++)
    {
        if (is_user_alive(i) && !g_IsSage[i])
        {
            new flags = pev(i, pev_flags);
            set_pev(i, pev_flags, g_IsFrozen ? (flags | FL_FROZEN) : (flags & ~FL_FROZEN));
        }
    }
    return PLUGIN_HANDLED;
}

public fw_CmdStart(id, uc_handle, seed)
{
    if (!g_IsSage[id] || !is_user_alive(id))
        return FMRES_IGNORED;

    new buttons = get_uc(uc_handle, UC_Buttons);
    new oldbuttons = pev(id, pev_oldbuttons);

    if ((buttons & IN_USE) && !(oldbuttons & IN_USE))
    {
        if (get_gametime() - g_LastKillTime[id] >= 0.5)
        {
            new target, body;
            get_user_aiming(id, target, body, 1500);

            if (is_user_alive(target) && target != id)
            {
                user_kill(target);
                g_LastKillTime[id] = get_gametime();
            }
        }
    }
    return FMRES_IGNORED;
}

public cmd_laser(id)
{
    if (!g_IsSage[id] || !is_user_alive(id))
        return PLUGIN_HANDLED;

    new Float:origin[3], Float:view_ofs[3];
    new Float:eyes[3], Float:v_angle[3], Float:forward[3];
    new Float:end_trace[3], Float:hit[3];
    new ent, tr;

    pev(id, pev_origin, origin);
    pev(id, pev_view_ofs, view_ofs);

    eyes[0] = origin[0] + view_ofs[0];
    eyes[1] = origin[1] + view_ofs[1];
    eyes[2] = origin[2] + view_ofs[2];

    pev(id, pev_v_angle, v_angle);
    engfunc(EngFunc_MakeVectors, v_angle);
    global_get(glb_v_forward, forward);

    end_trace[0] = eyes[0] + forward[0] * 8192.0;
    end_trace[1] = eyes[1] + forward[1] * 8192.0;
    end_trace[2] = eyes[2] + forward[2] * 8192.0;

    engfunc(EngFunc_TraceLine, eyes, end_trace, IGNORE_MONSTERS, id, tr);
    get_tr2(tr, TR_vecEndPos, hit);

    ent = create_entity("info_target");
    if (!pev_valid(ent))
        return PLUGIN_HANDLED;

    set_pev(ent, pev_classname, LASER_CLASS);
    set_pev(ent, pev_origin, hit);
    set_pev(ent, pev_solid, SOLID_NOT);
    set_pev(ent, pev_nextthink, get_gametime() + 0.1);

    g_LaserEnd[ent][0] = end_trace[0];
    g_LaserEnd[ent][1] = end_trace[1];
    g_LaserEnd[ent][2] = end_trace[2];

    return PLUGIN_HANDLED;
}

public fw_Think(ent)
{
    if (!pev_valid(ent))
        return FMRES_IGNORED;

    static classname[32];
    pev(ent, pev_classname, classname, 31);

    if (!equal(classname, LASER_CLASS))
        return FMRES_IGNORED;

    new Float:start[3];
    new Float:beam_end[3];
    new tr, hit;

    pev(ent, pev_origin, start);

    beam_end[0] = g_LaserEnd[ent][0];
    beam_end[1] = g_LaserEnd[ent][1];
    beam_end[2] = g_LaserEnd[ent][2];

    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMPOINTS);
    engfunc(EngFunc_WriteCoord, start[0]);
    engfunc(EngFunc_WriteCoord, start[1]);
    engfunc(EngFunc_WriteCoord, start[2]);
    engfunc(EngFunc_WriteCoord, beam_end[0]);
    engfunc(EngFunc_WriteCoord, beam_end[1]);
    engfunc(EngFunc_WriteCoord, beam_end[2]);
    write_short(g_Sprite);
    write_byte(0);
    write_byte(0);
    write_byte(2);
    write_byte(15);
    write_byte(0);
    write_byte(255);
    write_byte(0);
    write_byte(0);
    write_byte(255);
    write_byte(0);
    message_end();

    engfunc(EngFunc_TraceLine, start, beam_end, DONT_IGNORE_MONSTERS, ent, tr);
    hit = get_tr2(tr, TR_pHit);

    if (is_user_alive(hit) && !g_IsSage[hit])
        user_kill(hit);

    set_pev(ent, pev_nextthink, get_gametime() + 0.1);
    return FMRES_IGNORED;
}

public round_start()
{
    g_IsFrozen = false;

    new ent = -1;
    while ((ent = find_ent_by_class(ent, LASER_CLASS)) > 0)
    {
        remove_entity(ent);
    }

    for (new i = 1; i <= 32; i++)
    {
        g_IsSage[i] = false;
        if (is_user_connected(i))
        {
            set_user_godmode(i, 0);
            set_user_noclip(i, 0);
            new flags = pev(i, pev_flags);
            set_pev(i, pev_flags, flags & ~FL_FROZEN);
        }
    }
}
