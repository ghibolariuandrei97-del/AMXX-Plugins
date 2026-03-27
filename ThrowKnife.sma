#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <hamsandwich>

#define PLUGIN  "Thunder Bouncing Knife"
#define VERSION "7.1"
#define AUTHOR  "Gemini"

#define KNIFE_V_MODEL "models/v_knife.mdl"
#define KNIFE_W_MODEL "models/w_knife.mdl"
#define THUNDER_SOUND "ambience/thunder_close.wav"
#define KNIFE_CLASSNAME "knife_thrown"

#define TASK_HUD 1000

// Offsets
#define m_pPlayer 41
#define linux_diff_weapon 4

new pcvar_speed, pcvar_life, pcvar_count;
new Float:g_flCooldown[33]; 
new g_iKnivesLeft[33];
new g_iHudTimer[33]; 
new g_iBeamSpr, g_iLightningSpr;

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);
    
    pcvar_speed    = register_cvar("amx_knife_speed", "1200.0");
    pcvar_life     = register_cvar("amx_knife_life", "5.0"); // Cooldown will be 5s
    pcvar_count    = register_cvar("amx_knife_count", "10");
    
    register_clcmd("drop", "clcmd_drop");
    
    RegisterHam(Ham_Spawn, "player", "Ham_PlayerSpawn_Post", 1);
    RegisterHam(Ham_Killed, "player", "Ham_PlayerKilled_Pre");
    
    RegisterHam(Ham_Weapon_PrimaryAttack, "weapon_knife", "Ham_Knife_Attack_Pre");
    RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_knife", "Ham_Knife_Attack_Pre");
    RegisterHam(Ham_Item_Deploy, "weapon_knife", "Ham_Knife_Deploy_Post", 1);
    
    register_touch(KNIFE_CLASSNAME, "*", "knife_touch");
    register_event("HLTV", "event_round_start", "a", "1=0", "2=0");
}

public plugin_precache()
{
    precache_model(KNIFE_V_MODEL);
    precache_model(KNIFE_W_MODEL);
    g_iBeamSpr = precache_model("sprites/smoke.spr");
    g_iLightningSpr = precache_model("sprites/lgtning.spr");
    precache_sound(THUNDER_SOUND);
}

public event_round_start()
{
    new iMax = get_maxplayers();
    for(new i = 1; i <= iMax; i++)
    {
        g_iKnivesLeft[i] = get_pcvar_num(pcvar_count);
    }
}

public Ham_PlayerSpawn_Post(id)
{
    if (is_user_alive(id)) 
    {
        g_flCooldown[id] = 0.0;
        remove_task(id + TASK_HUD);
    }
}

public Ham_PlayerKilled_Pre(id)
{
    remove_task(id + TASK_HUD); // Stop timer if player dies
}

public Ham_Knife_Attack_Pre(iWeapon)
{
    new id = get_pdata_cbase(iWeapon, m_pPlayer, linux_diff_weapon);
    if (id >= 1 && id <= 32 && g_flCooldown[id] > get_gametime()) return HAM_SUPERCEDE;
    return HAM_IGNORED;
}

public Ham_Knife_Deploy_Post(iWeapon)
{
    new id = get_pdata_cbase(iWeapon, m_pPlayer, linux_diff_weapon);
    if (g_flCooldown[id] > get_gametime()) set_pev(id, pev_viewmodel2, "");
    else set_pev(id, pev_viewmodel2, KNIFE_V_MODEL);
}

public clcmd_drop(id)
{
    if (!is_user_alive(id) || get_user_weapon(id) != CSW_KNIFE) return PLUGIN_CONTINUE;
    
    new Float:flTime = get_gametime();
    
    // Check Round Count
    if (g_iKnivesLeft[id] <= 0)
    {
        client_print(id, print_chat, "[Knife] No knives remaining for this round.");
        return PLUGIN_HANDLED;
    }

    // Check Cooldown
    if (g_flCooldown[id] > flTime) return PLUGIN_HANDLED;
    
    throw_knife(id);
    g_iKnivesLeft[id]--;
    
    // COOLDOWN = LIFE
    new Float:flLife = get_pcvar_float(pcvar_life);
    g_flCooldown[id] = flTime + flLife;
    
    // Hide the knife model
    set_pev(id, pev_viewmodel2, "");
    
    // Sync HUD timer to the life CVAR
    g_iHudTimer[id] = floatround(flLife); 
    
    remove_task(id + TASK_HUD);
    // Task runs exactly g_iHudTimer[id] times
    set_task(1.0, "update_hud_timer", id + TASK_HUD, _, _, "a", g_iHudTimer[id]);
    
    return PLUGIN_HANDLED;
}

public update_hud_timer(taskid)
{
    new id = taskid - TASK_HUD;
    if (!is_user_alive(id)) return;

    g_iHudTimer[id]--;

    if (g_iHudTimer[id] <= 0)
    {
        set_pev(id, pev_viewmodel2, KNIFE_V_MODEL);
        client_print(id, print_chat, "[Knife] Returned! Throws left: %d", g_iKnivesLeft[id]);
    }
    else
    {
        // Displaying the LIVE countdown
        set_hudmessage(0, 255, 255, -1.0, 0.25, 0, 0.0, 1.1, 0.0, 0.0, -1);
        show_hudmessage(id, "RECHARGING...^n%d seconds left^n[Knives: %d]", g_iHudTimer[id], g_iKnivesLeft[id]);
    }
}

public throw_knife(id)
{
    new Float:vOrigin[3], Float:vAngle[3], Float:vForward[3], Float:vVelocity[3], Float:vViewOfs[3];
    pev(id, pev_origin, vOrigin);
    pev(id, pev_view_ofs, vViewOfs);
    vOrigin[0] += vViewOfs[0]; vOrigin[1] += vViewOfs[1]; vOrigin[2] += vViewOfs[2];
    
    pev(id, pev_v_angle, vAngle);
    angle_vector(vAngle, ANGLEVECTOR_FORWARD, vForward);
    
    new iEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
    if (!pev_valid(iEnt)) return;
    
    set_pev(iEnt, pev_classname, KNIFE_CLASSNAME);
    engfunc(EngFunc_SetModel, iEnt, KNIFE_W_MODEL);
    
    new Float:vStart[3];
    vStart[0] = vOrigin[0] + (vForward[0] * 20.0);
    vStart[1] = vOrigin[1] + (vForward[1] * 20.0);
    vStart[2] = vOrigin[2] + (vForward[2] * 20.0);
    engfunc(EngFunc_SetOrigin, iEnt, vStart);
    
    set_pev(iEnt, pev_angles, vAngle);
    set_pev(iEnt, pev_movetype, MOVETYPE_BOUNCE); 
    set_pev(iEnt, pev_solid, SOLID_BBOX);
    set_pev(iEnt, pev_owner, id);
    set_pev(iEnt, pev_gravity, 0.0001); 
    
    new Float:flSpeed = get_pcvar_float(pcvar_speed);
    vVelocity[0] = vForward[0] * flSpeed;
    vVelocity[1] = vForward[1] * flSpeed;
    vVelocity[2] = vForward[2] * flSpeed;
    set_pev(iEnt, pev_velocity, vVelocity);
    
    new iTeam = get_user_team(id);
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMFOLLOW);
    write_short(iEnt);
    write_short(g_iBeamSpr);
    write_byte(6); write_byte(3); 
    if (iTeam == 1) { write_byte(255); write_byte(0); write_byte(0); }
    else { write_byte(0); write_byte(100); write_byte(255); }
    write_byte(180); 
    message_end();
    
    set_pev(iEnt, pev_nextthink, get_gametime() + get_pcvar_float(pcvar_life));
}

public knife_touch(iEnt, iToucher)
{
    if (!pev_valid(iEnt)) return;
    if (is_user_alive(iToucher))
    {
        new iOwner = pev(iEnt, pev_owner);
        if (iToucher != iOwner)
        {
            ExecuteHamB(Ham_TakeDamage, iToucher, iEnt, iOwner, 2000.0, DMG_BULLET);
            create_thunder(iToucher);
        }
    }
    new Float:vVel[3], Float:vAng[3];
    pev(iEnt, pev_velocity, vVel);
    vector_to_angle(vVel, vAng);
    set_pev(iEnt, pev_angles, vAng);
}

public pfn_think(iEnt)
{
    if (!pev_valid(iEnt)) return;
    static szClass[32];
    pev(iEnt, pev_classname, szClass, charsmax(szClass));
    if (equal(szClass, KNIFE_CLASSNAME)) engfunc(EngFunc_RemoveEntity, iEnt);
}

public create_thunder(iTarget)
{
    new Float:vOrigin[3], Float:vTop[3];
    pev(iTarget, pev_origin, vOrigin);
    vTop[0] = vOrigin[0]; vTop[1] = vOrigin[1]; vTop[2] = vOrigin[2] + 600.0;
    
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMPOINTS);
    engfunc(EngFunc_WriteCoord, vTop[0]); engfunc(EngFunc_WriteCoord, vTop[1]); engfunc(EngFunc_WriteCoord, vTop[2]);
    engfunc(EngFunc_WriteCoord, vOrigin[0]); engfunc(EngFunc_WriteCoord, vOrigin[1]); engfunc(EngFunc_WriteCoord, vOrigin[2]);
    write_short(g_iLightningSpr);
    write_byte(0); write_byte(15); write_byte(8); write_byte(50); write_byte(20);
    write_byte(255); write_byte(255); write_byte(255); write_byte(255); write_byte(20);
    message_end();
    
    emit_sound(iTarget, CHAN_BODY, THUNDER_SOUND, 1.0, ATTN_NORM, 0, PITCH_NORM);
}
