#include <amxmodx>
#include <reapi>
#include <fun>

#define Debug_On 0
#define Debug_File "addons/amxmodx/logs/capture_debug.log"

#define PLUGIN "AMXX Team Capture Mode"
#define VERSION "1.0"
#define AUTHOR "AI"

new g_szWinner[32]

#if Debug_On == 1
stock debug_logs(const fmt[], any:...)
{
    static message[256]
    vformat(message, charsmax(message), fmt, 2)

    static timedate[32]
    get_time("%m/%d/%Y - %H:%M:%S", timedate, charsmax(timedate))

    static final_msg[512]
    formatex(final_msg, charsmax(final_msg), "[%s] %s", timedate, message)

    write_file(Debug_File, final_msg, -1)
}

stock debug_init()
{
    if(file_exists(Debug_File))
        delete_file(Debug_File)

    write_file(Debug_File, "--- Debug Session Started ---", -1)
}
#else
#define debug_logs(%1)
#define debug_init()
#endif

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)

    debug_init()
    debug_logs("Plugin Initialized. Version %s", VERSION)

    RegisterHookChain(RG_CSGameRules_OnRoundFreezeEnd, "RG_RoundFreezeEnd_Post", true)
    RegisterHookChain(RG_CBasePlayer_Killed, "RG_PlayerKilled_Post", true)
    
    register_event("SendAudio", "Event_RoundEnd_T", "a", "2=%!MRAD_terwin")
    register_event("SendAudio", "Event_RoundEnd_CT", "a", "2=%!MRAD_ctwin")
    register_event("SendAudio", "Event_RoundEnd_Draw", "a", "2=%!MRAD_draw")

    set_cvar_num("mp_autoteambalance", 0)
    set_cvar_num("mp_limitteams", 0)
    
    set_task(1.0, "remove_objectives")
}

public remove_objectives()
{
    static const ent_list[][] = { "func_bomb_target", "info_bomb_target", "hostage_entity", "func_hostage_rescue", "info_hostage_rescue", "func_buyzone" }
    for(new i = 0; i < sizeof(ent_list); i++) {
        new ent = -1; while((ent = rg_find_ent_by_class(ent, ent_list[i])) > 0) {
            rg_remove_entity(ent)
            debug_logs("Entity Removed: %s", ent_list[i])
        }
    }
}

public Event_RoundEnd_T() { debug_logs("T Win Event"); copy(g_szWinner, charsmax(g_szWinner), "TERRORISTS"); set_task(0.5, "DelayedVictoryLogic"); }
public Event_RoundEnd_CT() { debug_logs("CT Win Event"); copy(g_szWinner, charsmax(g_szWinner), "COUNTER-TERRORISTS"); set_task(0.5, "DelayedVictoryLogic"); }
public Event_RoundEnd_Draw() { debug_logs("Draw Event"); copy(g_szWinner, charsmax(g_szWinner), "NO ONE (DRAW)"); set_task(0.5, "DelayedVictoryLogic"); }

public DelayedVictoryLogic()
{
    debug_logs("Executing Victory Shuffle for Winner: %s", g_szWinner)
    
    set_hudmessage(200, 100, 0, -1.0, 0.3, 0, 0.0, 5.0, 0.1, 0.1, -1)
    show_hudmessage(0, "ROUND OVER^n%s WIN THE BATTLE!", g_szWinner)

    static players[32]; new num
    get_players(players, num, "h")
    
    for(new i = 0; i < num; i++)
    {
        new id = players[i]
        if(!is_user_connected(id)) continue

        new TeamName:assignedTeam = (i % 2 == 0) ? TEAM_CT : TEAM_TERRORIST
        
        debug_logs("Shuffling %n to Team %d", id, assignedTeam)
        rg_set_user_team(id, assignedTeam)

        set_user_godmode(id, 1)

        if(assignedTeam == TEAM_CT)
            set_user_rendering(id, kRenderFxGlowShell, 0, 0, 255, kRenderNormal, 16)
        else
            set_user_rendering(id, kRenderFxGlowShell, 255, 0, 0, kRenderNormal, 16)
    }
}

public RG_RoundFreezeEnd_Post()
{
    debug_logs("Round Start: Stripping protection/glow")
    
    set_member_game(m_iRoundTime, 999999)
    set_cvar_num("mp_buy_anywhere", 1)
    set_cvar_num("mp_buytime", 9999)
    
    static players[32]; new num
    get_players(players, num, "h")
    
    for(new i = 0; i < num; i++)
    {
        new id = players[i]
        if(!is_user_connected(id)) continue
        
        set_user_godmode(id, 0)
        set_user_rendering(id, kRenderFxNone, 0, 0, 0, kRenderNormal, 0)

        if(!is_user_alive(id)) rg_round_respawn(id)
    }
}

public RG_PlayerKilled_Post(const victim, const killer, const gib)
{
    if(!is_user_connected(victim) || !is_user_connected(killer)) return
    if(killer == victim) return

    new TeamName:killerTeam = get_member(killer, m_iTeam)
    debug_logs("Capture: %n -> %n (Team %d)", victim, killer, killerTeam)

    rg_set_user_team(victim, killerTeam)
    client_print(victim, print_center, "Captured! Joining enemy team...")

    set_task(0.5, "do_respawn_task", victim)
}

public do_respawn_task(id)
{
    if(is_user_connected(id)) {
        debug_logs("Respawning captured player %n", id)
        rg_round_respawn(id)
    }
}
