#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>
#include <reapi>

#define PLUGIN_NAME    "Quantum Arsenal"
#define PLUGIN_VERSION "1.1"
#define PLUGIN_AUTHOR  "AI Studio"

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

new g_pCvarDist, g_pCvarRotate, g_pCvarScale, g_pCvarBuyTime, g_pCvarFlash, g_pCvarSellPercent;
new Float:g_fRoundStartTime;
new Trie:g_tCustomModels;
new g_iHudSync;
new Array:g_aRebuyList[MAX_PLAYERS + 1];

new const g_szConfigFile[] = "custom3dbuy.ini";
new const g_szMenuID[] = "Custom Buy Menu";

/* --- Plugin Initialization --- */

public plugin_init() {
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

	// CVARs for customization
	g_pCvarDist   = register_cvar("qa_preview_dist", "100.0");
	g_pCvarRotate = register_cvar("qa_rotate_speed", "3.0");
	g_pCvarScale  = register_cvar("qa_preview_scale", "1.2");
	g_pCvarBuyTime = register_cvar("qa_buytime", "20.0");
	g_pCvarFlash   = register_cvar("qa_buy_flash", "1");
	g_pCvarSellPercent = register_cvar("qa_sell_percent", "50.0");

	// Commands
	register_clcmd("shop", "Cmd_OpenShop");
	register_clcmd("buy", "Cmd_OpenShop");
	register_clcmd("client_buy_open", "Cmd_OpenShop");
	register_clcmd("cl_buy", "Cmd_OpenShop");
	register_clcmd("autobuy", "Cmd_AutoBuy");
	register_clcmd("rebuy", "Cmd_OpenShop");
	
	// Register Menu Handler
	register_menucmd(register_menuid(g_szMenuID), (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<6)|(1<<7), "Handle_ShopMenu");
	
	g_iHudSync = CreateHudSyncObj();
	
	// ReAPI Hooks
	RegisterHookChain(RG_ShowVGUIMenu, "OnShowVGUIMenu", .post = false);
	RegisterHookChain(RG_ShowMenu, "OnShowMenu", .post = false);
	RegisterHookChain(RG_CSGameRules_RestartRound, "OnRestartRound", .post = true);
	
	// Fakemeta Hooks
	register_forward(FM_SetModel, "OnSetModel", 0);
	
	// HamSandwich Hooks
	RegisterHam(Ham_Spawn, "player", "OnPlayerSpawn", .Post = 1);
	RegisterHam(Ham_Player_UpdateClientData, "player", "OnUpdateClientData", .Post = 1);
	
	// Hide BuyZone Icon
	g_iMsgStatusIcon = get_user_msgid("StatusIcon");
	register_message(g_iMsgStatusIcon, "Msg_StatusIcon");

	// Hook 'lastinv' (Q) to cycle
	register_clcmd("lastinv", "Cmd_CycleWeapon");
	
	// Menu Slot Hooks for skipping
	register_clcmd("slot3", "Cmd_SkipStage");
}

public plugin_end() {
	TrieDestroy(g_tCustomModels);
	for (new i = 1; i <= MAX_PLAYERS; i++) {
		ArrayDestroy(g_aRebuyList[i]);
	}
}

public plugin_precache() {
	g_aWeaponData = ArrayCreate(WeaponData);
	g_aPrimary = ArrayCreate();
	g_aSecondary = ArrayCreate();
	g_aEquipment = ArrayCreate();
	g_tCustomModels = TrieCreate();
	
	for (new i = 1; i <= MAX_PLAYERS; i++) {
		g_aRebuyList[i] = ArrayCreate();
	}
	
	LoadConfig();
}

public client_disconnected(id) {
	Cmd_CloseShop(id);
	ArrayClear(g_aRebuyList[id]);
}

/* --- Hooks & Callbacks --- */

public OnRestartRound() {
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
	
	new Float:fPercent = get_pcvar_float(g_pCvarSellPercent) / 100.0;
	new iTotalRefund = 0;
	
	for (new i = 1; i <= 5; i++) {
		new iEnt = get_member(id, m_rgpPlayerItems, i);
		while (iEnt > 0) {
			new iNext = get_member(iEnt, m_pNext);
			new szClass[32];
			pev(iEnt, pev_classname, szClass, charsmax(szClass));
			
			if (!equal(szClass, "weapon_knife")) {
				new iPrice = 0;
				new iImpulse = pev(iEnt, pev_impulse);
				if (iImpulse > 0) {
					new iMasterIndex = iImpulse - 1;
					new data[WeaponData];
					if (iMasterIndex >= 0 && iMasterIndex < ArraySize(g_aWeaponData)) {
						ArrayGetArray(g_aWeaponData, iMasterIndex, data);
						iPrice = data[WD_PRICE];
					}
				} else {
					iPrice = GetDefaultWeaponPrice(szClass);
				}
				
				if (iPrice > 0) iTotalRefund += floatround(float(iPrice) * fPercent);
			}
			iEnt = iNext;
		}
	}
	
	if (iTotalRefund > 0) {
		cs_set_user_money(id, cs_get_user_money(id) + iTotalRefund);
		client_print_color(id, print_team_default, "^4[Quantum]^1 Sold previous gear for ^4$%d^1.", iTotalRefund);
	}

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
		client_print_color(id, print_team_default, "^4[Quantum]^1 Use ^3'shop'^1 command!");
	}
	return PLUGIN_HANDLED;
}

public Msg_StatusIcon(msg_id, msg_dest, id) {
	static szIcon[8];
	get_msg_arg_string(2, szIcon, charsmax(szIcon));
	if (equal(szIcon, "buyzone") && get_msg_arg_int(1) != 0) {
		set_msg_arg_int(1, ARG_BYTE, 0); 
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
	if (iStartStage == ST_NONE) return PLUGIN_HANDLED;

	g_iPlayerStage[id] = iStartStage;
	g_iCurrentSelection[id] = 0;
	
	ShowPreview(id);
	UpdateMenuInfo(id);
	
	set_hudmessage(0, 255, 255, -1.0, 0.2, 0, 0.0, 3.0, 0.1, 0.1);
	ShowSyncHudMsg(id, g_iHudSync, "--- QUANTUM ARSENAL ---^n 3D SHOP ACTIVATED");
	
	return PLUGIN_HANDLED;
}

public Cmd_CycleWeapon(id) {
	if (g_iPlayerStage[id] == ST_NONE) return PLUGIN_CONTINUE;

	new iMax = GetStageCount(g_iPlayerStage[id]);
	if (iMax <= 0) {
		Cmd_SkipStage(id);
		return PLUGIN_HANDLED;
	}

	g_iCurrentSelection[id] = (g_iCurrentSelection[id] + 1) % iMax;
	ShowPreview(id);
	UpdateMenuInfo(id);
	return PLUGIN_HANDLED;
}

public Handle_ShopMenu(id, iKey) {
	if (g_iPlayerStage[id] == ST_NONE) return PLUGIN_HANDLED;
	switch(iKey) {
		case 0: Cmd_BuySelection(id);
		case 1: Cmd_CloseShop(id);
		case 2: Cmd_SkipStage(id);
		case 3: Cmd_PrevStage(id);
		case 4: Cmd_AutoBuy(id);
		case 5: Cmd_SellWeapon(id);
		case 6: Cmd_SellAll(id);
		case 7: Cmd_Rebuy(id);
	}
	return PLUGIN_HANDLED;
}

public Cmd_Rebuy(id) {
	if (ArraySize(g_aRebuyList[id]) <= 0) {
		client_print_color(id, print_team_default, "^4[Quantum]^1 No previous purchase history!");
		UpdateMenuInfo(id);
		return PLUGIN_HANDLED;
	}

	if (get_gametime() - g_fRoundStartTime > get_pcvar_float(g_pCvarBuyTime)) {
		client_print_color(id, print_team_default, "^4[Quantum]^1 Buy time has ^3expired^1!");
		Cmd_CloseShop(id);
		return PLUGIN_HANDLED;
	}

	new iMoney = cs_get_user_money(id);
	new bool:bBought = false;
	new data[WeaponData];
	
	for (new i = 0; i < ArraySize(g_aRebuyList[id]); i++) {
		new iMasterIndex = ArrayGetCell(g_aRebuyList[id], i);
		ArrayGetArray(g_aWeaponData, iMasterIndex, data);
		
		if (iMoney >= data[WD_PRICE] && !user_has_weapon(id, get_weaponid(data[WD_CLASS]))) {
			if (data[WD_FLAG] == 0 || (get_user_flags(id) & data[WD_FLAG])) {
				iMoney -= data[WD_PRICE];
				new iEnt = rg_give_item(id, data[WD_CLASS]);
				if (iEnt > 0) {
					set_pev(iEnt, pev_impulse, iMasterIndex + 1);
					ExecuteHamB(Ham_Item_Deploy, iEnt);
					if (data[WD_CLIP] > 0) cs_set_weapon_ammo(iEnt, data[WD_CLIP]);
					if (data[WD_BACKPACK] > 0) cs_set_user_bpammo(id, get_weaponid(data[WD_CLASS]), data[WD_BACKPACK]);
					bBought = true;
				}
			}
		}
	}
	
	if (bBought) {
		cs_set_user_money(id, iMoney);
		if (get_pcvar_num(g_pCvarFlash)) Util_ScreenFlash(id, 0, 255, 0, 100);
		client_print_color(id, print_team_default, "^4[Quantum]^1 Rebuy complete!");
	}
	
	Cmd_CloseShop(id);
	return PLUGIN_HANDLED;
}

public Cmd_PrevStage(id) {
	if (g_iPlayerStage[id] == ST_NONE) return PLUGIN_CONTINUE;
	
	new iPrevStage = GetPrevValidStage(g_iPlayerStage[id]);
	if (iPrevStage == ST_NONE) {
		UpdateMenuInfo(id);
		return PLUGIN_HANDLED;
	}
	
	g_iPlayerStage[id] = iPrevStage;
	g_iCurrentSelection[id] = 0;
	
	ShowPreview(id);
	UpdateMenuInfo(id);
	
	return PLUGIN_HANDLED;
}

public Cmd_SkipStage(id) {
	if (g_iPlayerStage[id] == ST_NONE) return PLUGIN_CONTINUE;
	
	new iNextStage = GetNextValidStage(g_iPlayerStage[id]);
	if (iNextStage == ST_NONE) {
		UpdateMenuInfo(id);
		return PLUGIN_HANDLED;
	}
	
	g_iPlayerStage[id] = iNextStage;
	g_iCurrentSelection[id] = 0;
	
	ShowPreview(id);
	UpdateMenuInfo(id);
	
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
		new iMasterIndex = GetWeaponMasterIndex(g_iPlayerStage[id], g_iCurrentSelection[id]);
		set_pev(iEnt, pev_impulse, iMasterIndex + 1);
		ExecuteHamB(Ham_Item_Deploy, iEnt);
		if (data[WD_CLIP] > 0) cs_set_weapon_ammo(iEnt, data[WD_CLIP]);
		if (data[WD_BACKPACK] > 0) cs_set_user_bpammo(id, get_weaponid(data[WD_CLASS]), data[WD_BACKPACK]);
		
		// Add to Rebuy List
		ArrayPushCell(g_aRebuyList[id], iMasterIndex);
		
		// Force switch to avoid grenade bug
		rg_switch_weapon(id, iEnt);
	}
	
	if (get_pcvar_num(g_pCvarFlash)) Util_ScreenFlash(id, 0, 255, 0, 100);
	
	if (g_iPlayerStage[id] == ST_EQUIPMENT) UpdateMenuInfo(id);
	else Cmd_SkipStage(id);
	
	return PLUGIN_HANDLED;
}

public Cmd_AutoBuy(id) {
	if (!is_user_alive(id)) return PLUGIN_HANDLED;
	
	if (get_gametime() - g_fRoundStartTime > get_pcvar_float(g_pCvarBuyTime)) {
		client_print_color(id, print_team_default, "^4[Quantum]^1 Buy time has ^3expired^1!");
		Cmd_CloseShop(id);
		return PLUGIN_HANDLED;
	}

	new iMoney = cs_get_user_money(id);
	new bool:bBought = false;
	
	if (AttemptRandomBuy(id, ST_PRIMARY, iMoney)) bBought = true;
	if (AttemptRandomBuy(id, ST_SECONDARY, iMoney)) bBought = true;
	if (AttemptRandomBuy(id, ST_EQUIPMENT, iMoney)) bBought = true;
	
	if (bBought) {
		cs_set_user_money(id, iMoney);
		if (get_pcvar_num(g_pCvarFlash)) Util_ScreenFlash(id, 0, 255, 0, 100);
		client_print_color(id, print_team_default, "^4[Quantum]^1 AutoBuy complete!");
	} else {
		client_print_color(id, print_team_default, "^4[Quantum]^1 AutoBuy failed: Not enough money or already armed.");
	}
	
	Cmd_CloseShop(id);
	return PLUGIN_HANDLED;
}

bool:AttemptRandomBuy(id, iStage, &iMoney) {
	new iCount = GetStageCount(iStage);
	if (iCount <= 0) return false;
	
	// Check if player already has a weapon in this category's slot
	if (iStage == ST_PRIMARY && get_member(id, m_rgpPlayerItems, 1) > 0) return false;
	if (iStage == ST_SECONDARY && get_member(id, m_rgpPlayerItems, 2) > 0) return false;
	
	new Array:aValid = ArrayCreate();
	new data[WeaponData];
	
	for (new i = 0; i < iCount; i++) {
		GetWeaponData(iStage, i, data);
		if (iMoney >= data[WD_PRICE] && !user_has_weapon(id, get_weaponid(data[WD_CLASS]))) {
			if (data[WD_FLAG] == 0 || (get_user_flags(id) & data[WD_FLAG])) {
				ArrayPushCell(aValid, i);
			}
		}
	}
	
	new iValidCount = ArraySize(aValid);
	if (iValidCount <= 0) {
		ArrayDestroy(aValid);
		return false;
	}
	
	new iRand = random(iValidCount);
	new iSelection = ArrayGetCell(aValid, iRand);
	ArrayDestroy(aValid);
	
	new iMasterIndex = GetWeaponMasterIndex(iStage, iSelection);
	GetWeaponData(iStage, iSelection, data);
	iMoney -= data[WD_PRICE];
	
	new iEnt = rg_give_item(id, data[WD_CLASS]);
	if (iEnt > 0) {
		set_pev(iEnt, pev_impulse, iMasterIndex + 1);
		ExecuteHamB(Ham_Item_Deploy, iEnt);
		if (data[WD_CLIP] > 0) cs_set_weapon_ammo(iEnt, data[WD_CLIP]);
		if (data[WD_BACKPACK] > 0) cs_set_user_bpammo(id, get_weaponid(data[WD_CLASS]), data[WD_BACKPACK]);
		
		// Add to Rebuy List
		ArrayPushCell(g_aRebuyList[id], iMasterIndex);
	}
	
	return true;
}

public Cmd_SellWeapon(id) {
	new iEnt = get_member(id, m_pActiveItem);
	if (!pev_valid(iEnt)) return PLUGIN_HANDLED;
	new szClass[32]; pev(iEnt, pev_classname, szClass, charsmax(szClass));
	if (equal(szClass, "weapon_knife")) return PLUGIN_HANDLED;
	
	new iPrice = 0;
	new iImpulse = pev(iEnt, pev_impulse);
	if (iImpulse > 0) {
		new iMasterIndex = iImpulse - 1;
		new data[WeaponData];
		if (iMasterIndex >= 0 && iMasterIndex < ArraySize(g_aWeaponData)) {
			ArrayGetArray(g_aWeaponData, iMasterIndex, data);
			iPrice = data[WD_PRICE];
		}
	} else {
		iPrice = GetDefaultWeaponPrice(szClass);
	}
	
	new iRefund = floatround(float(iPrice) * (get_pcvar_float(g_pCvarSellPercent) / 100.0));
	cs_set_user_money(id, cs_get_user_money(id) + iRefund);
	rg_remove_item(id, szClass);
	
	if (g_iPlayerStage[id] != ST_NONE) UpdateMenuInfo(id);
	return PLUGIN_HANDLED;
}

public Cmd_SellAll(id) {
	new iMoney = cs_get_user_money(id);
	new iTotalRefund = 0;
	new Float:fPercent = get_pcvar_float(g_pCvarSellPercent) / 100.0;
	
	for (new i = 1; i <= 5; i++) {
		new iEnt = get_member(id, m_rgpPlayerItems, i);
		while (iEnt > 0) {
			new iNext = get_member(iEnt, m_pNext);
			new szClass[32]; pev(iEnt, pev_classname, szClass, charsmax(szClass));
			if (!equal(szClass, "weapon_knife")) {
				new iPrice = 0;
				new iImpulse = pev(iEnt, pev_impulse);
				if (iImpulse > 0) {
					new iMasterIndex = iImpulse - 1;
					new data[WeaponData];
					if (iMasterIndex >= 0 && iMasterIndex < ArraySize(g_aWeaponData)) {
						ArrayGetArray(g_aWeaponData, iMasterIndex, data);
						iPrice = data[WD_PRICE];
					}
				} else {
					iPrice = GetDefaultWeaponPrice(szClass);
				}
				if (iPrice > 0) {
					iTotalRefund += floatround(float(iPrice) * fPercent);
					rg_remove_item(id, szClass);
				}
			}
			iEnt = iNext;
		}
	}
	cs_set_user_money(id, iMoney + iTotalRefund);
	Cmd_CloseShop(id);
	return PLUGIN_HANDLED;
}

GetDefaultWeaponPrice(const szClass[]) {
	new data[WeaponData];
	for (new i = 0; i < ArraySize(g_aWeaponData); i++) {
		ArrayGetArray(g_aWeaponData, i, data);
		if (equal(szClass, data[WD_CLASS])) return data[WD_PRICE];
	}
	return 0;
}

public Cmd_CloseShop(id) {
	if (g_iPlayerStage[id] == ST_NONE) return PLUGIN_CONTINUE;
	g_iPlayerStage[id] = ST_NONE;
	RemovePreview(id);
	show_menu(id, 0, "^n", 1);
	return PLUGIN_HANDLED;
}

/* --- Visuals & Previews --- */

public OnSetModel(iEnt, const szModel[]) {
	if (!pev_valid(iEnt)) return FMRES_IGNORED;
	if (szModel[0] != 'm' || szModel[7] != 'w' || szModel[8] != '_') return FMRES_IGNORED;

	new iImpulse = pev(iEnt, pev_impulse);
	if (iImpulse <= 0) return FMRES_IGNORED;
	
	new iMasterIndex = iImpulse - 1;
	if (iMasterIndex < 0 || iMasterIndex >= ArraySize(g_aWeaponData)) return FMRES_IGNORED;
	
	new data[WeaponData];
	ArrayGetArray(g_aWeaponData, iMasterIndex, data);
	
	if (data[WD_W_MODEL][0]) {
		engfunc(EngFunc_SetModel, iEnt, data[WD_W_MODEL]);
		return FMRES_SUPERCEDE;
	}
	
	return FMRES_IGNORED;
}

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

public OnUpdateClientData(id) {
	if (g_iPlayerStage[id] != ST_NONE && is_user_alive(id)) {
		UpdatePreviewPos(id);
	}
}

public ShowPreview(id) {
	RemovePreview(id);
	new data[WeaponData];
	if (!GetWeaponData(g_iPlayerStage[id], g_iCurrentSelection[id], data)) return;
	new iEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
	set_pev(iEnt, pev_classname, "weapon_preview");
	engfunc(EngFunc_SetModel, iEnt, data[WD_W_MODEL]);
	set_pev(iEnt, pev_movetype, MOVETYPE_NOCLIP);
	set_pev(iEnt, pev_solid, SOLID_NOT);
	set_pev(iEnt, pev_scale, get_pcvar_float(g_pCvarScale));
	g_iPreviewEnt[id] = iEnt;
	UpdatePreviewPos(id);
}

public RemovePreview(id) {
	if (pev_valid(g_iPreviewEnt[id])) engfunc(EngFunc_RemoveEntity, g_iPreviewEnt[id]);
	g_iPreviewEnt[id] = 0;
}

public UpdatePreviewPos(id) {
	if (!pev_valid(g_iPreviewEnt[id])) return;
	new Float:fOrigin[3], Float:fAngles[3], Float:fForward[3], Float:fViewOfs[3];
	pev(id, pev_origin, fOrigin); pev(id, pev_view_ofs, fViewOfs);
	fOrigin[0] += fViewOfs[0]; fOrigin[1] += fViewOfs[1]; fOrigin[2] += fViewOfs[2];
	pev(id, pev_v_angle, fAngles); angle_vector(fAngles, ANGLEVECTOR_FORWARD, fForward);
	
	new Float:fPreviewPos[3];
	fPreviewPos[0] = fOrigin[0] + fForward[0] * get_pcvar_float(g_pCvarDist);
	fPreviewPos[1] = fOrigin[1] + fForward[1] * get_pcvar_float(g_pCvarDist);
	fPreviewPos[2] = fOrigin[2] + fForward[2] * get_pcvar_float(g_pCvarDist);
	
	new ptr = create_tr2();
	engfunc(EngFunc_TraceLine, fOrigin, fPreviewPos, DONT_IGNORE_MONSTERS, id, ptr);
	get_tr2(ptr, TR_vecEndPos, fPreviewPos);
	free_tr2(ptr);
	
	fPreviewPos[0] -= fForward[0] * 15.0; fPreviewPos[1] -= fForward[1] * 15.0; fPreviewPos[2] -= fForward[2] * 15.0;
	fPreviewPos[2] += (floatsin(get_gametime() * 3.0) * 4.0);
	set_pev(g_iPreviewEnt[id], pev_origin, fPreviewPos);
	
	static Float:fRot[3];
	fRot[1] = fAngles[1] + (get_gametime() * get_pcvar_float(g_pCvarRotate) * 15.0); 
	set_pev(g_iPreviewEnt[id], pev_angles, fRot);
}

public UpdateMenuInfo(id) {
	new data[WeaponData];
	if (!GetWeaponData(g_iPlayerStage[id], g_iCurrentSelection[id], data)) return;
	new szStageName[16]; GetStageName(g_iPlayerStage[id], szStageName, charsmax(szStageName));
	new iMoney = cs_get_user_money(id);
	new bool:bHasHistory = bool:(ArraySize(g_aRebuyList[id]) > 0);
	
	new szMenu[512], iLen;
	iLen = formatex(szMenu, charsmax(szMenu), "\yQuantum Arsenal Shop^n");
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\wStage: \r%s^n", szStageName);
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\wItem: \y%s^n", data[WD_NAME]);
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\wPrice: %s$%d^n^n", (iMoney >= data[WD_PRICE] ? "\g" : "\r"), data[WD_PRICE]);
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r1. \wBuy Item^n\r2. \wExit^n\r3. \wSkip Stage^n\r4. \wBack Stage^n\r5. \wAutoBuy^n\r6. \wSell Weapon^n\r7. \wSell ALL^n%s8. \wRebuy Last Loadout^n^n\d[Q] Cycle", (bHasHistory ? "\r" : "\d"));
	
	new iKeys = (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<6);
	if (bHasHistory) iKeys |= (1<<7);
	
	show_menu(id, iKeys, szMenu, -1, g_szMenuID);
}

/* --- Config & Data Handling --- */

public LoadConfig() {
	new szPath[128]; get_configsdir(szPath, charsmax(szPath));
	format(szPath, charsmax(szPath), "%s/%s", szPath, g_szConfigFile);
	if (!file_exists(szPath)) CreateDefaultConfig(szPath);
	
	ArrayClear(g_aWeaponData); ArrayClear(g_aPrimary); ArrayClear(g_aSecondary); ArrayClear(g_aEquipment); TrieClear(g_tCustomModels);
	new f = fopen(szPath, "rt");
	if (!f) return;
	new szLine[512], szCat[16], szName[32], szClass[32], szWModel[64], szVModel[64], szPModel[64], szClip[8], szBackpack[8], szPrice[16], szFlag[8];
	while (!feof(f)) {
		fgets(f, szLine, charsmax(szLine)); trim(szLine);
		if (!szLine[0] || szLine[0] == ';') continue;
		parse(szLine, szCat, charsmax(szCat), szName, charsmax(szName), szClass, charsmax(szClass), szWModel, charsmax(szWModel), szVModel, charsmax(szVModel), szPModel, charsmax(szPModel), szClip, charsmax(szClip), szBackpack, charsmax(szBackpack), szPrice, charsmax(szPrice), szFlag, charsmax(szFlag));
		new data[WeaponData];
		copy(data[WD_NAME], charsmax(data[WD_NAME]), szName); copy(data[WD_CLASS], charsmax(data[WD_CLASS]), szClass); copy(data[WD_W_MODEL], charsmax(data[WD_W_MODEL]), szWModel); copy(data[WD_V_MODEL], charsmax(data[WD_V_MODEL]), szVModel); copy(data[WD_P_MODEL], charsmax(data[WD_P_MODEL]), szPModel);
		data[WD_CLIP] = str_to_num(szClip); data[WD_BACKPACK] = str_to_num(szBackpack); data[WD_PRICE] = str_to_num(szPrice); data[WD_FLAG] = (szFlag[0] == '0' || !szFlag[0]) ? 0 : read_flags(szFlag);
		new iIndex = ArrayPushArray(g_aWeaponData, data);
		if (equal(szCat, "PRIMARY")) ArrayPushCell(g_aPrimary, iIndex);
		else if (equal(szCat, "SECONDARY")) ArrayPushCell(g_aSecondary, iIndex);
		else if (equal(szCat, "EQUIPMENT")) ArrayPushCell(g_aEquipment, iIndex);
		
		if (data[WD_W_MODEL][0]) engfunc(EngFunc_PrecacheModel, data[WD_W_MODEL]);
		if (data[WD_V_MODEL][0]) engfunc(EngFunc_PrecacheModel, data[WD_V_MODEL]);
		if (data[WD_P_MODEL][0]) engfunc(EngFunc_PrecacheModel, data[WD_P_MODEL]);
		
		if (!TrieKeyExists(g_tCustomModels, szClass)) {
			TrieSetCell(g_tCustomModels, szClass, 1);
			if (containi(szClass, "weapon_") != -1) RegisterHam(Ham_Item_Deploy, szClass, "OnItemDeploy", .Post = true);
		}
	}
	fclose(f);
}

public CreateDefaultConfig(const szPath[]) {
	new f = fopen(szPath, "wt");
	if (!f) return;
	fputs(f, "; Quantum Arsenal Configuration^n; Format: ^"CATEGORY^" ^"Name^" ^"Classname^" ^"W_Model^" ^"V_Model^" ^"P_Model^" ^"Clip^" ^"Backpack^" ^"Price^" ^"Flags^"^n^n");
	fputs(f, "^"PRIMARY^" ^"AK-47 Dominator^" ^"weapon_ak47^" ^"models/w_ak47.mdl^" ^"models/v_ak47.mdl^" ^"models/p_ak47.mdl^" ^"30^" ^"90^" ^"2500^" ^"0^"^n");
	fputs(f, "^"SECONDARY^" ^"Desert Eagle^" ^"weapon_deagle^" ^"models/w_deagle.mdl^" ^"models/v_deagle.mdl^" ^"models/p_deagle.mdl^" ^"7^" ^"35^" ^"650^" ^"0^"^n");
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
	if (iMasterIndex != -1) { ArrayGetArray(g_aWeaponData, iMasterIndex, data); return true; }
	return false;
}

public GetWeaponMasterIndex(iStage, iIndex) {
	if (iIndex < 0 || iIndex >= GetStageCount(iStage)) return -1;
	if (iStage == ST_PRIMARY) return ArrayGetCell(g_aPrimary, iIndex);
	if (iStage == ST_SECONDARY) return ArrayGetCell(g_aSecondary, iIndex);
	if (iStage == ST_EQUIPMENT) return ArrayGetCell(g_aEquipment, iIndex);
	return -1;
}

GetNextValidStage(iCurrentStage) {
	new iNext = iCurrentStage;
	for (new i = 0; i < 3; i++) {
		if (iNext == ST_NONE) iNext = ST_PRIMARY;
		else if (iNext == ST_PRIMARY) iNext = ST_SECONDARY;
		else if (iNext == ST_SECONDARY) iNext = ST_EQUIPMENT;
		else break;
		
		if (GetStageCount(iNext) > 0) return iNext;
	}
	return ST_NONE;
}

GetPrevValidStage(iCurrentStage) {
	new iPrev = iCurrentStage;
	for (new i = 0; i < 3; i++) {
		if (iPrev == ST_EQUIPMENT) iPrev = ST_SECONDARY;
		else if (iPrev == ST_SECONDARY) iPrev = ST_PRIMARY;
		else break;
		
		if (GetStageCount(iPrev) > 0) return iPrev;
	}
	return ST_NONE;
}

public GetStageName(iStage, szName[], iLen) {
	if (iStage == ST_PRIMARY) copy(szName, iLen, "Primary");
	else if (iStage == ST_SECONDARY) copy(szName, iLen, "Secondary");
	else if (iStage == ST_EQUIPMENT) copy(szName, iLen, "Equipment");
	else copy(szName, iLen, "None");
}

stock Util_ScreenFlash(id, iRed, iGreen, iBlue, iAlpha) {
	static msgScreenFade; if (!msgScreenFade) msgScreenFade = get_user_msgid("ScreenFade");
	message_begin(MSG_ONE_UNRELIABLE, msgScreenFade, {0,0,0}, id);
	write_short(1<<10); write_short(1<<10); write_short(0x0001);
	write_byte(iRed); write_byte(iGreen); write_byte(iBlue); write_byte(iAlpha);
	message_end();
}
