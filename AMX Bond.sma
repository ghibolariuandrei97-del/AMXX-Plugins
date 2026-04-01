#pragma semicolon 1

#include <amxmodx>
#include <engine>
#include <reapi>
#include <hamsandwich>

#define PLUGIN "Bond System Share"
#define VERSION "1.0"
#define AUTHOR "AI"

// CONFIG
#define MAX_BONDS 32
#define MAX_DIST 2500

new g_bond[33][33];
new g_bondCount[33];

new g_spriteBeam;
new g_maxPlayers;

// CVARS
new g_pRequest;
new g_pDmgShare;

// Anti recursion
new bool:g_blockDamage;

//---------------------------------------------

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("bond", "cmd_bond");
    register_clcmd("bonds", "cmd_menu");

    g_pRequest  = register_cvar("amx_bond_request", "1");
    g_pDmgShare = register_cvar("amx_bond_damageshare", "1");

    RegisterHookChain(RG_CBasePlayer_TakeDamage, "fw_TakeDamage", 0);

    g_maxPlayers = get_maxplayers();

    set_task(0.4, "draw_beams", .flags="b");
}

//---------------------------------------------

public plugin_precache()
{
    g_spriteBeam = precache_model("sprites/laserbeam.spr");
}

//---------------------------------------------
// BOND

public cmd_bond(id)
{
    if (!is_user_alive(id)) return PLUGIN_HANDLED;

    new target, body;
    get_user_aiming(id, target, body);

    if (!is_user_alive(target) || id == target)
        return PLUGIN_HANDLED;

    if (get_member(id, m_iTeam) != get_member(target, m_iTeam))
        return PLUGIN_HANDLED;

    static request[33][33];

    if (get_pcvar_num(g_pRequest))
    {
        if (request[target][id])
        {
            create_bond(id, target);
            request[target][id] = 0;
            return PLUGIN_HANDLED;
        }

        request[id][target] = 1;

        client_print(id, print_chat, "[Bond] Request sent");
        client_print(target, print_chat, "[Bond] Press bond to accept");
    }
    else
    {
        create_bond(id, target);
    }

    return PLUGIN_HANDLED;
}

//---------------------------------------------

create_bond(id, target)
{
    if (g_bond[id][target]) return;

    g_bond[id][target] = 1;
    g_bond[target][id] = 1;

    g_bondCount[id]++;
    g_bondCount[target]++;

    client_print(id, print_chat, "[Bond] Connected!");
    client_print(target, print_chat, "[Bond] Connected!");
}

//---------------------------------------------
// MENU

public cmd_menu(id)
{
    new menu = menu_create("Your Bonds:", "menu_handler");

    new name[32], info[4];

    for (new i = 1; i <= g_maxPlayers; i++)
    {
        if (g_bond[id][i] && is_user_connected(i))
        {
            get_user_name(i, name, charsmax(name));
            num_to_str(i, info, charsmax(info));
            menu_additem(menu, name, info);
        }
    }

    menu_display(id, menu);
}

//---------------------------------------------

public menu_handler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new access, callback;
    new info[4], name[32];

    menu_item_getinfo(menu, item, access, info, charsmax(info), name, charsmax(name), callback);

    new target = str_to_num(info);

    remove_bond(id, target);

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

//---------------------------------------------

remove_bond(id, target)
{
    g_bond[id][target] = 0;
    g_bond[target][id] = 0;

    client_print(id, print_chat, "[Bond] Removed");
    client_print(target, print_chat, "[Bond] Removed");
}

//---------------------------------------------
// 🔥 GROUP SYSTEM

get_bond_group(start, players[32])
{
    new count = 0;

    for (new i = 1; i <= g_maxPlayers; i++)
    {
        if ((i == start || g_bond[start][i]) && is_user_alive(i))
        {
            players[count++] = i;
        }
    }

    return count;
}

//---------------------------------------------
// 🔥 DAMAGE SHARE ONLY

public fw_TakeDamage(victim, inflictor, attacker, Float:damage)
{
    if (g_blockDamage) return HC_CONTINUE;
    if (!get_pcvar_num(g_pDmgShare)) return HC_CONTINUE;
    if (!is_user_alive(victim)) return HC_CONTINUE;

    new group[32];
    new count = get_bond_group(victim, group);

    if (count <= 1) return HC_CONTINUE;

    g_blockDamage = true;

    new Float:split = damage / float(count);

    // victim gets reduced damage
    SetHookChainArg(4, ATYPE_FLOAT, split);

    for (new i = 0; i < count; i++)
    {
        new id = group[i];

        if (id == victim) continue;

        ExecuteHamB(Ham_TakeDamage, id, inflictor, attacker, split, DMG_GENERIC);
    }

    g_blockDamage = false;

    return HC_CONTINUE;
}

//---------------------------------------------
// BEAMS (SAFE)

public draw_beams()
{
    new players[32], num;
    get_players(players, num, "a");

    for (new i = 0; i < num; i++)
    {
        for (new j = i + 1; j < num; j++)
        {
            new id = players[i];
            new target = players[j];

            if (!g_bond[id][target]) continue;

            draw_line(id, target);
        }
    }
}

//---------------------------------------------

draw_line(id, target)
{
    new o1[3], o2[3];
    get_user_origin(id, o1);
    get_user_origin(target, o2);

    send_beam(id, o1, o2);
    send_beam(target, o1, o2);
}

send_beam(player, o1[3], o2[3])
{
    message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, player);

    write_byte(TE_BEAMPOINTS);

    write_coord(o1[0]); write_coord(o1[1]); write_coord(o1[2]);
    write_coord(o2[0]); write_coord(o2[1]); write_coord(o2[2]);

    write_short(g_spriteBeam);
    write_byte(0);
    write_byte(0);
    write_byte(4);
    write_byte(4);
    write_byte(0);

    write_byte(0);
    write_byte(255);
    write_byte(180);

    write_byte(120);
    write_byte(0);

    message_end();
}
