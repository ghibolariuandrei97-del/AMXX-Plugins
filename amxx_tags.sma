#include <amxmodx>
#include <amxmisc>
#include <fakemeta>

#define PLUGIN  "AMXX Tags"
#define VERSION "1.2"
#define AUTHOR  "Astarasefk"

#define TASK_SEND_MSG 2000
#define TASK_RESTORE  3000

#define MAX_NAME_LENGTH 32
#define MAX_TAG_LENGTH 12

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

    if (equal(szArgs, "/tag", 4)) {
        static szCommand[16], szTag[MAX_TAG_LENGTH];
        
        parse(szArgs, szCommand, charsmax(szCommand), szTag, charsmax(szTag));

        if (szTag[0] == 0) {
            client_print(id, print_chat, "* Ca sa iti pui un tag, scrie /tag NUME-TAG sau /tag 0 ca sa-ti scoti tag-ul !");
            return PLUGIN_HANDLED;
        }

        if (equal(szTag, "0")) {
            g_szTags[id][0] = 0;
            client_print(id, print_chat, "* Tag-ul tau a fost scos.");
            return PLUGIN_HANDLED;
        }

        copy(g_szTags[id], charsmax(g_szTags[]), szTag);
        trim(g_szTags[id]);
        client_print(id, print_chat, "* Tag-ul tau in killfeed este acum: %s", g_szTags[id]);
        
        return PLUGIN_HANDLED;
    }
    
    return PLUGIN_CONTINUE;
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

// Blocheaza notificarile de sistem din TextMsg
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

// Blocheaza mesajele de schimbare de nume din SayText (fara sa blocheze chatul normal)
public hook_SuppressSayText(msg_id, msg_dest, msg_entity) {
    static szMsg[128];
    get_msg_arg_string(2, szMsg, charsmax(szMsg));

    // Daca mesajul vine de la sistem si contine "name" + "changed" sau "next round"
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
