#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>
#include <reapi>

#define PLUGIN_NAME    "Custom 3D Buy System"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR  "AI"

/* --- Configuration & Enums --- */

enum {
	ST_NONE = 0,
	ST_PRIMARY,
	ST_SECONDARY,
	ST_EQUIPMENT
};

enum _:WeaponData {
	WD_NAME[32],
	WD_CLASS[32],
	WD_W_MODEL[64],
	WD_V_MODEL[64],
	WD_P_MODEL[64],
	WD_CLIP,
	WD_BACKPACK,
	WD_PRICE,
	WD_FLAG
};

/* --- Global Variables --- */

new Array:g_aWeaponData;
new Array:g_aPrimary;
new Array:g_aSecondary;
new Array:g_aEquipment;

new g_iPlayerStage[MAX_PLAYERS + 1];
new g_iCurrentSelection[MAX_PLAYERS + 1];
new g_iPreviewEnt[MAX_PLAYERS + 1];
new g_iMsgStatusIcon;

new g_pCvarDist, g_pCvarRotate, g_pCvarScale, g_pCvarBuyTime;
new Float:g_fRoundStartTime;
new Trie:g_tCustomModels;

new const g_szConfigFile[] = "custom3dbuy.ini";
new const g_szMenuID[] = "Custom Buy Menu";

new Float:g_fLastOrigin[MAX_PLAYERS + 1][3];
new Float:g_fLastAngles[MAX_PLAYERS + 1][3];

/* --- Plugin Initialization --- */

public plugin_init() {
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

	// CVARs for customization
	g_pCvarDist   = register_cvar("qa_preview_dist", "100.0");
	g_pCvarRotate = register_cvar("qa_rotate_speed", "3.0");
	g_pCvarScale  = register_cvar("qa_preview_scale", "1.2");
	g_pCvarBuyTime = register_cvar("qa_buytime", "20.0");

	// Commands
	register_clcmd("shop", "Cmd_OpenShop");
	
	// Block default buy commands
	register_clcmd("buy", "Cmd_BlockBuy");
	register_clcmd("client_buy_open", "Cmd_BlockBuy");
	register_clcmd("cl_buy", "Cmd_BlockBuy");
	register_clcmd("autobuy", "Cmd_BlockBuy");
	register_clcmd("rebuy", "Cmd_BlockBuy");
	
	// Register Menu Handler (Proper way)
	register_menucmd(register_menuid(g_szMenuID), (1<<0)|(1<<1)|(1<<2), "Handle_ShopMenu");
	
	// ReAPI Hooks
	RegisterHookChain(RG_ShowVGUIMenu, "OnShowVGUIMenu", .post = false);
	RegisterHookChain(RG_ShowMenu, "OnShowMenu", .post = false);
	RegisterHookChain(RG_CSGameRules_RestartRound, "OnRestartRound", .post = true);
	
	// Fakemeta Hooks (High Compatibility)
	register_forward(FM_SetModel, "OnSetModel", 0);
	
	// HamSandwich Hooks
	RegisterHam(Ham_Spawn, "player", "OnPlayerSpawn", .Post = 1);
	
	// Hide BuyZone Icon
	g_iMsgStatusIcon = get_user_msgid("StatusIcon");
	register_message(g_iMsgStatusIcon, "Msg_StatusIcon");

	// Hook 'lastinv' (Q) to cycle
	register_clcmd("lastinv", "Cmd_CycleWeapon");
	
	// Menu Slot Hooks for skipping
	register_clcmd("slot3", "Cmd_SkipStage");
	
	// Optimization: Use a task instead of PreThink for all players
	// Increased interval to 0.1s for performance
	set_task(0.1, "Task_UpdatePreviews", .flags = "b");
}

public plugin_precache() {
	g_aWeaponData = ArrayCreate(WeaponData);
	g_aPrimary = ArrayCreate();
	g_aSecondary = ArrayCreate();
	g_aEquipment = ArrayCreate();
	g_tCustomModels = TrieCreate();
	
	LoadConfig();
}

public client_disconnected(id) {
	RemovePreview(id);
	g_iPlayerStage[id] = ST_NONE;
}

/* --- Hooks & Callbacks --- */

public OnRestartRound() {
	// Manual Buyzone Removal (Compatible with all versions)
	new iEnt = -1;
	while((iEnt = engfunc(EngFunc_FindEntityByString, iEnt, "classname", "func_buyzone")) != 0) {
		engfunc(EngFunc_RemoveEntity, iEnt);
	}
	
	set_member_game(m_bMapHasBuyZone, false);
	set_member_game(m_bCTCantBuy, true);
	set_member_game(m_bTCantBuy, true);
	
	g_fRoundStartTime = get_gametime();
}

public OnPlayerSpawn(id) {
	if (!is_user_alive(id)) return HAM_IGNORED;
	rg_remove_all_items(id);
	rg_give_item(id, "weapon_knife");
	return HAM_IGNORED;
}

public OnShowVGUIMenu(const id, VGUIMenu:menuType, const bitsSlots, szOldMenu[]) {
	if (menuType == VGUI_Menu_Buy) {
		Cmd_BlockBuy(id);
		return HC_SUPERCEDE;
	}
	return HC_CONTINUE;
}

public OnShowMenu(const id, const bitsSlots, const iDisplayTime, const iNeedMore, pszText[]) {
	if (containi(pszText, "Buy") != -1) {
		Cmd_BlockBuy(id);
		return HC_SUPERCEDE;
	}
	return HC_CONTINUE;
}

public Cmd_BlockBuy(id) {
	if (is_user_alive(id)) {
		client_print_color(id, print_team_default, "^4[Quantum]^1 Use ^3'shop'^1 command! (Bind B shop)");
	}
	return PLUGIN_HANDLED;
}

public Msg_StatusIcon(msg_id, msg_dest, id) {
	static szIcon[8];
	get_msg_arg_string(2, szIcon, charsmax(szIcon));
	
	if (equal(szIcon, "buyzone")) {
		if (get_msg_arg_int(1) != 0) {
			set_msg_arg_int(1, ARG_BYTE, 0); 
		}
	}
}

/* --- Shop Logic --- */

public Cmd_OpenShop(id) {
	if (!is_user_alive(id)) return PLUGIN_HANDLED;

	if (get_gametime() - g_fRoundStartTime > get_pcvar_float(g_pCvarBuyTime)) {
		client_print_color(id, print_team_default, "^4[Quantum]^1 Buy time has ^3expired^1!");
		return PLUGIN_HANDLED;
	}

	if (g_iPlayerStage[id] != ST_NONE) {
		Cmd_CloseShop(id);
		return PLUGIN_HANDLED;
	}

	new iStartStage = GetNextValidStage(ST_NONE);
	if (iStartStage == ST_NONE) {
		client_print_color(id, print_team_default, "^4[Quantum]^1 Shop is empty! Check config.");
		return PLUGIN_HANDLED;
	}

	g_iPlayerStage[id] = iStartStage;
	g_iCurrentSelection[id] = 0;
	
	ShowPreview(id);
	UpdateMenuInfo(id);
	
	client_print_color(id, print_team_default, "^4[Quantum]^1 Shop Opened. Use ^3'Q'^1 to cycle, ^3'1'^1 to buy, ^3'3'^1 to skip, ^3'2'^1 to close.");
	
	return PLUGIN_HANDLED;
}

public Cmd_CycleWeapon(id) {
	if (g_iPlayerStage[id] == ST_NONE) return PLUGIN_CONTINUE;

	new iMax = GetStageCount(g_iPlayerStage[id]);
	if (iMax <= 0) {
		Cmd_SkipStage(id);
		return PLUGIN_HANDLED;
	}

	g_iCurrentSelection[id]++;
	if (g_iCurrentSelection[id] >= iMax) {
		g_iCurrentSelection[id] = 0;
	}
	
	ShowPreview(id);
	UpdateMenuInfo(id);
	
	return PLUGIN_HANDLED;
}

// Proper Menu Handler
public Handle_ShopMenu(id, iKey) {
	if (g_iPlayerStage[id] == ST_NONE) return PLUGIN_HANDLED;

	switch(iKey) {
		case 0: Cmd_BuySelection(id); // Slot 1
		case 1: Cmd_CloseShop(id);    // Slot 2
		case 2: Cmd_SkipStage(id);    // Slot 3
	}
	
	return PLUGIN_HANDLED;
}

public Cmd_SkipStage(id) {
	if (g_iPlayerStage[id] == ST_NONE) return PLUGIN_CONTINUE;
	
	new iNextStage = GetNextValidStage(g_iPlayerStage[id]);
	if (iNextStage == ST_NONE) {
		Cmd_CloseShop(id);
		return PLUGIN_HANDLED;
	}
	
	g_iPlayerStage[id] = iNextStage;
	g_iCurrentSelection[id] = 0;
	
	ShowPreview(id);
	UpdateMenuInfo(id);
	client_print_color(id, print_team_default, "^4[Quantum]^1 Stage skipped to ^3%s^1.", GetStageNameString(g_iPlayerStage[id]));
	
	return PLUGIN_HANDLED;
}

public Cmd_BuySelection(id) {
	if (get_gametime() - g_fRoundStartTime > get_pcvar_float(g_pCvarBuyTime)) {
		client_print_color(id, print_team_default, "^4[Quantum]^1 Buy time has ^3expired^1!");
		Cmd_CloseShop(id);
		return PLUGIN_HANDLED;
	}

	new data[WeaponData];
	if (!GetWeaponData(g_iPlayerStage[id], g_iCurrentSelection[id], data)) return PLUGIN_HANDLED;
	
	// Flag Check
	if (data[WD_FLAG] != 0 && !(get_user_flags(id) & data[WD_FLAG])) {
		client_print_color(id, print_team_default, "^4[Quantum]^1 This weapon is for ^3VIPs^1 only!");
		UpdateMenuInfo(id); 
		return PLUGIN_HANDLED;
	}
	
	new iMoney = cs_get_user_money(id);
	if (iMoney < data[WD_PRICE]) {
		client_print_color(id, print_team_default, "^4[Quantum]^1 Insufficient funds! Need ^4$%d", data[WD_PRICE]);
		UpdateMenuInfo(id);
		return PLUGIN_HANDLED;
	}
	
	if (user_has_weapon(id, get_weaponid(data[WD_CLASS]))) {
		client_print_color(id, print_team_default, "^4[Quantum]^1 You already have this weapon!");
		UpdateMenuInfo(id);
		return PLUGIN_HANDLED;
	}
	
	cs_set_user_money(id, iMoney - data[WD_PRICE]);
	
	new iEnt = rg_give_item(id, data[WD_CLASS]);
	if (iEnt > 0) {
		// Store master index + 1 in impulse to identify this custom weapon
		set_pev(iEnt, pev_impulse, GetWeaponMasterIndex(g_iPlayerStage[id], g_iCurrentSelection[id]) + 1);
		
		// CRITICAL: Force immediate model update so user doesn't have to switch back and forth
		ExecuteHamB(Ham_Item_Deploy, iEnt);
		
		if (data[WD_CLIP] > 0) {
			cs_set_weapon_ammo(iEnt, data[WD_CLIP]);
		}
		if (data[WD_BACKPACK] > 0) {
			cs_set_user_bpammo(id, get_weaponid(data[WD_CLASS]), data[WD_BACKPACK]);
		}
	}
	
	client_print_color(id, print_team_default, "^4[Quantum]^1 Purchased: ^3%s", data[WD_NAME]);
	
	// Advance stage automatically
	Cmd_SkipStage(id);
	
	return PLUGIN_HANDLED;
}

// Helper to get stage name as string
GetStageNameString(iStage) {
	static szName[16];
	GetStageName(iStage, szName, charsmax(szName));
	return szName;
}

public Cmd_CloseShop(id) {
	if (g_iPlayerStage[id] == ST_NONE) return PLUGIN_CONTINUE;
	
	g_iPlayerStage[id] = ST_NONE;
	RemovePreview(id);
	
	// Clear Menu
	show_menu(id, 0, "^n", 1);
	
	return PLUGIN_HANDLED;
}

/* --- Visuals & Previews --- */

public OnItemDeploy(iEnt) {
	new iImpulse = pev(iEnt, pev_impulse);
	if (iImpulse <= 0) return;
	
	new iMasterIndex = iImpulse - 1;
	if (iMasterIndex < 0 || iMasterIndex >= ArraySize(g_aWeaponData)) return;
	
	new data[WeaponData];
	ArrayGetArray(g_aWeaponData, iMasterIndex, data);
	
	new id = get_member(iEnt, m_pPlayer);
	if (is_user_alive(id)) {
		if (data[WD_V_MODEL][0]) set_pev(id, pev_viewmodel2, data[WD_V_MODEL]);
		if (data[WD_P_MODEL][0]) set_pev(id, pev_weaponmodel2, data[WD_P_MODEL]);
	}
}

public OnSetModel(iEnt, const szModel[]) {
	if (!pev_valid(iEnt)) return FMRES_IGNORED;
	
	// We only care about models that look like default world models
	if (szModel[0] != 'm' || szModel[7] != 'w' || szModel[8] != '_') 
		return FMRES_IGNORED;

	static szClass[32];
	pev(iEnt, pev_classname, szClass, charsmax(szClass));
	
	new iWeapon = -1;
	
	// If it's a weaponbox, we need to find the weapon inside
	if (equal(szClass, "weaponbox")) {
		for (new i = 0; i < 6; i++) {
			iWeapon = get_member(iEnt, m_WeaponBox_rgpPlayerItems, i);
			if (iWeapon > 0) break;
		}
	} else if (containi(szClass, "weapon_") != -1) {
		iWeapon = iEnt;
	}
	
	if (iWeapon > 0) {
		new iImpulse = pev(iWeapon, pev_impulse);
		if (iImpulse > 0) {
			new iMasterIndex = iImpulse - 1;
			if (iMasterIndex >= 0 && iMasterIndex < ArraySize(g_aWeaponData)) {
				new data[WeaponData];
				ArrayGetArray(g_aWeaponData, iMasterIndex, data);
				
				if (data[WD_W_MODEL][0]) {
					set_pev(iEnt, pev_modelindex, engfunc(EngFunc_PrecacheModel, data[WD_W_MODEL]));
					return FMRES_SUPERCEDE;
				}
			}
		}
	}
	
	return FMRES_IGNORED;
}

public Task_UpdatePreviews() {
	static Float:fOrigin[3], Float:fAngles[3];
	
	for (new i = 1; i <= MaxClients; i++) {
		if (g_iPlayerStage[i] != ST_NONE && is_user_alive(i)) {
			pev(i, pev_origin, fOrigin);
			pev(i, pev_v_angle, fAngles);
			
			// Only update if player moved or looked around significantly
			if (vector_distance(fOrigin, g_fLastOrigin[i]) > 1.0 || vector_distance(fAngles, g_fLastAngles[i]) > 0.5) {
				UpdatePreviewPos(i);
				g_fLastOrigin[i] = fOrigin;
				g_fLastAngles[i] = fAngles;
			}
		}
	}
}

public ShowPreview(id) {
	RemovePreview(id);
	
	new data[WeaponData];
	if (!GetWeaponData(g_iPlayerStage[id], g_iCurrentSelection[id], data)) return;
	
	new iEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
	if (!pev_valid(iEnt)) return;
	
	set_pev(iEnt, pev_classname, "weapon_preview");
	engfunc(EngFunc_SetModel, iEnt, data[WD_W_MODEL]);
	
	set_pev(iEnt, pev_movetype, MOVETYPE_NOCLIP);
	set_pev(iEnt, pev_solid, SOLID_NOT);
	
	// Fully Visible
	set_pev(iEnt, pev_rendermode, kRenderNormal);
	set_pev(iEnt, pev_renderamt, 255.0);
	set_pev(iEnt, pev_scale, get_pcvar_float(g_pCvarScale));
	
	g_iPreviewEnt[id] = iEnt;
	UpdatePreviewPos(id);
}

public RemovePreview(id) {
	if (pev_valid(g_iPreviewEnt[id])) {
		engfunc(EngFunc_RemoveEntity, g_iPreviewEnt[id]);
	}
	g_iPreviewEnt[id] = 0;
}

public UpdatePreviewPos(id) {
	if (!pev_valid(g_iPreviewEnt[id])) return;
	
	new Float:fOrigin[3], Float:fAngles[3], Float:fForward[3];
	new Float:fViewOfs[3];
	
	pev(id, pev_origin, fOrigin);
	pev(id, pev_view_ofs, fViewOfs);
	fOrigin[0] += fViewOfs[0]; fOrigin[1] += fViewOfs[1]; fOrigin[2] += fViewOfs[2];
	
	pev(id, pev_v_angle, fAngles);
	angle_vector(fAngles, ANGLEVECTOR_FORWARD, fForward);
	
	new Float:fEnd[3];
	new Float:fDist = get_pcvar_float(g_pCvarDist);
	
	fEnd[0] = fOrigin[0] + fForward[0] * fDist;
	fEnd[1] = fOrigin[1] + fForward[1] * fDist;
	fEnd[2] = fOrigin[2] + fForward[2] * fDist;
	
	new ptr = create_tr2();
	engfunc(EngFunc_TraceLine, fOrigin, fEnd, DONT_IGNORE_MONSTERS, id, ptr);
	get_tr2(ptr, TR_vecEndPos, fOrigin);
	free_tr2(ptr);
	
	// Pull back slightly
	fOrigin[0] -= fForward[0] * 15.0;
	fOrigin[1] -= fForward[1] * 15.0;
	fOrigin[2] -= fForward[2] * 15.0;
	
	set_pev(g_iPreviewEnt[id], pev_origin, fOrigin);
	
	static Float:fRot[3];
	fRot[1] += get_pcvar_float(g_pCvarRotate);
	if (fRot[1] >= 360.0) fRot[1] -= 360.0;
	set_pev(g_iPreviewEnt[id], pev_angles, fRot);
}

public UpdateMenuInfo(id) {
	new data[WeaponData];
	if (!GetWeaponData(g_iPlayerStage[id], g_iCurrentSelection[id], data)) return;
	
	new szStageName[16];
	GetStageName(g_iPlayerStage[id], szStageName, charsmax(szStageName));

	new iMoney = cs_get_user_money(id);
	new bool:bHasWeapon = bool:(user_has_weapon(id, get_weaponid(data[WD_CLASS])));
	new bool:bCanBuy = (iMoney >= data[WD_PRICE] && !bHasWeapon);
	
	new szMenu[512], iLen;
	iLen = formatex(szMenu, charsmax(szMenu), "\yQuantum Arsenal Shop^n");
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\wStage: \r%s^n", szStageName);
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\wItem: \y%s^n", data[WD_NAME]);
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\wPrice: %s$%d^n", (iMoney >= data[WD_PRICE] ? "\g" : "\r"), data[WD_PRICE]);
	
	if (bHasWeapon) {
		iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r[Already Owned]^n^n");
	} else if (iMoney < data[WD_PRICE]) {
		iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r[Not Enough Money]^n^n");
	} else {
		iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n");
	}
	
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "%s1. \wBuy Item^n", (bCanBuy ? "\r" : "\d"));
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r2. \wExit^n");
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r3. \wSkip Stage^n^n");
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d[Q] Cycle Weapons");
	
	new iKeys = (1<<1) | (1<<2);
	if (bCanBuy) iKeys |= (1<<0);
	
	show_menu(id, iKeys, szMenu, -1, g_szMenuID);
}

/* --- Config & Data Handling --- */

public LoadConfig() {
	new szPath[128];
	get_configsdir(szPath, charsmax(szPath));
	format(szPath, charsmax(szPath), "%s/%s", szPath, g_szConfigFile);
	
	if (!file_exists(szPath)) {
		CreateDefaultConfig(szPath);
	}
	
	ArrayClear(g_aWeaponData);
	ArrayClear(g_aPrimary);
	ArrayClear(g_aSecondary);
	ArrayClear(g_aEquipment);
	TrieClear(g_tCustomModels);
	
	new f = fopen(szPath, "rt");
	if (!f) return;
	
	new szLine[512], szCat[16], szName[32], szClass[32], szWModel[64], szVModel[64], szPModel[64], szClip[8], szBackpack[8], szPrice[16], szFlag[8];
	while (!feof(f)) {
		fgets(f, szLine, charsmax(szLine));
		trim(szLine);
		
		if (!szLine[0] || szLine[0] == ';') continue;
		
		// Category, Name, weapon_Name, w_model, v_model, p_model, bullets, backpackammo, price, Flags
		parse(szLine, szCat, charsmax(szCat), szName, charsmax(szName), szClass, charsmax(szClass), 
			szWModel, charsmax(szWModel), szVModel, charsmax(szVModel), szPModel, charsmax(szPModel), 
			szClip, charsmax(szClip), szBackpack, charsmax(szBackpack), szPrice, charsmax(szPrice), szFlag, charsmax(szFlag));
		
		new data[WeaponData];
		copy(data[WD_NAME], charsmax(data[WD_NAME]), szName);
		copy(data[WD_CLASS], charsmax(data[WD_CLASS]), szClass);
		copy(data[WD_W_MODEL], charsmax(data[WD_W_MODEL]), szWModel);
		copy(data[WD_V_MODEL], charsmax(data[WD_V_MODEL]), szVModel);
		copy(data[WD_P_MODEL], charsmax(data[WD_P_MODEL]), szPModel);
		
		data[WD_CLIP] = str_to_num(szClip);
		data[WD_BACKPACK] = str_to_num(szBackpack);
		data[WD_PRICE] = str_to_num(szPrice);
		data[WD_FLAG] = (szFlag[0] == '0' || !szFlag[0]) ? 0 : read_flags(szFlag);
		
		new iIndex = ArrayPushArray(g_aWeaponData, data);
		
		if (equal(szCat, "PRIMARY")) ArrayPushCell(g_aPrimary, iIndex);
		else if (equal(szCat, "SECONDARY")) ArrayPushCell(g_aSecondary, iIndex);
		else if (equal(szCat, "EQUIPMENT")) ArrayPushCell(g_aEquipment, iIndex);
		
		// Precache and register models
		if (data[WD_W_MODEL][0]) engfunc(EngFunc_PrecacheModel, data[WD_W_MODEL]);
		if (data[WD_V_MODEL][0]) engfunc(EngFunc_PrecacheModel, data[WD_V_MODEL]);
		if (data[WD_P_MODEL][0]) engfunc(EngFunc_PrecacheModel, data[WD_P_MODEL]);
		
		// We still use the Trie for quick classname check, but now it just stores that this class HAS custom models
		if (!TrieKeyExists(g_tCustomModels, szClass)) {
			TrieSetCell(g_tCustomModels, szClass, 1);
			if (containi(szClass, "weapon_") != -1) {
				RegisterHam(Ham_Item_Deploy, szClass, "OnItemDeploy", .Post = true);
			}
		}
	}
	fclose(f);
}

public CreateDefaultConfig(const szPath[]) {
	new f = fopen(szPath, "wt");
	if (!f) return;
	
	fputs(f, "; Quantum Arsenal Configuration^n");
	fputs(f, "; Format: ^"CATEGORY^" ^"Name^" ^"Classname^" ^"W_Model^" ^"V_Model^" ^"P_Model^" ^"Clip^" ^"Backpack^" ^"Price^" ^"Flags^"^n^n");
	
	// Primaries
	fputs(f, "^"PRIMARY^" ^"AK-47 Dominator^" ^"weapon_ak47^" ^"models/w_ak47.mdl^" ^"models/v_ak47.mdl^" ^"models/p_ak47.mdl^" ^"30^" ^"90^" ^"2500^" ^"0^"^n");
	fputs(f, "^"PRIMARY^" ^"M4A1-S Phantom^" ^"weapon_m4a1^" ^"models/w_m4a1.mdl^" ^"models/v_m4a1.mdl^" ^"models/p_m4a1.mdl^" ^"30^" ^"90^" ^"3100^" ^"0^"^n");
	fputs(f, "^"PRIMARY^" ^"AWP Singularity^" ^"weapon_awp^" ^"models/w_awp.mdl^" ^"models/v_awp.mdl^" ^"models/p_awp.mdl^" ^"10^" ^"30^" ^"4750^" ^"0^"^n");
	
	// Secondaries
	fputs(f, "^"SECONDARY^" ^"Desert Eagle^" ^"weapon_deagle^" ^"models/w_deagle.mdl^" ^"models/v_deagle.mdl^" ^"models/p_deagle.mdl^" ^"7^" ^"35^" ^"650^" ^"0^"^n");
	
	// Equipment
	fputs(f, "^"EQUIPMENT^" ^"HE Grenade^" ^"weapon_hegrenade^" ^"models/w_hegrenade.mdl^" ^"models/v_hegrenade.mdl^" ^"models/p_hegrenade.mdl^" ^"1^" ^"0^" ^"300^" ^"0^"^n");
	
	fclose(f);
}

public GetStageCount(iStage) {
	if (iStage == ST_PRIMARY) return ArraySize(g_aPrimary);
	if (iStage == ST_SECONDARY) return ArraySize(g_aSecondary);
	if (iStage == ST_EQUIPMENT) return ArraySize(g_aEquipment);
	return 0;
}

public bool:GetWeaponData(iStage, iIndex, data[WeaponData]) {
	new iMasterIndex = GetWeaponMasterIndex(iStage, iIndex);
	if (iMasterIndex != -1) {
		ArrayGetArray(g_aWeaponData, iMasterIndex, data);
		return true;
	}
	return false;
}

public GetWeaponMasterIndex(iStage, iIndex) {
	new iSize = GetStageCount(iStage);
	if (iIndex < 0 || iIndex >= iSize) return -1;
	
	if (iStage == ST_PRIMARY) return ArrayGetCell(g_aPrimary, iIndex);
	if (iStage == ST_SECONDARY) return ArrayGetCell(g_aSecondary, iIndex);
	if (iStage == ST_EQUIPMENT) return ArrayGetCell(g_aEquipment, iIndex);
	return -1;
}

public GetNextValidStage(iCurrentStage) {
	new iNext = iCurrentStage;
	for (;;) {
		if (iNext == ST_NONE) iNext = ST_PRIMARY;
		else if (iNext == ST_PRIMARY) iNext = ST_SECONDARY;
		else if (iNext == ST_SECONDARY) iNext = ST_EQUIPMENT;
		else return ST_NONE;
		
		if (GetStageCount(iNext) > 0) return iNext;
	}
	return ST_NONE;
}

public GetStageName(iStage, szName[], iLen) {
	if (iStage == ST_PRIMARY) copy(szName, iLen, "Primary");
	else if (iStage == ST_SECONDARY) copy(szName, iLen, "Secondary");
	else if (iStage == ST_EQUIPMENT) copy(szName, iLen, "Equipment");
	else copy(szName, iLen, "None");
}
