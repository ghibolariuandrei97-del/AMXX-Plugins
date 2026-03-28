#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <xs>
#include <fun>
#include <cstrike>

#define PLUGIN "Advanced Bomb"
#define VERSION "1.0"
#define AUTHOR "AI"

new Float:gBombOrigin[3]
new bool:gBombPlanted
new gSpriteBeam, gSpriteRing
new gBombCarrier

new Float:gLastDistance[33]
new gBombTicks

new pCvarMode, pCvarTimer, pCvarBuffDist, pCvarRegen

public plugin_precache()
{
    gSpriteBeam = precache_model("sprites/laserbeam.spr")
    gSpriteRing = precache_model("sprites/shockwave.spr")
    precache_sound("buttons/blip1.wav")
}

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)

    pCvarMode = register_cvar("amx_bombgps_mode", "3") 
    pCvarTimer = get_cvar_pointer("mp_c4timer")
    pCvarBuffDist = register_cvar("amx_bomb_defender_dist", "450.0")
    pCvarRegen = register_cvar("amx_bomb_regen_amt", "3.0")

    register_event("HLTV", "event_round_start", "a", "1=0", "2=0")
    register_event("CurWeapon", "event_cur_weapon", "be", "1=1")
    register_clcmd("drop", "clcmd_drop")
    
    set_task(0.5, "gps_update", _, _, _, "b")
}

public client_disconnected(id)
{
    if(id == gBombCarrier && !gBombPlanted)
    {
        gBombCarrier = 0
        set_task(1.0, "check_bomb_carrier")
    }
}

public clcmd_drop(id)
{
    if(id == gBombCarrier && !gBombPlanted)
    {
        client_print(id, print_center, "NU POTI ARUNCA BOMBA!")
        return PLUGIN_HANDLED
    }
    return PLUGIN_CONTINUE
}

public event_round_start()
{
    gBombPlanted = false
    gBombTicks = 0
    gBombCarrier = 0
    arrayset(_:gLastDistance, 0, sizeof gLastDistance)
    
    set_task(1.0, "check_bomb_carrier")
    reset_glow()
}

public check_bomb_carrier()
{
    if(gBombPlanted) return

    new players[32], num, id
    get_players(players, num, "ae", "TERRORIST")
    if(num == 0) return

    for(new i = 0; i < num; i++)
    {
        id = players[i]
        if(user_has_weapon(id, CSW_C4))
        {
            setup_carrier(id)
            return
        }
    }
    
    new new_carrier = players[0]
    give_item(new_carrier, "weapon_c4")
    setup_carrier(new_carrier)
}

public setup_carrier(id)
{
    gBombCarrier = id
    
    if(user_has_weapon(id, CSW_GLOCK18)) ham_strip_weapon(id, "weapon_glock18")
    if(user_has_weapon(id, CSW_USP)) ham_strip_weapon(id, "weapon_usp")
    
    engclient_cmd(id, "weapon_c4")
    
    set_hudmessage(200, 100, 0, -1.0, 0.3, 1, 0.0, 5.0, 0.1, 0.2, 3)
    show_hudmessage(id, "ESTI PURTATORUL BOMBEI!^nProtejeaza C4 si planteaza!")
}

public event_cur_weapon(id)
{
    if(id == gBombCarrier && !gBombPlanted)
    {
        new weapon = read_data(2)
        if(weapon != CSW_C4 && weapon != CSW_KNIFE)
        {
            engclient_cmd(id, "weapon_c4")
        }
    }
}

public gps_update()
{
    if(!gBombPlanted)
    {
        new ent = find_ent_by_model(-1, "grenade", "models/w_c4.mdl")
        if(pev_valid(ent))
        {
            new movetype = pev(ent, pev_movetype)
            if(movetype == MOVETYPE_TOSS || movetype == MOVETYPE_NONE)
            {
                pev(ent, pev_origin, gBombOrigin)
                gBombPlanted = true
                gBombTicks = 0
                
                teleport_all_terrorists()
            }
        }
        return
    }

    gBombTicks++
    
    new ent_check = find_ent_by_model(-1, "grenade", "models/w_c4.mdl")
    if(!pev_valid(ent_check))
    {
        gBombPlanted = false
        reset_glow()
        return
    }

    new Float:maxTime = get_pcvar_float(pCvarTimer)
    new Float:remaining = maxTime - (float(gBombTicks) * 0.5)
    if(remaining < 0.0) remaining = 0.0

    new r, g, b
    if(remaining > 20.0) { r = 0; g = 255; b = 0; }
    else if(remaining > 10.0) { r = 255; g = 255; b = 0; }
    else { r = 255; g = 0; b = 0; }

    if(gBombTicks % 2 == 0) draw_effects(r, g, b, (remaining <= 10.0))

    for(new id = 1; id <= get_maxplayers(); id++)
    {
        if(!is_user_alive(id)) continue

        new team = get_user_team(id)
        new Float:origin[3]
        pev(id, pev_origin, origin)
        new Float:distance = get_distance_f(origin, gBombOrigin)

        if(team == 1 && distance <= get_pcvar_float(pCvarBuffDist))
        {
            new iWpn = get_user_weapon(id)
            if(iWpn != CSW_KNIFE && iWpn != CSW_C4) give_user_weapon(id, iWpn, 30, 90) 
            
            new Float:hp; pev(id, pev_health, hp)
            if(hp < 150.0) set_user_health(id, floatround(hp + get_pcvar_float(pCvarRegen)))
            set_user_rendering(id, kRenderFxGlowShell, r, g, b, kRenderNormal, 15)
        }
        else if(team == 1) set_user_rendering(id)

        new mode = get_pcvar_num(pCvarMode)
        if(mode == 3 || (mode == 1 && team == 1) || (mode == 2 && team == 2))
        {
            new Float:v_angle[3]; pev(id, pev_v_angle, v_angle)
            new Float:angle_to_bomb = get_relative_angle(origin, v_angle, gBombOrigin)
            new arrow[12]; get_arrow_direction(angle_to_bomb, arrow, 11)

            set_hudmessage(r, g, b, 0.02, 0.75, 0, 0.0, 0.6, 0.0, 0.0, 1)
            show_hudmessage(id, "C4: %.0f u^nDirectie: %s^nTimp: %.1fs", distance, arrow, remaining)
        }
    }
}

public draw_effects(r, g, b, bool:fast)
{
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
    write_byte(TE_BEAMPOINTS)
    engfunc(EngFunc_WriteCoord, gBombOrigin[0]); engfunc(EngFunc_WriteCoord, gBombOrigin[1]); engfunc(EngFunc_WriteCoord, gBombOrigin[2] + 800.0)
    engfunc(EngFunc_WriteCoord, gBombOrigin[0]); engfunc(EngFunc_WriteCoord, gBombOrigin[1]); engfunc(EngFunc_WriteCoord, gBombOrigin[2])
    write_short(gSpriteBeam); write_byte(0); write_byte(0); write_byte(10); write_byte(fast ? 30 : 15); write_byte(0)
    write_byte(r); write_byte(g); write_byte(b); write_byte(150); write_byte(0)
    message_end()

    if(fast || gBombTicks % 4 == 0)
    {
        message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
        write_byte(TE_BEAMCYLINDER)
        engfunc(EngFunc_WriteCoord, gBombOrigin[0]); engfunc(EngFunc_WriteCoord, gBombOrigin[1]); engfunc(EngFunc_WriteCoord, gBombOrigin[2])
        engfunc(EngFunc_WriteCoord, gBombOrigin[0]); engfunc(EngFunc_WriteCoord, gBombOrigin[1]); engfunc(EngFunc_WriteCoord, gBombOrigin[2] + 200.0)
        write_short(gSpriteRing); write_byte(0); write_byte(1); write_byte(6); write_byte(10); write_byte(0)
        write_byte(r); write_byte(g); write_byte(b); write_byte(200); write_byte(0)
        message_end()
    }
}

public teleport_all_terrorists()
{
    new players[32], num, id
    get_players(players, num, "ae", "TERRORIST")
    if(num <= 1) return 
    
    new Float:targetPos[3], Float:angleStep = 360.0 / float(num), Float:currentAngle = 0.0
    for(new i = 0; i < num; i++)
    {
        id = players[i]
        if(id == gBombCarrier) continue
        
        targetPos[0] = gBombOrigin[0] + (140.0 * floatcos(currentAngle, degrees))
        targetPos[1] = gBombOrigin[1] + (140.0 * floatsin(currentAngle, degrees))
        targetPos[2] = gBombOrigin[2] + 30.0
        
        if(!is_hull_vacant(targetPos, id)) {
            targetPos[0] = gBombOrigin[0] + (70.0 * floatcos(currentAngle, degrees))
            targetPos[1] = gBombOrigin[1] + (70.0 * floatsin(currentAngle, degrees))
        }
        
        engfunc(EngFunc_SetOrigin, id, targetPos)
        engfunc(EngFunc_DropToFloor, id)
        currentAngle += angleStep
    }
}

stock ham_strip_weapon(id, weapon[])
{
    if(!is_user_alive(id)) return
    if(user_has_weapon(id, get_weaponid(weapon))) {
        engclient_cmd(id, "drop", weapon)
        new ent = find_ent_by_owner(-1, weapon, id)
        if(pev_valid(ent)) remove_entity(ent)
    }
}

stock bool:is_hull_vacant(Float:origin[3], id)
{
    engfunc(EngFunc_TraceHull, origin, origin, 0, HULL_HUMAN, id, 0)
    if (!get_tr2(0, TR_StartSolid) && !get_tr2(0, TR_AllSolid) && get_tr2(0, TR_InOpen))
        return true
    return false
}

stock give_user_weapon( index , iWeaponTypeID , iClip=0 , iBPAmmo=0 )
{
	if ( !( CSW_P228 <= iWeaponTypeID <= CSW_P90 ) || ( iClip < 0 ) || ( iBPAmmo < 0 ) || !is_user_alive( index ) )
		return -1;
	
	new szWeaponName[ 20 ] , iWeaponEntity , bool:bIsGrenade;
	const GrenadeBits = ( ( 1 << CSW_HEGRENADE ) | ( 1 << CSW_FLASHBANG ) | ( 1 << CSW_SMOKEGRENADE ) | ( 1 << CSW_C4 ) );
	
	if ( ( bIsGrenade = bool:!!( GrenadeBits & ( 1 << iWeaponTypeID ) ) ) )
		iClip = clamp( iClip ? iClip : iBPAmmo , 1 );
	
	get_weaponname( iWeaponTypeID , szWeaponName , charsmax( szWeaponName ) );
	
	if ( ( iWeaponEntity = user_has_weapon( index , iWeaponTypeID ) ? find_ent_by_owner( -1 , szWeaponName , index ) : give_item( index , szWeaponName ) ) > 0 )
	{
		if ( iWeaponTypeID != CSW_KNIFE )
		{
			if ( iClip && !bIsGrenade )
				cs_set_weapon_ammo( iWeaponEntity , iClip );
		
			if ( iWeaponTypeID == CSW_C4 ) 
				cs_set_user_plant( index , 1 , 1 );
			else
				cs_set_user_bpammo( index , iWeaponTypeID , bIsGrenade ? iClip : iBPAmmo ); 
		}
	}
	return iWeaponEntity;
}

Float:get_relative_angle(Float:pOrigin[3], Float:pAngle[3], Float:tOrigin[3])
{
    new Float:dir[3]; xs_vec_sub(tOrigin, pOrigin, dir)
    new Float:rel_angle = floatatan2(dir[1], dir[0], degrees) - pAngle[1]
    while(rel_angle > 180.0) rel_angle -= 360.0
    while(rel_angle < -180.0) rel_angle += 360.0
    return rel_angle
}

get_arrow_direction(Float:angle, arrow[], len)
{
    if(angle >= -45.0 && angle < 45.0) copy(arrow, len, "FATA")
    else if(angle >= 45.0 && angle < 135.0) copy(arrow, len, "DREAPTA")
    else if(angle <= -45.0 && angle > -135.0) copy(arrow, len, "STANGA")
    else copy(arrow, len, "SPATE")
}

reset_glow()
{
    new iMax = get_maxplayers()
    for(new i = 1; i <= iMax; i++)
    {
        if(is_user_connected(i)) {
            set_user_rendering(i)
        }
    }
}
