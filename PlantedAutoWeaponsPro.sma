/*================================================================================
 [ Planted Auto-Weapons Pro ]
 -------------------------------------------------------------------------------
  A high-performance, aesthetically crafted plugin for Counter-Strike 1.6.
  
  Architectural Philosophy:
  - No PreThink/PostThink (Optimized Task/Think/Update loops)
  - Full Hungarian Notation (sz_Var, i_Var, f_Var)
  - Logical "Poetry" Stanzas (Optimized for CPU Stability & Visual Beauty)
 =================================================================================*/

#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <hamsandwich>
#include <cstrike>
#include <fun> 
#include <xs>

/*================================================================================
 [ Constants & Static Mappings ]
=================================================================================*/

#define PLUGIN  "Planted Auto-Weapons Pro"
#define VERSION "1.0"
#define AUTHOR  "AI Studio"

#define CLASS_SENTRY "planted_weapon"
#define TASK_DEPLOY_VAL 4488

// Primary Weapons Selection Mask
#define MASK_PRIMARIES ((1<<CSW_SCOUT) | (1<<CSW_XM1014) | (1<<CSW_MAC10) | (1<<CSW_AUG) | (1<<CSW_UMP45) | (1<<CSW_SG550) | (1<<CSW_GALIL) | (1<<CSW_FAMAS) | (1<<CSW_AWP) | (1<<CSW_MP5NAVY) | (1<<CSW_M249) | (1<<CSW_M3) | (1<<CSW_M4A1) | (1<<CSW_TMP) | (1<<CSW_G3SG1) | (1<<CSW_SG552) | (1<<CSW_AK47) | (1<<CSW_P90))

// pev mappings
#define pev_u_wpnid   pev_iuser1  
#define pev_u_team    pev_iuser2  
#define pev_u_clip    pev_iuser3  
#define pev_u_ammo    pev_iuser4  
#define pev_u_rel     pev_impulse 
#define pev_u_hphud   pev_fuser1  // Master Integrity HP
#define pev_u_pulset  pev_fuser2  // Pulse Trace Timer
#define pev_u_basez   pev_fuser3  // Original Anchor Z
#define pev_u_searcht pev_fuser4  // Victim Search Timer (Throttling)
#define pev_u_target  pev_euser1  // Target Handle

new const sz_ModelTable[][] = {
	"", "models/w_p228.mdl", "", "models/w_scout.mdl", "models/w_hegrenade.mdl",
	"models/w_xm1014.mdl", "models/w_c4.mdl", "models/w_mac10.mdl", "models/w_aug.mdl",
	"models/w_smokegrenade.mdl", "models/w_elite.mdl", "models/w_fiveseven.mdl",
	"models/w_ump45.mdl", "models/w_sg550.mdl", "models/w_galil.mdl", "models/w_famas.mdl",
	"models/w_usp.mdl", "models/w_glock18.mdl", "models/w_awp.mdl", "models/w_mp5.mdl",
	"models/w_m249.mdl", "models/w_m3.mdl", "models/w_m4a1.mdl", "models/w_tmp.mdl",
	"models/w_g3sg1.mdl", "models/w_flashbang.mdl", "models/w_deagle.mdl", "models/w_sg552.mdl",
	"models/w_ak47.mdl", "models/w_knife.mdl", "models/w_p90.mdl"
};

new const Float:f_DamagePerWpn[] = {
	0.0, 22.0, 0.0, 75.0, 0.0, 20.0, 0.0, 29.0, 32.0, 0.0, 36.0, 20.0, 30.0, 40.0, 30.0, 30.0, 
	34.0, 25.0, 115.0, 26.0, 35.0, 22.0, 33.0, 20.0, 80.0, 0.0, 54.0, 33.0, 36.0, 0.0, 26.0
};

new const Float:f_DelayPerWpn[] = {
	0.0, 0.2, 0.0, 1.25, 0.0, 0.3, 0.0, 0.09, 0.13, 0.0, 0.2, 0.15, 0.1, 0.25, 0.12, 0.08, 
	0.15, 0.15, 1.45, 0.08, 0.1, 0.8, 0.09, 0.08, 0.25, 0.0, 0.2, 0.13, 0.1, 0.0, 0.07
};

/*================================================================================
 [ Global Variable Handles ]
=================================================================================*/

new iCvar_Range, iCvar_PlantTime, iCvar_Health;
new bool:g_isUserPlanting[33];
new Float:g_vStartOrigin[33][3];

new g_iAimerTarget[33]; 
new Float:g_fDamageCooldown[33];

new g_msgBarID, g_sBeam, g_sExp, g_hSync, g_sBlood, g_sFlower;

/*================================================================================
 [ Plugin Entry ]
=================================================================================*/

public plugin_init() {
	register_plugin(PLUGIN, VERSION, AUTHOR);

	iCvar_Range     = register_cvar("amx_plantwp_range", "600.0");
	iCvar_PlantTime = register_cvar("amx_plantwp_time", "3.0");
	iCvar_Health    = register_cvar("amx_plantwp_health", "100.0");

	register_clcmd("+plantwp", "Interaction_OnStarted");
	register_clcmd("-plantwp", "Interaction_OnStopped");

	register_think(CLASS_SENTRY, "Device_ProcessThink");
	register_touch(CLASS_SENTRY, "player", "Hook_DeviceTouch");
	register_logevent("RoundEnd_Cleanup", 2, "1=Round_End");
	register_event("HLTV", "RoundEnd_Cleanup", "a", "1=0", "2=0");
	
	RegisterHam(Ham_Player_UpdateClientData, "player", "Hook_StatusUpdate", 1);
	register_forward(FM_CmdStart, "Hook_CmdStart_ManualAttack");

	g_msgBarID = get_user_msgid("BarTime");
	g_hSync    = CreateHudSyncObj();
}

public plugin_precache() {
	new i;
	for(i = 1; i < sizeof(sz_ModelTable); i++) {
		if(sz_ModelTable[i][0]) precache_model(sz_ModelTable[i]);
	}
	
	precache_sound("weapons/m4a1-1.wav");
	precache_sound("weapons/boltcurl.wav"); 
	precache_sound("debris/metal1.wav");    
	precache_sound("buttons/bell1.wav");     
	precache_sound("buttons/blip1.wav");     
	
	g_sBeam   = precache_model("sprites/laserbeam.spr");
	g_sExp    = precache_model("sprites/zerogxplode.spr");
	g_sBlood  = precache_model("sprites/blood.spr");
	g_sFlower = precache_model("sprites/muzzleflash.spr");
}

/*================================================================================
 [ Interactive Logic Stanza ]
=================================================================================*/

public Interaction_OnStarted(id) {
	if(!is_user_alive(id)) return PLUGIN_HANDLED;

	new i_ActiveWpn = get_user_weapon(id);
	if(!(MASK_PRIMARIES & (1 << i_ActiveWpn))) {
		client_print(id, print_center, "Deployment Blocked: Primary Weapon Required!");
		return PLUGIN_HANDLED;
	}

	g_isUserPlanting[id] = true;
	pev(id, pev_origin, g_vStartOrigin[id]);

	UTIL_ApplyBar(id, get_pcvar_num(iCvar_PlantTime));
	set_task(get_pcvar_float(iCvar_PlantTime), "Task_ConcludePlanting", id + TASK_DEPLOY_VAL);

	return PLUGIN_HANDLED;
}

public Interaction_OnStopped(id) {
	if(g_isUserPlanting[id]) AbortInteraction(id);
	return PLUGIN_HANDLED;
}

public Hook_StatusUpdate(id) {
	if(!g_isUserPlanting[id]) return;
	
	static Float:v_CurrPos[3]; pev(id, pev_origin, v_CurrPos);
	if(get_distance_f(v_CurrPos, g_vStartOrigin[id]) > 15.0) {
		AbortInteraction(id);
	}
}

public Hook_DeviceTouch(i_Ent, id) {
	if(!pev_valid(i_Ent) || !is_user_alive(id)) return;
	
	if(get_user_team(id) == pev(i_Ent, pev_u_team)) {
		static Float:f_LT; f_LT = get_gametime();
		static Float:f_LastTouch[33];
		if(f_LT - f_LastTouch[id] >= 1.0) {
			emit_sound(i_Ent, CHAN_AUTO, "buttons/blip1.wav", 0.4, ATTN_NORM, 0, PITCH_NORM);
			f_LastTouch[id] = f_LT;
		}
	}
}

public Task_ConcludePlanting(tid) {
	new id = tid - TASK_DEPLOY_VAL;
	if(!is_user_alive(id) || !g_isUserPlanting[id]) return;

	new i_WpnID = get_user_weapon(id);
	if(!(MASK_PRIMARIES & (1 << i_WpnID))) return;

	new i_WpnIdx = get_pdata_cbase(id, 373);
	new i_Clip   = cs_get_weapon_ammo(i_WpnIdx);
	new i_Bpk    = cs_get_user_bpammo(id, i_WpnID);

	static Float:v_P_Ori[3], Float:v_G_Ori[3]; 
	pev(id, pev_origin, v_P_Ori);
	
	new i_Trace = create_tr2();
	engfunc(EngFunc_TraceLine, v_P_Ori, Float:{0.0, 0.0, -9999.0}, IGNORE_MONSTERS, id, i_Trace);
	get_tr2(i_Trace, TR_vecEndPos, v_G_Ori);
	free_tr2(i_Trace);

	new i_WeaponEntity = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
	if(!pev_valid(i_WeaponEntity)) return;

	set_pev(i_WeaponEntity, pev_classname, CLASS_SENTRY);
	engfunc(EngFunc_SetModel, i_WeaponEntity, sz_ModelTable[i_WpnID]);
	
	set_pev(i_WeaponEntity, pev_solid, SOLID_BBOX);
	set_pev(i_WeaponEntity, pev_movetype, MOVETYPE_FLY); 
	set_pev(i_WeaponEntity, pev_takedamage, DAMAGE_AIM); 
	
	new Float:f_HPInit = get_pcvar_float(iCvar_Health);
	set_pev(i_WeaponEntity, pev_health, 2000.0); 
	set_pev(i_WeaponEntity, pev_u_hphud, f_HPInit); 
	
	static Float:v_StickAng[3];
	v_StickAng[0] = -90.0; v_StickAng[1] = random_float(0.0, 360.0); v_StickAng[2] = 0.0;
	set_pev(i_WeaponEntity, pev_angles, v_StickAng);
	
	new i_TID = get_user_team(id);
	set_pev(i_WeaponEntity, pev_u_wpnid,  i_WpnID);
	set_pev(i_WeaponEntity, pev_u_team,   i_TID);
	set_pev(i_WeaponEntity, pev_u_clip,   i_Clip);
	set_pev(i_WeaponEntity, pev_u_ammo,   i_Bpk);
	set_pev(i_WeaponEntity, pev_owner,    id);
	set_pev(i_WeaponEntity, pev_u_basez,  v_G_Ori[2] + 40.0); 
	
	v_G_Ori[2] += 40.0; 
	engfunc(EngFunc_SetOrigin, i_WeaponEntity, v_G_Ori);
	engfunc(EngFunc_SetSize, i_WeaponEntity, Float:{-15.0, -15.0, -12.0}, Float:{15.0, 15.0, 12.0});

	ClearSlot(id, i_WpnID);
	UTIL_ApplyBar(id, 0);
	g_isUserPlanting[id] = false;
	
	set_pev(i_WeaponEntity, pev_nextthink, get_gametime() + 0.1);
}

/*================================================================================
 [ Automation & Dynamics Stanza ]
=================================================================================*/

public Device_ProcessThink(i_Ent) {
	if(!pev_valid(i_Ent)) return;

	static Float:v_Origin[3], Float:f_CT; 
	pev(i_Ent, pev_origin, v_Origin);
	f_CT = get_gametime();
	
	new i_TIdx      = pev(i_Ent, pev_u_team);
	new i_WeaponID = pev(i_Ent, pev_u_wpnid);
	new i_ClipCur  = pev(i_Ent, pev_u_clip);
	new i_AmmoCur  = pev(i_Ent, pev_u_ammo);
	new i_Owner    = pev(i_Ent, pev_owner);
	new bool:isRel = (pev(i_Ent, pev_u_rel) == 1);
	new Float:f_Ran  = get_pcvar_float(iCvar_Range);

	static Float:f_NextS; pev(i_Ent, pev_u_searcht, f_NextS);
	new i_MatchedVictim = pev(i_Ent, pev_u_target);
	
	if(f_CT >= f_NextS) {
		i_MatchedVictim = UTIL_GetVictim(i_Ent, v_Origin, i_TIdx, f_Ran);
		if(i_MatchedVictim && !pev(i_Ent, pev_u_target)) {
			emit_sound(i_Ent, CHAN_VOICE, "buttons/bell1.wav", 0.6, ATTN_NORM, 0, PITCH_NORM);
		}
		set_pev(i_Ent, pev_u_target, i_MatchedVictim);
		set_pev(i_Ent, pev_u_searcht, f_CT + 0.2);
	}

	if(!i_MatchedVictim) {
		set_pev(i_Ent, pev_renderfx, kRenderFxNone);
		static Float:v_IdleAng[3]; pev(i_Ent, pev_angles, v_IdleAng);
		v_IdleAng[1] += 4.5; 
		set_pev(i_Ent, pev_angles, v_IdleAng);
		static Float:f_BZ; pev(i_Ent, pev_u_basez, f_BZ);
		v_Origin[2] = f_BZ + (floatsin(f_CT * 45.0) * 10.0); 
		engfunc(EngFunc_SetOrigin, i_Ent, v_Origin);
	} else {
		set_pev(i_Ent, pev_renderfx, kRenderFxGlowShell);
		set_pev(i_Ent, pev_rendercolor, Float:{255.0, 0.0, 0.0});
		set_pev(i_Ent, pev_rendermode, kRenderNormal);
		set_pev(i_Ent, pev_renderamt, 100.0);

		static Float:v_VPos[3], Float:v_Angles[3], Float:v_Dir[3];
		pev(i_MatchedVictim, pev_origin, v_VPos);
		v_Dir[0] = v_VPos[0] - v_Origin[0]; v_Dir[1] = v_VPos[1] - v_Origin[1]; v_Dir[2] = v_VPos[2] - v_Origin[2];
		engfunc(EngFunc_VecToAngles, v_Dir, v_Angles);
		v_Angles[0] -= 90.0; 
		set_pev(i_Ent, pev_angles, v_Angles);
	}

	static Float:f_LP; pev(i_Ent, pev_u_pulset, f_LP);
	if(f_CT - f_LP >= 6.0) { 
		UTIL_DrawPulse(v_Origin, i_TIdx, f_Ran);
		set_pev(i_Ent, pev_u_pulset, f_CT);
	}
	
	static i_PIdx;
	for(i_PIdx = 1; i_PIdx <= 32; i_PIdx++) {
		if(!is_user_alive(i_PIdx)) { g_iAimerTarget[i_PIdx] = 0; continue; }
		g_iAimerTarget[i_PIdx] = 0;

		if(UTIL_IsPlayerLookingAt(i_PIdx, v_Origin, 0.98)) {
			g_iAimerTarget[i_PIdx] = i_Ent;
			static sz_OwnerN[32]; get_user_name(i_Owner, sz_OwnerN, 31);
			set_hudmessage(i_TIdx == 1 ? 255 : 50, 150, i_TIdx == 2 ? 255 : 50, -1.0, 0.40, 0, 0.0, 0.15, 0.05, 0.0);
			static Float:f_CurHP; pev(i_Ent, pev_u_hphud, f_CurHP);
			ShowSyncHudMsg(i_PIdx, g_hSync, "| AUTOMATIC DEFENSE |^nIntegrity: %.0f HP^nClip: %d^nReserve: %d^nOwner: %s%s", 
				f_CurHP, i_ClipCur, i_AmmoCur, sz_OwnerN, isRel ? "^n[ RELOADING SYSTEM ]" : "");
		}
	}

	if(isRel) {
		set_pev(i_Ent, pev_nextthink, f_CT + 0.1);
		return;
	}

	if(i_MatchedVictim && is_user_alive(i_MatchedVictim)) {
		if(i_ClipCur > 0) {
			Weapon_Fire(i_Ent, i_MatchedVictim, v_Origin, i_WeaponID);
			set_pev(i_Ent, pev_u_clip, i_ClipCur - 1);
			set_pev(i_Ent, pev_nextthink, f_CT + f_DelayPerWpn[i_WeaponID]);
			return;
		} else if(i_AmmoCur > 0) {
			set_pev(i_Ent, pev_u_rel, 1);
			set_task(3.0, "Task_WeaponReady", i_Ent);
			emit_sound(i_Ent, CHAN_WEAPON, "weapons/boltcurl.wav", 0.7, ATTN_NORM, 0, PITCH_NORM);
		} else {
			DeviceDeath(i_Ent, true);
			return;
		}
	}

	set_pev(i_Ent, pev_nextthink, f_CT + 0.1);
}

public Task_WeaponReady(i_Ent) {
	if(!pev_valid(i_Ent)) return;
	new i_WID      = pev(i_Ent, pev_u_wpnid);
	new i_BpkAmmo = pev(i_Ent, pev_u_ammo);
	new i_Limit   = UTIL_GetCap(i_WID);
	new i_Load    = min(i_BpkAmmo, i_Limit);
	set_pev(i_Ent, pev_u_clip, i_Load);
	set_pev(i_Ent, pev_u_ammo, i_BpkAmmo - i_Load);
	set_pev(i_Ent, pev_u_rel, 0);
}

/*================================================================================
 [ Manual Destruction Stanza ]
=================================================================================*/

public Hook_CmdStart_ManualAttack(id, i_Handle) {
	if(!g_iAimerTarget[id] || !is_user_alive(id)) return;
	static i_Btn; i_Btn = get_uc(i_Handle, UC_Buttons);
	if(!(i_Btn & IN_ATTACK)) return;
	static i_Target; i_Target = g_iAimerTarget[id];
	if(!pev_valid(i_Target)) { g_iAimerTarget[id] = 0; return; }
	static Float:f_CT; f_CT = get_gametime();
	if(f_CT < g_fDamageCooldown[id]) return;
	emit_sound(i_Target, CHAN_BODY, "debris/metal1.wav", 0.5, ATTN_NORM, 0, PITCH_NORM);
	static Float:f_HP; pev(i_Target, pev_u_hphud, f_HP);
	f_HP -= random_float(10.0, 15.0);
	set_pev(i_Target, pev_u_hphud, f_HP);
	static Float:v_Ori[3]; pev(i_Target, pev_origin, v_Ori);
	engfunc(EngFunc_MessageBegin, MSG_PVS, SVC_TEMPENTITY, v_Ori, 0);
	write_byte(TE_BLOODSPRITE);
	engfunc(EngFunc_WriteCoord, _:v_Ori[0]); engfunc(EngFunc_WriteCoord, _:v_Ori[1]); engfunc(EngFunc_WriteCoord, _:(v_Ori[2] + random_float(-4.0, 4.0)));
	write_short(g_sBlood); write_short(g_sBlood); write_byte(70); write_byte(3); message_end();
	if(f_HP <= 0.0) { DeviceDeath(i_Target, true); g_iAimerTarget[id] = 0; }
	g_fDamageCooldown[id] = f_CT + 0.12; 
}

/*================================================================================
 [ Specialized Utilities ]
=================================================================================*/

ClearSlot(id, i_WID) {
	static sz_N[32]; get_weaponname(i_WID, sz_N, 31);
	new i_E = find_ent_by_owner(-1, sz_N, id);
	if(i_E > 0) {
		set_pev(id, pev_weapons, pev(id, pev_weapons) & ~(1 << i_WID));
		cs_set_user_bpammo(id, i_WID, 0);
		ExecuteHamB(Ham_Item_Kill, i_E);
		set_task(0.2, "Task_KnifeReset", id);
	}
}

public Task_KnifeReset(id) {
	if(is_user_connected(id)) engclient_cmd(id, "weapon_knife");
}

DeviceDeath(i_Ent, bool:bExplode) {
	if(bExplode) {
		static Float:v_E_Ori[3]; pev(i_Ent, pev_origin, v_E_Ori);
		engfunc(EngFunc_MessageBegin, MSG_PVS, SVC_TEMPENTITY, v_E_Ori, 0);
		write_byte(TE_EXPLOSION);
		engfunc(EngFunc_WriteCoord, _:v_E_Ori[0]); engfunc(EngFunc_WriteCoord, _:v_E_Ori[1]); engfunc(EngFunc_WriteCoord, _:(v_E_Ori[2] + 15.0));
		write_short(g_sExp); write_byte(10); write_byte(35); write_byte(0);
		message_end();
	}
	engfunc(EngFunc_RemoveEntity, i_Ent);
}

Weapon_Fire(i_Ent, i_Vic, Float:v_C[3], i_Idx) {
	static Float:v_VPos[3]; pev(i_Vic, pev_origin, v_VPos); 
	ExecuteHamB(Ham_TakeDamage, i_Vic, i_Ent, pev(i_Ent, pev_owner), f_DamagePerWpn[i_Idx], DMG_BULLET);
	emit_sound(i_Ent, CHAN_WEAPON, "weapons/m4a1-1.wav", 0.9, ATTN_NORM, 0, PITCH_NORM);
	engfunc(EngFunc_MessageBegin, MSG_PVS, SVC_TEMPENTITY, v_C, 0);
	write_byte(TE_SPRITE);
	engfunc(EngFunc_WriteCoord, _:v_C[0]); engfunc(EngFunc_WriteCoord, _:v_C[1]); engfunc(EngFunc_WriteCoord, _:v_C[2]);
	write_short(g_sFlower); write_byte(5); write_byte(200); message_end();
	engfunc(EngFunc_MessageBegin, MSG_PVS, SVC_TEMPENTITY, v_C, 0);
	write_byte(TE_BEAMPOINTS);
	engfunc(EngFunc_WriteCoord, _:v_C[0]); engfunc(EngFunc_WriteCoord, _:v_C[1]); engfunc(EngFunc_WriteCoord, _:v_C[2]);
	engfunc(EngFunc_WriteCoord, _:v_VPos[0]); engfunc(EngFunc_WriteCoord, _:v_VPos[1]); engfunc(EngFunc_WriteCoord, _:v_VPos[2]);
	write_short(g_sBeam); write_byte(0); write_byte(1); write_byte(1); write_byte(15); write_byte(0);
	write_byte(255); write_byte(0); write_byte(0); write_byte(150); write_byte(0);
	message_end();
}

bool:UTIL_IsPlayerLookingAt(id, Float:v_T[3], Float:f_L) {
	static Float:v_PO[3], Float:v_PV[3], Float:v_PD[3];
	pev(id, pev_origin, v_PO); pev(id, pev_view_ofs, v_PD);
	v_PO[0] += v_PD[0]; v_PO[1] += v_PD[1]; v_PO[2] += v_PD[2];
	velocity_by_aim(id, 1, v_PV);
	v_PD[0] = v_T[0] - v_PO[0]; v_PD[1] = v_T[1] - v_PO[1]; v_PD[2] = v_T[2] - v_PO[2];
	if(vector_distance(v_PO, v_T) > 500.0) return false;
	xs_vec_normalize(v_PD, v_PD);
	return (xs_vec_dot(v_PV, v_PD) >= f_L);
}

UTIL_GetVictim(i_Ent, Float:v_S[3], i_Team, Float:f_Ran) {
	new i_Vic = -1, i_Best = 0; new Float:f_Closest = f_Ran;
	while((i_Vic = engfunc(EngFunc_FindEntityInSphere, i_Vic, v_S, f_Ran)) != 0) {
		if(i_Vic == i_Ent) continue;
		if(is_user_alive(i_Vic) && get_user_team(i_Vic) != i_Team) {
			static Float:v_VicOri[3]; pev(i_Vic, pev_origin, v_VicOri);
			new i_T = create_tr2();
			engfunc(EngFunc_TraceLine, v_S, v_VicOri, IGNORE_MONSTERS, i_Ent, i_T);
			new Float:f_Fr; get_tr2(i_T, TR_flFraction, f_Fr);
			free_tr2(i_T);
			if(f_Fr == 1.0) {
				new Float:f_D = get_distance_f(v_S, v_VicOri);
				if(f_D < f_Closest) { i_Best = i_Vic; f_Closest = f_D; }
			}
		}
	}
	return i_Best;
}

UTIL_GetCap(id) {
	switch(id) {
		case CSW_AK47, CSW_M4A1, CSW_AUG, CSW_SG552, CSW_MP5NAVY, CSW_TMP, CSW_MAC10: return 30;
		case CSW_FAMAS, CSW_GALIL: return 25;
		case CSW_P90: return 50;
		case CSW_M249: return 100;
		case CSW_XM1014: return 7;
		case CSW_M3: return 8;
		case CSW_SCOUT, CSW_AWP: return 10;
	}
	return 30;
}

AbortInteraction(id) {
	g_isUserPlanting[id] = false;
	remove_task(id + TASK_DEPLOY_VAL);
	UTIL_ApplyBar(id, 0);
}

UTIL_ApplyBar(id, dur) {
	message_begin(MSG_ONE, g_msgBarID, _, id);
	write_short(dur);
	message_end();
}

UTIL_DrawPulse(Float:v_P[3], i_Team, Float:f_R) {
	engfunc(EngFunc_MessageBegin, MSG_PVS, SVC_TEMPENTITY, v_P, 0);
	write_byte(TE_BEAMCYLINDER);
	engfunc(EngFunc_WriteCoord, _:v_P[0]); engfunc(EngFunc_WriteCoord, _:v_P[1]); engfunc(EngFunc_WriteCoord, _:(v_P[2] + 10.0)); 
	engfunc(EngFunc_WriteCoord, _:v_P[0]); engfunc(EngFunc_WriteCoord, _:v_P[1]); engfunc(EngFunc_WriteCoord, _:(v_P[2] + f_R)); 
	write_short(g_sBeam); write_byte(0); write_byte(1); write_byte(20); write_byte(8); write_byte(0);
	write_byte(i_Team == 1 ? 255 : 0); write_byte(0); write_byte(i_Team == 2 ? 255 : 0); write_byte(100); 
	write_byte(2); message_end();
}

public RoundEnd_Cleanup() {
	new i_Cleanup = -1;
	while((i_Cleanup = engfunc(EngFunc_FindEntityByString, i_Cleanup, "classname", CLASS_SENTRY)) != 0) {
		if(pev_valid(i_Cleanup)) engfunc(EngFunc_RemoveEntity, i_Cleanup);
	}
}
