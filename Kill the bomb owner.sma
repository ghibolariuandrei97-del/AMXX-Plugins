#include <amxmodx>
#include <engine>
#include <hamsandwich>
#include <fun>
#include <reapi>

new g_iBombOwner = 0;

public plugin_init() {
    register_plugin("Kill the BombOwner", "1.0", "AI");

    // Standard log event for planting
    register_logevent("Event_BombPlanted", 3, "2=Planted_The_Bomb");
    
    // Death hook
    RegisterHookChain(RG_CBasePlayer_Killed, "OnPlayerKilled_Post", 1);
    
    // Round start reset
    register_event("HLTV", "Event_NewRound", "a", "1=0", "2=0");

    // Block defuse attempt
    RegisterHam(Ham_Use, "grenade", "Ham_C4_Use_Pre", 0);
}

public Event_BombPlanted() {
    new loguser[80], name[32];
    read_logargv(0, loguser, charsmax(loguser));
    parse_loguser(loguser, name, charsmax(name));
    new id = get_user_index(name);

    if (is_user_connected(id)) {
        g_iBombOwner = id;
        
        // Red Glow (Using FUN module)
        set_user_rendering(id, kRenderFxGlowShell, 255, 0, 0, kRenderNormal, 25);

        client_print(0, print_center, "BOMB LINKED TO %n!^nKILL THEM TO DEFUSE!", id);
        client_print(0, print_chat, "* [Objective] Kill %n to deactivate the C4!", id);
    }
}

public Ham_C4_Use_Pre(const iEnt, const id) {
    if (g_iBombOwner == 0) return HAM_IGNORED;

    new model[64];
    entity_get_string(iEnt, EV_SZ_model, model, charsmax(model));
    
    // Check if it's the planted bomb model
    if (containi(model, "w_c4.mdl") != -1) {
        client_print(id, print_center, "DEFUSE BLOCKED!^nKill the Glowing Planter!");
        return HAM_SUPERCEDE;
    }
    return HAM_IGNORED;
}

public OnPlayerKilled_Post(const victim, const killer) {
    if (g_iBombOwner != 0 && victim == g_iBombOwner) {
        
        // Search for the planted bomb entity
        new iC4 = find_ent_by_model(-1, "grenade", "models/w_c4.mdl");
        
        if (is_valid_ent(iC4)) {
            // Using ReAPI round end with generic integers to avoid include errors
            // 3.0 = Delay, 3 = Round Win Condition (CTs Win)
            rg_round_end(3.0, WINSTATUS_CTS, ROUND_BOMB_DEFUSED, "Planter Neutralized!");
            
            // Remove the bomb entity so it stops beeping
            remove_entity(iC4);
            
            client_print(0, print_chat, "* Target %n eliminated! Bomb deactivated.", victim);
        }
        
        g_iBombOwner = 0;
    }
}

public Event_NewRound() {
    // Reset glow for the owner if they are still connected
    if (g_iBombOwner != 0 && is_user_connected(g_iBombOwner)) {
        set_user_rendering(g_iBombOwner, kRenderFxNone, 0, 0, 0, kRenderNormal, 0);
    }
    g_iBombOwner = 0;
}
