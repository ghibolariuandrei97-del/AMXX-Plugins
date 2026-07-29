#include <amxmodx>
#include <fakemeta>

#define PLUGIN  "AMXX Tags"
#define VERSION "1.5"
#define AUTHOR  "Astarasefk"

#define TASK_SEND_MSG 2000
#define TASK_RESTORE  3000

#define MAX_NAME_LENGTH 32
#define MAX_TAG_LENGTH 12 // Lungimea maxima a tag-ului (inclusiv caracterul null)

enum _:DeathData {
    D_KILLER,
    D_VICTIM,
    D_HS,
    D_WEAPON[32]
}

new g_szTags[33][MAX_TAG_LENGTH];
new g_szRealNames[33][MAX_NAME_LENGTH];
new bool:g_bIsSwapping[33];
new bool:g_bInternalMsg = false;

new g_msgDeathMsg;
new g_msgSayText;
new g_msgTextMsg;

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // Commands
    register_clcmd("say", "handle_say");
    register_clcmd("say_team", "handle_say");
    
    // Menu Command
    register_clcmd("say /tags", "cmd_show_tags_menu");
    register_clcmd("say_team /tags", "cmd_show_tags_menu");

    // Message IDs
    g_msgDeathMsg = get_user_msgid("DeathMsg");
    g_msgSayText  = get_user_msgid("SayText");
    g_msgTextMsg  = get_user_msgid("TextMsg");

    // Hooks
    register_message(g_msgDeathMsg, "hook_DeathMsg");
    register_message(g_msgTextMsg, "hook_SuppressMessages");
    register_message(g_msgSayText, "hook_SuppressSayText");
}

public client_putinserver(id) {
    g_szTags[id][0] = 0;
    g_bIsSwapping[id] = false;
    get_user_name(id, g_szRealNames[id], charsmax(g_szRealNames[]));
}

// --- Command Handling ---

public handle_say(id) {
    static szArgs[64];
    read_args(szArgs, charsmax(szArgs));
    remove_quotes(szArgs);

    // Ignoara /tags pentru a fi gestionat de cmd_show_tags_menu
    if (equal(szArgs, "/tags") || equal(szArgs, "/tags ", 6)) {
        return PLUGIN_CONTINUE;
    }

    if (equal(szArgs, "/tag", 4)) {
        static szCommand[16], szTag[MAX_TAG_LENGTH * 2];
        
        parse(szArgs, szCommand, charsmax(szCommand), szTag, charsmax(szTag));

        if (szTag[0] == 0) {
            client_print_color(id, print_team_default, "^4* ^1Ca sa iti pui un tag, scrie ^3/tag NUME-TAG ^1sau ^3/tag 0 ^1ca sa-ti scoti tag-ul !");
            client_print_color(id, print_team_default, "^4* ^1Scrie ^3/tags ^1pentru a vedea ce tag-uri au ceilalti jucatori.");
            return PLUGIN_HANDLED;
        }

        if (equal(szTag, "0")) {
            g_szTags[id][0] = 0;
            client_print_color(id, print_team_default, "^4* ^1Tag-ul tau a fost ^3scos^1.");
            return PLUGIN_HANDLED;
        }

        // Verificare lungime tag
        if (strlen(szTag) > MAX_TAG_LENGTH - 1) {
            client_print_color(id, print_team_default, "^4* ^3Eroare! ^1Tag-ul introdus este prea lung! (Maxim ^4%d ^1caractere)", MAX_TAG_LENGTH - 1);
            return PLUGIN_HANDLED;
        }

        copy(g_szTags[id], charsmax(g_szTags[]), szTag);
        trim(g_szTags[id]);
        
        client_print_color(id, print_team_default, "^4* ^1Tag-ul tau in killfeed este acum: ^4%s", g_szTags[id]);
        
        // Verificare lungime nume + tag combinat
        if (strlen(g_szTags[id]) + 1 + strlen(g_szRealNames[id]) > 31) {
            client_print_color(id, print_team_default, "^4* ^3Atenție! ^1Numele tău complet va fi scurtat în killfeed din cauza lungimii!");
        }
        
        return PLUGIN_HANDLED;
    }
    
    return PLUGIN_CONTINUE;
}

// --- Dynamic Menu /tags ---

public cmd_show_tags_menu(id) {
    new iMenu = menu_create("\yTag-uri Jucatori Conectati:", "menu_tags_handler");
    new szItem[64], szUserId[6];
    new iCount = 0;

    for (new i = 1; i <= MaxClients; i++) {
        if (!is_user_connected(i) || g_szTags[i][0] == 0)
            continue;

        num_to_str(get_user_userid(i), szUserId, charsmax(szUserId));
        formatex(szItem, charsmax(szItem), "\w[%s] \y%s", g_szTags[i], g_szRealNames[i]);

        menu_additem(iMenu, szItem, szUserId);
        iCount++;
    }

    if (iCount == 0) {
        client_print_color(id, print_team_default, "^4* ^1Niciun jucator nu are un tag activ pe server!");
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    menu_display(id, iMenu, 0);
    return PLUGIN_HANDLED;
}

public menu_tags_handler(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[6], szName[64], access, callback;
    menu_item_getinfo(menu, item, access, szData, charsmax(szData), szName, charsmax(szName), callback);

    new iUserId = str_to_num(szData);
    new iTarget = find_player("k", iUserId);

    if (iTarget && g_szTags[iTarget][0] != 0) {
        copy(g_szTags[id], charsmax(g_szTags[]), g_szTags[iTarget]);
        client_print_color(id, print_team_default, "^4* ^1Ai copiat tag-ul [^4%s^1] de la ^3%s^1!", g_szTags[id], g_szRealNames[iTarget]);

        if (strlen(g_szTags[id]) + 1 + strlen(g_szRealNames[id]) > 31) {
            client_print_color(id, print_team_default, "^4* ^3Atenție! ^1Numele tău complet va fi scurtat în killfeed din cauza lungimii!");
        }
    } else {
        client_print_color(id, print_team_default, "^4* ^1Jucătorul respectiv nu mai are acest tag sau s-a deconectat!");
    }

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// --- Core KillFeed Logic ---

public hook_DeathMsg(msg_id, msg_dest, msg_entity) {
    if (g_bInternalMsg) return PLUGIN_CONTINUE;

    new killer = get_msg_arg_int(1);
    new victim = get_msg_arg_int(2);
    
    if (victim < 1 || victim > MaxClients) return PLUGIN_CONTINUE;

    new bool:bKillerValid = (killer > 0 && killer <= MaxClients && is_user_connected(killer));
    new bool:bKillerHasTag = (bKillerValid && g_szTags[killer][0] != 0);
    new bool:bVictimHasTag = (g_szTags[victim][0] != 0);

    if (!bKillerHasTag && !bVictimHasTag) return PLUGIN_CONTINUE;

    if (bKillerHasTag) {
        set_temp_name(killer);
    }
    if (bVictimHasTag) {
        set_temp_name(victim);
    }

    new data[DeathData];
    data[D_KILLER] = killer;
    data[D_VICTIM] = victim;
    data[D_HS] = get_msg_arg_int(3);
    get_msg_arg_string(4, data[D_WEAPON], charsmax(data[D_WEAPON]));

    set_task(0.05, "task_send_custom_msg", victim + TASK_SEND_MSG, data, sizeof(data));

    return PLUGIN_HANDLED;
}

public task_send_custom_msg(data[DeathData], taskid) {
    g_bInternalMsg = true;
    message_begin(MSG_ALL, g_msgDeathMsg);
    write_byte(data[D_KILLER]);
    write_byte(data[D_VICTIM]);
    write_byte(data[D_HS]);
    write_string(data[D_WEAPON]);
    message_end();
    g_bInternalMsg = false;

    if (data[D_KILLER] > 0 && data[D_KILLER] <= MaxClients) {
        set_task(0.1, "task_restore_name", data[D_KILLER] + TASK_RESTORE);
    }
    set_task(0.1, "task_restore_name", data[D_VICTIM] + TASK_RESTORE);
}

set_temp_name(id) {
    if (!is_user_connected(id)) return;
    
    new szNewName[32];
    formatex(szNewName, charsmax(szNewName), "%s %s", g_szTags[id], g_szRealNames[id]);
    szNewName[31] = 0;

    g_bIsSwapping[id] = true;
    set_user_info(id, "name", szNewName);
    set_pev(id, pev_netname, szNewName);
}

public task_restore_name(taskid) {
    new id = taskid - TASK_RESTORE;
    if (!is_user_connected(id)) return;

    set_user_info(id, "name", g_szRealNames[id]);
    set_pev(id, pev_netname, g_szRealNames[id]);
    set_task(0.2, "task_clear_swap_flag", id);
}

public task_clear_swap_flag(id) {
    g_bIsSwapping[id] = false;
}

public hook_SuppressMessages(msg_id, msg_dest, msg_entity) {
    if (msg_id == g_msgTextMsg) {
        static szMsg[64];
        get_msg_arg_string(2, szMsg, charsmax(szMsg));
        if (equal(szMsg, "#Cstrike_Name_Change") || contain(szMsg, "Name_Change") != -1) {
            return PLUGIN_HANDLED;
        }
    }
    return PLUGIN_CONTINUE;
}

public hook_SuppressSayText(msg_id, msg_dest, msg_entity) {
    static szMsg[128];
    get_msg_arg_string(2, szMsg, charsmax(szMsg));

    if (contain(szMsg, "#Cstrike_Name_Change") != -1 || 
       (contain(szMsg, "name") != -1 && contain(szMsg, "changed") != -1) ||
       (contain(szMsg, "name") != -1 && contain(szMsg, "round") != -1)) {
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public client_infochanged(id) {
    if (!is_user_connected(id) || g_bIsSwapping[id]) return PLUGIN_CONTINUE;
    
    static szNewName[MAX_NAME_LENGTH];
    get_user_info(id, "name", szNewName, charsmax(szNewName));

    if (szNewName[0] != 0 && !equal(szNewName, g_szRealNames[id])) {
        copy(g_szRealNames[id], charsmax(g_szRealNames[]), szNewName);
    }
    return PLUGIN_CONTINUE;
}

public client_disconnected(id)
{
    remove_task(id + TASK_RESTORE);
    remove_task(id + TASK_SEND_MSG);

    g_szTags[id][0] = 0;
    g_bIsSwapping[id] = false;
}
