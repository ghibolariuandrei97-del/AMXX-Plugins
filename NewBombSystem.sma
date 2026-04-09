#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <xs>
#include <fun>
#include <cstrike>
#include <hamsandwich>

#define PLUGIN "New Bomb System"
#define VERSION "1.0"
#define AUTHOR "AI"

#define TASK_BOMB_LOOP 888
#define TASK_TRANSFER 999
#define TASK_UNSTUCK_DELAY 111

new Float:gBombOrigin[3], bool:gBombPlanted, gSpriteBeam, gBombTicks
new Float:gCurrentZoneRadius
new pCvarMode, pCvarTimer, pCvarBuffDist, pCvarRegen, pCvarDarkMode
new pCvarMaxHP, pCvarTeleport, pCvarBlockDrop, pCvarBlockSwitch, pCvarRegenEnable, pCvarGlow
new pCvarZoneDamage, pCvarZoneEnable, pCvarZoneColored, pCvarPlantReward

public plugin_precache()
{
    gSpriteBeam = precache_model("sprites/laserbeam.spr")
}

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)

    pCvarMode        = register_cvar("bomb_gps_mode", "3")       
    pCvarTimer       = get_cvar_pointer("mp_c4timer")
    pCvarBuffDist    = register_cvar("bomb_buff_dist_m", "15.0") 
    pCvarRegen       = register_cvar("bomb_regen_hp", "5.0")     
    pCvarMaxHP       = register_cvar("bomb_max_hp", "150.0")     
    pCvarTeleport    = register_cvar("bomb_teleport_t", "1")     
    pCvarBlockDrop   = register_cvar("bomb_block_drop", "1")     
    pCvarBlockSwitch = register_cvar("bomb_block_switch", "1")   
    pCvarRegenEnable = register_cvar("bomb_regen_enable", "1")   
    pCvarGlow        = register_cvar("bomb_glow_effects", "1")   
    pCvarDarkMode    = register_cvar("bomb_dark_mode", "1")
    pCvarZoneDamage  = register_cvar("bomb_zone_damage", "8.0")
    pCvarZoneEnable  = register_cvar("bomb_zone_enable", "1")
    pCvarZoneColored = register_cvar("bomb_zone_colored", "1")
    pCvarPlantReward = register_cvar("bomb_plant_money", "2500")

    register_logevent("event_bomb_planted", 3, "2=Planted_The_Bomb")
    register_logevent("event_bomb_defused", 3, "2=Defused_The_Bomb")
    register_logevent("event_bomb_exploded", 6, "3=Target_Bombed")
    register_event("HLTV", "event_new_round", "a", "1=0", "2=0")
    register_event("CurWeapon", "event_cur_weapon", "be", "1=1")
    
    RegisterHam(Ham_Killed, "player", "fw_PlayerKilled", 1)
    register_clcmd("drop", "clcmd_drop")
}

public event_cur_weapon(id)
{
    if(!is_user_alive(id) || gBombPlanted || !get_pcvar_num(pCvarBlockSwitch)) return PLUGIN_CONTINUE

    if(user_has_weapon(id, CSW_C4) && read_data(2) != CSW_C4)
    {
        engclient_cmd(id, "weapon_c4")
        client_print(id, print_center, "NU POTI SCHIMBA ARMA! PLANTEAZA!")
    }
    return PLUGIN_CONTINUE
}

public clcmd_drop(id) 
{
    if(get_pcvar_num(pCvarBlockDrop) && user_has_weapon(id, CSW_C4)) 
    {
        client_print(id, print_center, "NU POTI ARUNCA BOMBA! ESTI ALESUL!")
        return PLUGIN_HANDLED
    }
    return PLUGIN_CONTINUE
}

public event_new_round()
{
    gBombPlanted = false
    remove_task(TASK_BOMB_LOOP)
    if(get_pcvar_num(pCvarDarkMode)) set_lights("m")
    reset_all_rendering()
}

public fw_PlayerKilled(victim, killer, shouldgib)
{
    if(user_has_weapon(victim, CSW_C4))
    {
        set_task(0.1, "transfer_bomb_logic", victim + TASK_TRANSFER)
    }
}

public transfer_bomb_logic(taskid)
{
    if(gBombPlanted) return
    
    new ent = -1
    while((ent = find_ent_by_class(ent, "weaponbox")))
    {
        if(find_ent_by_model(ent, "weapon_c4", "models/w_backpack.mdl"))
        {
            remove_entity(ent)
            break
        }
    }

    new players[32], num; get_players(players, num, "ae", "TERRORIST")
    if(num > 0)
    {
        new id = players[0]
        give_item(id, "weapon_c4")
        new name[32]; get_user_name(id, name, 31)
        client_print_color(0, print_team_red, "^4[C4]^1 Purtatorul a murit! ^3%s^1 a preluat bomba!", name)
    }
}

public event_bomb_planted()
{
    new id = get_loguser_index()
    new name[32]; get_user_name(id, name, 31)
    
    pev(id, pev_origin, gBombOrigin)
    gBombPlanted = true
    gBombTicks = 0
    gCurrentZoneRadius = 1800.0

    cs_set_user_money(id, cs_get_user_money(id) + get_pcvar_num(pCvarPlantReward))
    client_print_color(0, print_team_red, "^4[C4]^3 %s^1 a plantat. Zona este activa!", name)
    
    if(get_pcvar_num(pCvarDarkMode)) set_lights("d")
    set_task(0.5, "bomb_active_loop", TASK_BOMB_LOOP, _, _, "b")

    if(get_pcvar_num(pCvarTeleport))
    {
        new players[32], num; get_players(players, num, "ae", "TERRORIST")
        for(new i = 0; i < num; i++) set_task(0.1 * i, "process_unstuck", players[i] + TASK_UNSTUCK_DELAY)
    }
}

public bomb_active_loop()
{
    if(!gBombPlanted) return

    gBombTicks++
    new Float:c4timer = get_pcvar_float(pCvarTimer)
    new Float:remaining = c4timer - (float(gBombTicks) * 0.5)
    
    new r, g, b
    if(remaining > 20.0) { r = 0; g = 255; b = 0; }
    else if(remaining > 10.0) { r = 255; g = 255; b = 0; }
    else { r = 255; g = 0; b = 0; }

    // Calculam raza zonei
    gCurrentZoneRadius = 1800.0 * (remaining / c4timer)
    if(gCurrentZoneRadius < 150.0) gCurrentZoneRadius = 150.0

    // Randare vizuala (doar o data pe secunda pentru performanta)
    if(gBombTicks % 2 == 0) 
    {
        if(get_pcvar_num(pCvarZoneEnable) && get_pcvar_num(pCvarZoneColored))
            draw_zone_wall(floatround(gCurrentZoneRadius), r, g, b)
        
        if(get_pcvar_num(pCvarGlow))
            draw_ring(150, r, g, b)
    }
    
    if(get_pcvar_num(pCvarGlow)) draw_laser(r, g, b)

    // Loop jucatori optimizat
    new players[32], num, id; get_players(players, num, "a")
    for(new i = 0; i < num; i++)
    {
        id = players[i]
        new team = get_user_team(id)
        new Float:origin[3]; pev(id, pev_origin, origin)
        new Float:dist = get_distance_f(origin, gBombOrigin)

        // Damage & Buffs
        if(get_pcvar_num(pCvarZoneEnable) && dist > gCurrentZoneRadius && is_user_alive(id))
        {
            if(gBombTicks % 2 == 0) {
                new Float:hp; pev(id, pev_health, hp)
                if(hp <= get_pcvar_float(pCvarZoneDamage)) user_kill(id)
                else set_user_health(id, floatround(hp - get_pcvar_float(pCvarZoneDamage)))
                
                set_hudmessage(255, 0, 0, -1.0, 0.8, 0, 0.0, 0.8, 0.1, 0.1, 2)
                show_hudmessage(id, "!!! ESTI IN AFARA ZONEI !!!")
            }
        }
        else if(team == 1 && dist <= get_pcvar_float(pCvarBuffDist) * 40.0)
        {
            if(get_pcvar_num(pCvarRegenEnable) && (gBombTicks % 2 == 0))
            {
                new Float:hp; pev(id, pev_health, hp)
                new Float:max = get_pcvar_float(pCvarMaxHP)
                if(hp < max) set_user_health(id, floatround(floatmin(hp + get_pcvar_float(pCvarRegen), max)))
            }
            if(get_pcvar_num(pCvarGlow)) set_user_rendering(id, kRenderFxGlowShell, r, g, b, kRenderNormal, 15)
        }
        else set_user_rendering(id)

        // GPS (doar daca e activat)
        new mode = get_pcvar_num(pCvarMode)
        if(mode == 3 || (mode == team))
        {
            new Float:v_angle[3]; pev(id, pev_v_angle, v_angle)
            new Float:rel_angle = get_relative_angle(origin, v_angle, gBombOrigin)
            new arrow[12]; get_arrow_dir(rel_angle, arrow, 11)
            set_hudmessage(r, g, b, 0.02, 0.75, 0, 0.0, 0.6, 0.0, 0.0, 1)
            show_hudmessage(id, "C4: %.1f M | ZONA: %.1f M^nDIR: %s | TIMP: %.1fs", dist/40.0, gCurrentZoneRadius/40.0, arrow, remaining)
        }
    }
}

// --- Functii Vizuale ---
draw_zone_wall(radius, r, g, b)
{
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
    write_byte(TE_BEAMCYLINDER)
    engfunc(EngFunc_WriteCoord, gBombOrigin[0]); engfunc(EngFunc_WriteCoord, gBombOrigin[1]); engfunc(EngFunc_WriteCoord, gBombOrigin[2])
    engfunc(EngFunc_WriteCoord, gBombOrigin[0]); engfunc(EngFunc_WriteCoord, gBombOrigin[1]); engfunc(EngFunc_WriteCoord, gBombOrigin[2] + radius)
    write_short(gSpriteBeam); write_byte(0); write_byte(0); write_byte(10); write_byte(20); write_byte(0); write_byte(r); write_byte(g); write_byte(b); write_byte(120); write_byte(0)
    message_end()
}

draw_ring(radius, r, g, b)
{
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
    write_byte(TE_BEAMCYLINDER)
    engfunc(EngFunc_WriteCoord, gBombOrigin[0]); engfunc(EngFunc_WriteCoord, gBombOrigin[1]); engfunc(EngFunc_WriteCoord, gBombOrigin[2])
    engfunc(EngFunc_WriteCoord, gBombOrigin[0]); engfunc(EngFunc_WriteCoord, gBombOrigin[1]); engfunc(EngFunc_WriteCoord, gBombOrigin[2] + radius)
    write_short(gSpriteBeam); write_byte(0); write_byte(0); write_byte(10); write_byte(10); write_byte(0); write_byte(r); write_byte(g); write_byte(b); write_byte(100); write_byte(0)
    message_end()
}

draw_laser(r, g, b)
{
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
    write_byte(TE_BEAMPOINTS)
    engfunc(EngFunc_WriteCoord, gBombOrigin[0]); engfunc(EngFunc_WriteCoord, gBombOrigin[1]); engfunc(EngFunc_WriteCoord, gBombOrigin[2] + 1000.0)
    engfunc(EngFunc_WriteCoord, gBombOrigin[0]); engfunc(EngFunc_WriteCoord, gBombOrigin[1]); engfunc(EngFunc_WriteCoord, gBombOrigin[2])
    write_short(gSpriteBeam); write_byte(0); write_byte(0); write_byte(5); write_byte(10); write_byte(0); write_byte(r); write_byte(g); write_byte(b); write_byte(150); write_byte(0)
    message_end()
}

// --- Helpers ---
public process_unstuck(taskid)
{
    new id = taskid - TASK_UNSTUCK_DELAY
    if(!is_user_alive(id)) return
    new Float:testPos[3]
    for(new Float:angle = 0.0; angle < 360.0; angle += 90.0) {
        testPos[0] = gBombOrigin[0] + (200.0 * floatcos(angle, degrees))
        testPos[1] = gBombOrigin[1] + (200.0 * floatsin(angle, degrees))
        testPos[2] = gBombOrigin[2] + 20.0
        if(is_place_safe(id, testPos)) {
            engfunc(EngFunc_SetOrigin, id, testPos)
            return
        }
    }
}

stock bool:is_place_safe(id, Float:origin[3])
{
    engfunc(EngFunc_TraceHull, origin, origin, 0, HULL_HUMAN, id, 0)
    return (!get_tr2(0, TR_StartSolid) && !get_tr2(0, TR_AllSolid))
}

stock get_loguser_index() 
{
    new loguser[80], name[32]
    read_logargv(0, loguser, 79); parse_loguser(loguser, name, 31)
    return get_user_index(name)
}

Float:get_relative_angle(Float:pOrigin[3], Float:pAngle[3], Float:tOrigin[3])
{
    new Float:dir[3]; xs_vec_sub(tOrigin, pOrigin, dir)
    new Float:rel = floatatan2(dir[1], dir[0], degrees) - pAngle[1]
    while(rel > 180.0) rel -= 360.0; while(rel < -180.0) rel += 360.0
    return rel
}

get_arrow_dir(Float:angle, arrow[], len)
{
    if(angle >= -45.0 && angle < 45.0) copy(arrow, len, "FATA")
    else if(angle >= 45.0 && angle < 135.0) copy(arrow, len, "DREAPTA")
    else if(angle <= -45.0 && angle > -135.0) copy(arrow, len, "STANGA")
    else copy(arrow, len, "SPATE")
}

public event_bomb_defused() { gBombPlanted = false; }
public event_bomb_exploded() { gBombPlanted = false; }
reset_all_rendering() { new players[32], num; get_players(players, num); for(new i = 0; i < num; i++) set_user_rendering(players[i]); }
