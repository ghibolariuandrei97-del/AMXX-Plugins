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
new Float:g_LaserStart[MAX_ENTS][3];
new Float:g_LaserEnd[MAX_ENTS][3];
new g_Sprite;
new g_pSageSpeed;
new g_pSageGlow;
new g_FwdBecomeSage;

public plugin_init()
{
    register_plugin("Great Sage", "v0.1", "AI");

    register_clcmd("say /sage", "cmd_sage");
    register_clcmd("say /sagehelp", "cmd_help");
    register_clcmd("say_team /sagehelp", "cmd_help");

    register_clcmd("say", "handle_say");
    register_clcmd("say_team", "handle_sayteam");
    register_clcmd("drop", "cmd_laser");
    register_impulse(100, "cmd_freeze");

    register_forward(FM_CmdStart, "fw_CmdStart");
    register_forward(FM_Think, "fw_Think");
    g_FwdBecomeSage = CreateMultiForward("user_become_sage", ET_IGNORE, FP_CELL);

    register_event("HLTV", "round_start", "a", "1=0", "2=0");
    register_event("CurWeapon", "ev_curweapon", "be", "1=1");

    g_pSageSpeed = register_cvar("sage_speed", "600.0");
    g_pSageGlow = register_cvar("sage_glow", "25");
}

public plugin_precache()
{
    g_Sprite = precache_model("sprites/laserbeam.spr");
}

public plugin_natives() {
    register_native("is_user_sage", "native_is_user_sage");
}

public native_is_user_sage(plugin, params)
{
    new id = get_param(1);
    
    if (!is_user_connected(id)) 
        return 0; // Nu e conectat, deci sigur nu e Sage
        
    return g_IsSage[id] ? 1 : 0; // Returneaza 1 daca e Sage, 0 daca nu e
}

public cmd_help(id)
{
    static motd[1024];
    new len;

    len += formatex(motd[len], charsmax(motd) - len, "<html><body style='background:#000;color:#fff;font-family:Arial;padding:20px;'>");
    len += formatex(motd[len], charsmax(motd) - len, "<h2 style='color:#00FF00;'>GREAT SAGE CONTROLS</h2>");
    len += formatex(motd[len], charsmax(motd) - len, "<p><b>E</b> - Instant kill</p>");
    len += formatex(motd[len], charsmax(motd) - len, "<p><b>R</b> - Teleport menu</p>");
    len += formatex(motd[len], charsmax(motd) - len, "<p><b>G</b> - Deadly laser</p>");
    len += formatex(motd[len], charsmax(motd) - len, "<p><b>F</b> - Global freeze</p>");
    len += formatex(motd[len], charsmax(motd) - len, "</body></html>");

    show_motd(id, motd, "Great Sage Help");
    return PLUGIN_HANDLED;
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
    set_user_rendering(id, kRenderFxGlowShell, 0, get_pcvar_num(g_pSageGlow), 0, kRenderNormal, 16);
    set_user_maxspeed(id, get_pcvar_float(g_pSageSpeed));

    new dummy;
    ExecuteForward(g_FwdBecomeSage, dummy, id);

    client_print(0, print_chat, "Great Sage activat!");
    cmd_help(id);
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

public handle_sayteam(id)
{
    if (!g_IsSage[id])
        return PLUGIN_CONTINUE;

    new msg[192];
    read_args(msg, charsmax(msg));
    remove_quotes(msg);

    if (!msg[0] || msg[0] == '/')
        return PLUGIN_CONTINUE;

    static motd[1024];
    new len;
    len += formatex(motd[len], charsmax(motd) - len, "<html><body style='background:#000;color:#00FF00;font-family:Arial;text-align:center;padding:40px;'>");
    len += formatex(motd[len], charsmax(motd) - len, "<h1>ORDIN DE LA GREAT SAGE</h1><hr><h2>%s</h2>", msg);
    len += formatex(motd[len], charsmax(motd) - len, "</body></html>");

    for (new i = 1; i <= 32; i++)
    {
        if (is_user_connected(i))
            show_motd(i, motd, "Mesaj Great Sage");
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
            if (g_IsFrozen) set_pev(i, pev_flags, flags | FL_FROZEN);
            else set_pev(i, pev_flags, flags & ~FL_FROZEN);
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

    if ((buttons & IN_RELOAD) && !(oldbuttons & IN_RELOAD))
    {
        new menu = menu_create("\yTeleporteaza jucatori vii:", "menu_tp_handler");
        menu_additem(menu, "\w1. Terrorists", "1");
        menu_additem(menu, "\w2. Counter-Terrorists", "2");
        menu_additem(menu, "\w3. All Players", "3");
        menu_additem(menu, "\w4. Specific Player", "4");
        menu_display(id, menu, 0);
    }

    return FMRES_IGNORED;
}

public menu_tp_handler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[6], name[64], access, callback;
    menu_item_getinfo(menu, item, access, data, 5, name, 63, callback);
    new choice = str_to_num(data);

    if (choice == 4)
    {
        show_specific_player_menu(id);
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new Float:origin[3];
    pev(id, pev_origin, origin);

    for (new i = 1; i <= 32; i++)
    {
        if (!is_user_alive(i) || i == id)
            continue;

        if ((choice == 1 && get_user_team(i) != 1) ||
            (choice == 2 && get_user_team(i) != 2))
            continue;

        teleport_unstuck(i, origin);
    }

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public show_specific_player_menu(id)
{
    new menu = menu_create("\yAlege jucator viu:", "specific_player_handler");
    new name[32], num[6];

    for (new i = 1; i <= 32; i++)
    {
        if (!is_user_alive(i) || i == id)
            continue;

        get_user_name(i, name, charsmax(name));
        num_to_str(i, num, charsmax(num));
        menu_additem(menu, name, num);
    }

    menu_display(id, menu, 0);
}

public specific_player_handler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[6], name[64], access, callback;
    menu_item_getinfo(menu, item, access, data, 5, name, 63, callback);
    new player = str_to_num(data);

    if (is_user_alive(player))
    {
        new Float:origin[3];
        pev(id, pev_origin, origin);
        teleport_unstuck(player, origin);
    }

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

teleport_unstuck(id, Float:center[3])
{
    new Float:pos[3];
    new Float:radius = 60.0;
    new Float:angle = 0.0;
    new tr;

    for (new attempt = 0; attempt < 40; attempt++)
    {
        pos[0] = center[0] + radius * floatcos(angle, degrees);
        pos[1] = center[1] + radius * floatsin(angle, degrees);
        pos[2] = center[2] + 10.0;

        engfunc(EngFunc_TraceHull, pos, pos, IGNORE_MONSTERS, HULL_HUMAN, 0, tr);
        if (!get_tr2(tr, TR_StartSolid) && !get_tr2(tr, TR_AllSolid))
        {
            engfunc(EngFunc_SetOrigin, id, pos);
            return;
        }

        angle += 45.0;
        if (angle >= 360.0)
        {
            angle = 0.0;
            radius += 40.0;
        }
    }

    engfunc(EngFunc_SetOrigin, id, center);
}

public cmd_laser(id)
{
    if (!g_IsSage[id])
        return PLUGIN_CONTINUE;

    if (!is_user_alive(id))
        return PLUGIN_HANDLED;

    new Float:origin[3], Float:view_ofs[3];
    new Float:eyes[3], Float:v_angle[3], Float:vecForward[3];
    new Float:end_trace[3], Float:hit[3], Float:normal[3], Float:laser_far[3], Float:real_end[3];
    new ent, tr, tr2;

    pev(id, pev_origin, origin);
    pev(id, pev_view_ofs, view_ofs);

    eyes[0] = origin[0] + view_ofs[0];
    eyes[1] = origin[1] + view_ofs[1];
    eyes[2] = origin[2] + view_ofs[2];

    pev(id, pev_v_angle, v_angle);
    engfunc(EngFunc_MakeVectors, v_angle);
    global_get(glb_v_forward, vecForward);

    end_trace[0] = eyes[0] + vecForward[0] * 8192.0;
    end_trace[1] = eyes[1] + vecForward[1] * 8192.0;
    end_trace[2] = eyes[2] + vecForward[2] * 8192.0;

    engfunc(EngFunc_TraceLine, eyes, end_trace, IGNORE_MONSTERS, id, tr);
    get_tr2(tr, TR_vecEndPos, hit);
    get_tr2(tr, TR_vecPlaneNormal, normal);

    laser_far[0] = hit[0] + normal[0] * 8192.0;
    laser_far[1] = hit[1] + normal[1] * 8192.0;
    laser_far[2] = hit[2] + normal[2] * 8192.0;

    engfunc(EngFunc_TraceLine, hit, laser_far, IGNORE_MONSTERS, 0, tr2);
    get_tr2(tr2, TR_vecEndPos, real_end);

    ent = create_entity("info_target");
    if (!pev_valid(ent))
        return PLUGIN_HANDLED;

    set_pev(ent, pev_classname, LASER_CLASS);
    set_pev(ent, pev_solid, SOLID_NOT);
    set_pev(ent, pev_nextthink, get_gametime() + 0.1);

    g_LaserStart[ent][0] = hit[0];
    g_LaserStart[ent][1] = hit[1];
    g_LaserStart[ent][2] = hit[2];

    g_LaserEnd[ent][0] = real_end[0];
    g_LaserEnd[ent][1] = real_end[1];
    g_LaserEnd[ent][2] = real_end[2];

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

    new Float:start[3], Float:beam_end[3];
    new tr, hit;

    start[0] = g_LaserStart[ent][0];
    start[1] = g_LaserStart[ent][1];
    start[2] = g_LaserStart[ent][2];

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
    write_byte(0); write_byte(0); write_byte(2); write_byte(15); write_byte(0);
    write_byte(255); write_byte(0); write_byte(0); write_byte(255); write_byte(0);
    message_end();

    engfunc(EngFunc_TraceLine, start, beam_end, DONT_IGNORE_MONSTERS, ent, tr);
    hit = get_tr2(tr, TR_pHit);

    if (is_user_alive(hit) && !g_IsSage[hit])
        user_kill(hit);

    set_pev(ent, pev_nextthink, get_gametime() + 0.1);
    return FMRES_IGNORED;
}

public ev_curweapon(id)
{
    if (g_IsSage[id] && is_user_alive(id))
    {
        set_user_maxspeed(id, get_pcvar_float(g_pSageSpeed));
        set_user_rendering(id, kRenderFxGlowShell, 0, get_pcvar_num(g_pSageGlow), 0, kRenderNormal, 16);
    }
}

public round_start()
{
    g_IsFrozen = false;

    new ent = -1;
    while ((ent = find_ent_by_class(ent, LASER_CLASS)) > 0)
        remove_entity(ent);

    for (new i = 1; i <= 32; i++)
    {
        g_IsSage[i] = false;
        if (is_user_connected(i))
        {
            set_user_godmode(i, 0);
            set_user_noclip(i, 0);
            set_user_rendering(i);
            set_user_maxspeed(i, 250.0);
            new flags = pev(i, pev_flags);
            set_pev(i, pev_flags, flags & ~FL_FROZEN);
        }
    }
}

