#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <engine>

/* --- Configuration --- */
new const sz_FileName[] = "player_models.ini";

/* --- Internal Constants & Globals --- */
enum {
    TAG_NONE = 0,
    TAG_VIP,
    TAG_ADMIN,
    TAG_GIRL
};

// We define the model names directly in a constant array to avoid "constant expression" errors
new const sz_ModelNames[][] = {
    "",             // TAG_NONE
    "VIP",          // TAG_VIP
    "ADMIN",        // TAG_ADMIN
    "GIRL"          // TAG_GIRL
};

new Trie:g_tPlayerTags;
new g_iPlayerTag[MAX_PLAYERS + 1];
new bool:g_bThirdPerson[MAX_PLAYERS + 1];

public plugin_init() 
{
    // Plugin Information
    register_plugin("ReAPI Player Models", "1.0", "Astarasefk");

    // Hook player spawn to apply model
    RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawn", .post = 1);

    // Commands
    register_clcmd("say /cam", "clcmd_Cam");
    register_clcmd("say_team /cam", "clcmd_Cam");
}

public clcmd_Cam(id)
{
    if(!is_user_connected(id))
        return PLUGIN_HANDLED;

    g_bThirdPerson[id] = !g_bThirdPerson[id];

    if(g_bThirdPerson[id])
    {
        set_view(id, CAMERA_3RDPERSON);
        client_print(id, print_chat, "* Camera set to Third Person.");
    }
    else
    {
        set_view(id, CAMERA_NONE);
        client_print(id, print_chat, "* Camera set to First Person.");
    }

    return PLUGIN_HANDLED;
}


public plugin_precache() {
    g_tPlayerTags = TrieCreate();
    
    // Precache all custom models
    // Format: models/player/T_TAG/T_TAG.mdl and models/player/CT_TAG/CT_TAG.mdl
    new sz_Path[128];
    
    // Loop through tags 1 to 3 (VIP, ADMIN, GIRL)
    for(new i = 1; i < sizeof(sz_ModelNames); i++) {
        // Precache Terrorist version
        formatex(sz_Path, charsmax(sz_Path), "models/player/T_%s/T_%s.mdl", sz_ModelNames[i], sz_ModelNames[i]);
        precache_model(sz_Path);
        
        // Precache CT version
        formatex(sz_Path, charsmax(sz_Path), "models/player/CT_%s/CT_%s.mdl", sz_ModelNames[i], sz_ModelNames[i]);
        precache_model(sz_Path);
    }

    load_models_file();
}

public plugin_end() {
    if (g_tPlayerTags != Invalid_Trie) {
        TrieDestroy(g_tPlayerTags);
    }
}

load_models_file() {
    new sz_FilePath[128];
    get_configsdir(sz_FilePath, charsmax(sz_FilePath));
    add(sz_FilePath, charsmax(sz_FilePath), "/");
    add(sz_FilePath, charsmax(sz_FilePath), sz_FileName);

    if (!file_exists(sz_FilePath)) {
        new i_FileHandle = fopen(sz_FilePath, "wt");
        if (i_FileHandle) {
            fputs(i_FileHandle, "; Format: ^"Name^" ^"TAG^"^n; Tags: VIP, ADMIN, GIRL^n");
            fclose(i_FileHandle);
        }
        return;
    }

    new i_File = fopen(sz_FilePath, "rt");
    if (!i_File) return;

    new sz_Line[128], sz_Name[32], sz_Tag[16];
    while (!feof(i_File)) {
        fgets(i_File, sz_Line, charsmax(sz_Line));
        trim(sz_Line);

        if (!sz_Line[0] || sz_Line[0] == ';' || sz_Line[0] == '/')
            continue;

        if (parse(sz_Line, sz_Name, charsmax(sz_Name), sz_Tag, charsmax(sz_Tag)) < 2)
            continue;

        new i_TagValue = TAG_NONE;
        if (equali(sz_Tag, "VIP")) i_TagValue = TAG_VIP;
        else if (equali(sz_Tag, "ADMIN")) i_TagValue = TAG_ADMIN;
        else if (equali(sz_Tag, "GIRL")) i_TagValue = TAG_GIRL;

        if (i_TagValue != TAG_NONE) {
            TrieSetCell(g_tPlayerTags, sz_Name, i_TagValue);
        }
    }
    fclose(i_File);
}

public client_putinserver(id) {
    check_tag(id);
}

public client_infochanged(id) {
    if (!is_user_connected(id)) return;

    new sz_NewName[32], sz_OldName[32];
    get_user_name(id, sz_OldName, charsmax(sz_OldName));
    get_user_info(id, "name", sz_NewName, charsmax(sz_NewName));

    if (!equal(sz_NewName, sz_OldName)) {
        set_task(0.1, "check_tag", id);
    }
}

public check_tag(id) {
    if (!is_user_connected(id)) return;

    new sz_Name[32];
    get_user_name(id, sz_Name, charsmax(sz_Name));

    g_iPlayerTag[id] = TAG_NONE;
    
    if (TrieKeyExists(g_tPlayerTags, sz_Name)) {
        TrieGetCell(g_tPlayerTags, sz_Name, g_iPlayerTag[id]);
    }

    // Apply or reset model immediately if the player is alive during name change
    if (is_user_alive(id)) {
        if (g_iPlayerTag[id] != TAG_NONE) {
            apply_custom_model(id);
        } else {
            rg_reset_user_model(id); // ReAPI native to restore default CS model
        }
    }
}

public OnPlayerSpawn(id) {
    if (!is_user_alive(id)) {
        return;
    }

    // If they don't have a tag, ensure any previous custom model is removed
    if (g_iPlayerTag[id] == TAG_NONE) {
        rg_reset_user_model(id);
        return;
    }

    apply_custom_model(id);
}

apply_custom_model(id) {
    new TeamName:i_Team = get_member(id, m_iTeam);
    new sz_FinalModel[32];

    // Logic: If Tero -> T_TAG, If CT -> CT_TAG
    if (i_Team == TEAM_TERRORIST) {
        formatex(sz_FinalModel, charsmax(sz_FinalModel), "T_%s", sz_ModelNames[g_iPlayerTag[id]]);
    } 
    else if (i_Team == TEAM_CT) {
        formatex(sz_FinalModel, charsmax(sz_FinalModel), "CT_%s", sz_ModelNames[g_iPlayerTag[id]]);
    }
    else {
        return; // Spectators don't get models
    }

    rg_set_user_model(id, sz_FinalModel);
}
