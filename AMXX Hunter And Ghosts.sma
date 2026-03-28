#include <amxmodx>
#include <cstrike>
#include <fun>
#include <reapi>
#include <fakemeta>
#include <xs>
#include <hamsandwich>
#include <engine>

#define PLUGIN  "Ghosts vs Hunters"
#define VERSION "1.0"
#define AUTHOR  "Improved & Craxor"

// --- Definitii Lasere ---
#define MAX_LASERS_PER_PLAYER   3
#define LASER_CLASSNAME         "gvh_laser"
#define LASER_TRACE_DIST        8192.0
#define LASER_PLACE_DIST        300.0
#define LASER_BEAM_WIDTH        10
#define LASER_ALPHA             210

#define LASER_T_R   255
#define LASER_T_G   30
#define LASER_T_B   30
#define LASER_CT_R  30
#define LASER_CT_G  80
#define LASER_CT_B  255

// --- Setari Vizibilitate si Ceata ---
#define FADE_SPEED        20.0
#define GHOST_MIN_ALPHA    0.0
#define GHOST_MAX_ALPHA  240.0
#define FLASHLIGHT_DIST   300.0
#define FLASHLIGHT_ALPHA   80.0

#define FOG_COLOR_R 100
#define FOG_COLOR_G 100
#define FOG_COLOR_B 115
#define FOG_DENSITY 0.0015 

new g_sModelIndexBeam, g_cvGhostSpeed, g_cvLaserLifetime, Float:g_fGhostSpeed;
new g_iPlantsLeft[MAX_PLAYERS + 1], Float:g_fCurrentAlpha[MAX_PLAYERS + 1];
new g_iHudSync, g_msgFog;

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    
    server_cmd("sv_maxspeed 5000");
    
    // Hook-uri ReAPI
    RegisterHookChain(RG_CBasePlayer_Spawn, "fw_PlayerSpawn_Post", true);
    RegisterHookChain(RG_CBasePlayer_ResetMaxSpeed, "fw_ResetMaxSpeed_Post", true);
    RegisterHookChain(RG_CSGameRules_RestartRound, "fw_RoundRestart_Post", true);
    RegisterHookChain(RG_CBasePlayer_AddPlayerItem, "fw_AddPlayerItem_Pre", false);
    
    // Hook-uri Engine pentru blocare pickup (Metoda ta)
    register_touch("weaponbox", "player", "fw_TouchWeapon");
    register_touch("armoury_entity", "player", "fw_TouchWeapon");
    
    register_forward(FM_Think, "fw_Think");
    register_clcmd("+plant", "Cmd_PlantLaser");
    
    // Blocare comenzi cumparare
    register_clcmd("buy", "block_cmd");
    register_clcmd("buyequip", "block_cmd");
    register_clcmd("cl_autobuy", "block_cmd");
    
    g_cvGhostSpeed = register_cvar("gvh_ghost_speed", "900.0");
    g_cvLaserLifetime = register_cvar("gvh_laser_lifetime", "60.0");
    
    g_iHudSync = CreateHudSyncObj();
    g_msgFog = get_user_msgid("Fog");
    
    set_task(0.1, "task_GhostLogic", .flags = "b");
}

public plugin_precache() {
    g_sModelIndexBeam = precache_model("sprites/laserbeam.spr");
    precache_sound("weapons/mine_activate.wav");
    
    // Dezactivare BuyZone (Metoda ta)
    new Entity = create_entity("info_map_parameters");
    DispatchKeyValue(Entity, "buying", "3");
    DispatchSpawn(Entity);
}

// Blocare Pickup pentru TERO (Metoda ta)
public fw_TouchWeapon(ent, id) {
    if(!is_user_alive(id) || !pev_valid(ent))
        return PLUGIN_CONTINUE;

    if(get_member(id, m_iTeam) == TEAM_TERRORIST)
        return PLUGIN_HANDLED; // Fantomele nu pot lua arme

    return PLUGIN_CONTINUE;
}

public block_cmd(id) return PLUGIN_HANDLED;

public fw_AddPlayerItem_Pre(id, iItem) {
    if (get_member(iItem, m_iId) == WEAPON_C4) {
        set_entvar(iItem, var_flags, FL_KILLME);
        SetHookChainReturn(ATYPE_INTEGER, 0);
        return HC_SUPERCEDE;
    }
    return HC_CONTINUE;
}

public fw_RoundRestart_Post() {
    new ent = -1;
    while ((ent = rg_find_ent_by_class(ent, LASER_CLASSNAME)) > 0) rg_remove_entity(ent);
    g_fGhostSpeed = get_pcvar_float(g_cvGhostSpeed);
    set_task(0.5, "ApplyFogToAll");
}

public ApplyFogToAll() {
    for (new i = 1; i <= MaxClients; i++) {
        if (is_user_connected(i)) SendFog(i);
    }
}

public SendFog(id) {
    message_begin(MSG_ONE_UNRELIABLE, g_msgFog, {0,0,0}, id);
    write_byte(FOG_COLOR_R);
    write_byte(FOG_COLOR_G);
    write_byte(FOG_COLOR_B);
    new Float:fDensity = FOG_DENSITY;
    write_long(_:fDensity); 
    message_end();
}

public fw_PlayerSpawn_Post(id) {
    if (!is_user_alive(id)) return;
    
    g_iPlantsLeft[id] = MAX_LASERS_PER_PLAYER;
    SendFog(id);
    
    rg_remove_all_items(id); // Curatam tot la spawn
    
    if (get_member(id, m_iTeam) == TEAM_TERRORIST) {
        set_entvar(id, var_movetype, MOVETYPE_NOCLIP);
        give_item(id, "weapon_knife");
        
        set_entvar(id, var_rendermode, kRenderTransAlpha);
        set_entvar(id, var_renderamt, 0.0);
        g_fCurrentAlpha[id] = 0.0;
    } else {
        set_entvar(id, var_movetype, MOVETYPE_WALK);
        set_entvar(id, var_rendermode, kRenderNormal);
        
        // Echipare CT: M4A1, Deagle, HE
        give_item(id, "weapon_knife");
	give_user_weapon( id, CSW_M4A1, 30, 200 );
	give_user_weapon( id, CSW_AK47, 30, 200 );
        give_user_weapon( id, CSW_DEAGLE, 7, 100 );
    }
    set_entvar(id, var_maxspeed, 1.0);
}

public fw_ResetMaxSpeed_Post(id) {
    if (is_user_alive(id) && get_member(id, m_iTeam) == TEAM_TERRORIST) {
        set_entvar(id, var_maxspeed, g_fGhostSpeed);
    }
}

public task_GhostLogic() {
    new players[32], num, id, i, j, cts[32], ct_num;
    get_players(cts, ct_num, "ae", "CT");
    get_players(players, num, "ae", "TERRORIST");
    
    for(i = 0; i < num; i++) {
        id = players[i];
        new iButtons = pev(id, pev_button);
        new bool:bMoving = bool:(iButtons & (IN_FORWARD|IN_BACK|IN_MOVELEFT|IN_MOVERIGHT|IN_JUMP|IN_DUCK));
        new bool:bLit = false;
        
        if (!bMoving) {
            new Float:vG[3]; pev(id, pev_origin, vG);
            for(j = 0; j < ct_num; j++) {
                if (pev(cts[j], pev_effects) & EF_DIMLIGHT) {
                    new Float:vH[3]; pev(cts[j], pev_origin, vH);
                    if (xs_vec_distance(vG, vH) <= FLASHLIGHT_DIST) { bLit = true; break; }
                }
            }
        }

        new Float:fT = bMoving ? GHOST_MAX_ALPHA : (bLit ? FLASHLIGHT_ALPHA : GHOST_MIN_ALPHA);
        if (g_fCurrentAlpha[id] != fT) {
            if (g_fCurrentAlpha[id] < fT) g_fCurrentAlpha[id] = floatmin(fT, g_fCurrentAlpha[id] + FADE_SPEED);
            else g_fCurrentAlpha[id] = floatmax(fT, g_fCurrentAlpha[id] - FADE_SPEED);
            set_entvar(id, var_renderamt, g_fCurrentAlpha[id]);
        }
        ShowPlayerHUD(id);
    }
}

public Cmd_PlantLaser(id) {
    if (!is_user_alive(id) || g_iPlantsLeft[id] <= 0) return PLUGIN_HANDLED;
    
    new TeamName:iT = get_member(id, m_iTeam);
    new Float:vE[3], Float:vA[3], Float:vF[3], Float:vEnd[3], Float:vO[3], Float:vOfs[3];
    
    pev(id, pev_origin, vO); pev(id, pev_view_ofs, vOfs); xs_vec_add(vO, vOfs, vE);
    pev(id, pev_v_angle, vA); angle_vector(vA, ANGLEVECTOR_FORWARD, vF);
    xs_vec_mul_scalar(vF, LASER_PLACE_DIST, vEnd); xs_vec_add(vE, vEnd, vEnd);
    
    new tr = create_tr2(); 
    engfunc(EngFunc_TraceLine, vE, vEnd, IGNORE_MONSTERS, id, tr);
    new Float:fF; get_tr2(tr, TR_flFraction, fF);
    if (fF >= 1.0) { free_tr2(tr); return PLUGIN_HANDLED; }
    
    new Float:vHP[3], Float:vN[3]; 
    get_tr2(tr, TR_vecEndPos, vHP); get_tr2(tr, TR_vecPlaneNormal, vN); 
    free_tr2(tr);
    
    new ent = rg_create_entity("info_target");
    if (is_nullent(ent)) return PLUGIN_HANDLED;

    set_entvar(ent, var_classname, LASER_CLASSNAME); 
    set_entvar(ent, var_owner, id); 
    set_entvar(ent, var_iuser1, _:iT);
    
    new Float:vS[3]; xs_vec_mul_scalar(vN, 2.0, vS); xs_vec_add(vHP, vS, vS); 
    set_entvar(ent, var_origin, vS);
    
    new Float:vBE[3], Float:vD[3]; 
    xs_vec_copy(vN, vD); xs_vec_mul_scalar(vD, LASER_TRACE_DIST, vD); xs_vec_add(vS, vD, vBE);
    
    new tr2 = create_tr2(); 
    engfunc(EngFunc_TraceLine, vS, vBE, IGNORE_MONSTERS, ent, tr2); 
    get_tr2(tr2, TR_vecEndPos, vBE); free_tr2(tr2);
    
    set_entvar(ent, var_vuser1, vBE); 
    set_entvar(ent, var_fuser1, 0.0);
    set_entvar(ent, var_fuser2, get_gametime() + get_pcvar_float(g_cvLaserLifetime));
    set_entvar(ent, var_nextthink, get_gametime() + 0.1); 
    
    g_iPlantsLeft[id]--;
    emit_sound(id, CHAN_WEAPON, "weapons/mine_activate.wav", 0.7, ATTN_NORM, 0, PITCH_NORM);
    return PLUGIN_HANDLED;
}

public fw_Think(ent) {
    if (is_nullent(ent)) return FMRES_IGNORED;
    static szClass[32]; get_entvar(ent, var_classname, szClass, 31);
    if (szClass[0] != 'g') return FMRES_IGNORED;

    new Float:fNow = get_gametime(), Float:vS[3], Float:vE[3], Float:fLV, Float:fEx;
    get_entvar(ent, var_origin, vS); get_entvar(ent, var_vuser1, vE); 
    get_entvar(ent, var_fuser1, fLV); get_entvar(ent, var_fuser2, fEx);
    
    if (fNow > fEx) { rg_remove_entity(ent); return FMRES_HANDLED; }
    
    new owner = get_entvar(ent, var_owner), iTO = get_entvar(ent, var_iuser1);
    new tr = create_tr2(); 
    engfunc(EngFunc_TraceLine, vS, vE, DONT_IGNORE_MONSTERS, ent, tr);
    new pH = get_tr2(tr, TR_pHit); free_tr2(tr);
    
    if (is_user_alive(pH) && iTO != _:get_member(pH, m_iTeam)) {
        ExecuteHamB(Ham_Killed, pH, is_user_connected(owner) ? owner : 0, 2);
    }
    
    if (fNow > fLV) {
        new r, g, b; 
        if (iTO == _:TEAM_TERRORIST) { r=LASER_T_R; g=LASER_T_G; b=LASER_T_B; } 
        else { r=LASER_CT_R; g=LASER_CT_G; b=LASER_CT_B; }
        
        message_begin(MSG_BROADCAST, SVC_TEMPENTITY); 
        write_byte(TE_BEAMPOINTS);
        engfunc(EngFunc_WriteCoord, vS[0]); engfunc(EngFunc_WriteCoord, vS[1]); engfunc(EngFunc_WriteCoord, vS[2]);
        engfunc(EngFunc_WriteCoord, vE[0]); engfunc(EngFunc_WriteCoord, vE[1]); engfunc(EngFunc_WriteCoord, vE[2]);
        write_short(g_sModelIndexBeam); 
        write_byte(0); write_byte(0); write_byte(11); write_byte(LASER_BEAM_WIDTH);
        write_byte(0); write_byte(r); write_byte(g); write_byte(b); 
        write_byte(LASER_ALPHA); write_byte(0); 
        message_end();
        
        set_entvar(ent, var_fuser1, fNow + 0.8);
    }
    set_entvar(ent, var_nextthink, fNow + 0.1); 
    return FMRES_HANDLED;
}

public ShowPlayerHUD(id) {
    new TeamName:iT = get_member(id, m_iTeam);
    set_hudmessage(iT == TEAM_CT ? 255 : 100, 100, iT == TEAM_CT ? 100 : 255, -1.0, 0.85, 0, 0.0, 0.2, 0.0, 0.0, -1);
    ShowSyncHudMsg(id, g_iHudSync, "[%s] Lasers: %d / %d", (iT == TEAM_CT) ? "Hunter" : "Ghost", g_iPlantsLeft[id], MAX_LASERS_PER_PLAYER);
}

give_user_weapon( index , iWeaponTypeID , iClip=0 , iBPAmmo=0 , szWeapon[]="" , maxchars=0 )
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
		
		if ( maxchars )
			copy( szWeapon , maxchars , szWeaponName[7] );
	}
	
	return iWeaponEntity;
}
