#include <amxmodx>
#include <amxmisc>
#include <fakemeta>

#define PLUGIN_NAME "VIP System"
#define PLUGIN_VERSION "2.0"
#define PLUGIN_AUTHOR "CopilotDev"

#define MAX_PLAYERS 32
#define MAX_VIP_LEVELS 10
#define CONFIG_DIR "addons/amxmodx/configs/vip"

// VIP Level IDs
enum {
	VIP_NONE = 0,
	VIP_IRON,
	VIP_BRONZE,
	VIP_SILVER,
	VIP_GOLD,
	VIP_PLATINUM,
	VIP_DIAMOND,
	VIP_MASTER,
	VIP_LEGEND
};

// VIP Data Structure
enum VIP_DATA {
	VIP_NAME[64],
	VIP_HEALTH,
	VIP_ARMOR,
	VIP_MONEY,
	VIP_WEAPONS[256],
	bool:VIP_ENABLED
};

new g_aVIPData[MAX_VIP_LEVELS][VIP_DATA];
new g_iPlayerVIPLevel[MAX_PLAYERS + 1];
new g_iVIPLevelCount = 0;

public plugin_init() {
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	
	register_event("HLTV", "event_round_start", "a");
	register_logevent("event_round_end", 2, "1=Round_End");
	
	register_clcmd("say /vip", "cmd_vip_menu");
	register_clcmd("say /vipmenu", "cmd_vip_menu");
	register_clcmd("say /vipinfo", "cmd_vip_info");
	register_clcmd("say /myvipl", "cmd_vip_info");
	
	// Load configurations
	load_vip_levels_config();
	load_vip_players_config();
	
	set_task(5.0, "task_check_vip_on_spawn", _, _, _, "b");
	set_task(15.0, "task_give_vip_money", _, _, _, "b");
	
	// Create config directory if it doesn't exist
	if(!dir_exists(CONFIG_DIR)) {
		mkdir(CONFIG_DIR);
	}
}

public client_connect(id) {
	g_iPlayerVIPLevel[id] = VIP_NONE;
	check_player_vip_level(id);
}

public client_putinserver(id) {
	new szName[32];
	get_user_name(id, szName, charsmax(szName));
	check_player_vip_level(id);
	
	if(g_iPlayerVIPLevel[id] > VIP_NONE) {
		new szMessage[256];
		formatex(szMessage, charsmax(szMessage), "%s has joined the server with %s privileges!", 
			szName, g_aVIPData[g_iPlayerVIPLevel[id]][VIP_NAME]);
		print_server_message(szMessage);
	}
}

check_player_vip_level(id) {
	new szPlayerName[32], szVIPName[32];
	get_user_name(id, szPlayerName, charsmax(szPlayerName));
	
	// Reset VIP level
	g_iPlayerVIPLevel[id] = VIP_NONE;
	
	// Check in players config file
	new szConfigPath[256];
	formatex(szConfigPath, charsmax(szConfigPath), "%s/vip_players.ini", CONFIG_DIR);
	
	if(file_exists(szConfigPath)) {
		new iFile = fopen(szConfigPath, "rt");
		new szBuffer[256], szName[32], szLevel[32];
		
		while(!feof(iFile)) {
			fgets(iFile, szBuffer, charsmax(szBuffer));
			
			// Skip empty lines and comments
			if(!szBuffer[0] || szBuffer[0] == ';' || szBuffer[0] == '/') continue;
			
			// Parse line: PLAYER_NAME   VIP_LEVEL
			if(sscanf(szBuffer, "s^t^ts", szName, szLevel) == 2) {
				if(equal(szName, szPlayerName)) {
					// Find matching VIP level
					for(new i = 1; i <= g_iVIPLevelCount; i++) {
						if(equal(szLevel, g_aVIPData[i][VIP_NAME])) {
							g_iPlayerVIPLevel[id] = i;
							break;
						}
					}
					break;
				}
			}
		}
		
		fclose(iFile);
	}
}

load_vip_levels_config() {
	new szConfigPath[256];
	formatex(szConfigPath, charsmax(szConfigPath), "%s/vip_levels.ini", CONFIG_DIR);
	
	if(!file_exists(szConfigPath)) {
		// Create default config if it doesn't exist
		create_default_vip_levels_config(szConfigPath);
		server_print("[VIP] Created default vip_levels.ini file at: %s", szConfigPath);
		return;
	}
	
	new iFile = fopen(szConfigPath, "rt");
	new szBuffer[512], szVIPName[64], szWeapons[256];
	new iHealth, iArmor, iMoney;
	
	g_iVIPLevelCount = 0;
	
	while(!feof(iFile) && g_iVIPLevelCount < MAX_VIP_LEVELS) {
		fgets(iFile, szBuffer, charsmax(szBuffer));
		
		// Skip empty lines and comments
		if(!szBuffer[0] || szBuffer[0] == ';' || szBuffer[0] == '/') continue;
		
		// Parse: VIP_NAME | HEALTH | ARMOR | MONEY | WEAPONS
		if(sscanf(szBuffer, "s^|^i^|^i^|^i^|^s", szVIPName, iHealth, iArmor, iMoney, szWeapons) == 5) {
			g_iVIPLevelCount++;
			
			copy(g_aVIPData[g_iVIPLevelCount][VIP_NAME], charsmax(g_aVIPData[][VIP_NAME]), szVIPName);
			g_aVIPData[g_iVIPLevelCount][VIP_HEALTH] = iHealth;
			g_aVIPData[g_iVIPLevelCount][VIP_ARMOR] = iArmor;
			g_aVIPData[g_iVIPLevelCount][VIP_MONEY] = iMoney;
			copy(g_aVIPData[g_iVIPLevelCount][VIP_WEAPONS], charsmax(g_aVIPData[][VIP_WEAPONS]), szWeapons);
			g_aVIPData[g_iVIPLevelCount][VIP_ENABLED] = true;
			
			server_print("[VIP] Loaded: %s (Health: %d, Armor: %d, Money: %d, Weapons: %s)", 
				szVIPName, iHealth, iArmor, iMoney, szWeapons);
		}
	}
	
	fclose(iFile);
	server_print("[VIP] Loaded %d VIP levels", g_iVIPLevelCount);
}

load_vip_players_config() {
	new szConfigPath[256];
	formatex(szConfigPath, charsmax(szConfigPath), "%s/vip_players.ini", CONFIG_DIR);
	
	if(!file_exists(szConfigPath)) {
		// Create default config if it doesn't exist
		create_default_vip_players_config(szConfigPath);
		server_print("[VIP] Created default vip_players.ini file at: %s", szConfigPath);
		return;
	}
	
	server_print("[VIP] Loaded vip_players.ini successfully");
}

create_default_vip_levels_config(szPath[]) {
	new iFile = fopen(szPath, "wt");
	
	fprintf(iFile, "; VIP Levels Configuration^n");
	fprintf(iFile, "; Format: VIP_NAME | HEALTH | ARMOR | MONEY | WEAPONS^n");
	fprintf(iFile, "; Weapons example: 'glock,knife' or 'ak47,deagle,knife' (separate with comma)^n");
	fprintf(iFile, "; Leave empty for no weapons^n^n");
	
	fprintf(iFile, "VIP_IRON | 10 | 10 | 500 | knife^n");
	fprintf(iFile, "VIP_BRONZE | 15 | 15 | 750 | knife^n");
	fprintf(iFile, "VIP_SILVER | 20 | 20 | 1000 | glock,knife^n");
	fprintf(iFile, "VIP_GOLD | 30 | 30 | 1500 | ak47,deagle,knife^n");
	fprintf(iFile, "VIP_PLATINUM | 40 | 40 | 2000 | ak47,deagle,knife^n");
	fprintf(iFile, "VIP_DIAMOND | 50 | 50 | 2500 | ak47,m4a1,deagle,knife^n");
	fprintf(iFile, "VIP_MASTER | 75 | 75 | 3500 | ak47,m4a1,deagle,knife^n");
	fprintf(iFile, "VIP_LEGEND | 100 | 100 | 5000 | ak47,m4a1,deagle,awp,knife^n");
	
	fclose(iFile);
}

create_default_vip_players_config(szPath[]) {
	new iFile = fopen(szPath, "wt");
	
	fprintf(iFile, "; VIP Players Configuration^n");
	fprintf(iFile, "; Format: PLAYER_NAME   VIP_LEVEL^n");
	fprintf(iFile, "; Example: Player123   VIP_GOLD^n");
	fprintf(iFile, "; Note: Use exact player names and VIP level names from vip_levels.ini^n^n");
	
	fprintf(iFile, "; PlayerName   VIP_LEVEL^n");
	fprintf(iFile, "; Add your VIP players below^n");
	
	fclose(iFile);
}

public event_round_start() {
	for(new i = 1; i <= 32; i++) {
		if(is_user_connected(i)) {
			check_player_vip_level(i);
		}
	}
}

public task_check_vip_on_spawn() {
	for(new i = 1; i <= 32; i++) {
		if(is_user_alive(i)) {
			apply_vip_benefits(i);
		}
	}
}

apply_vip_benefits(id) {
	new iVIPLevel = g_iPlayerVIPLevel[id];
	
	if(iVIPLevel == VIP_NONE) return;
	
	// Apply health bonus
	new iHealth = get_user_health(id);
	new iNewHealth = iHealth + g_aVIPData[iVIPLevel][VIP_HEALTH];
	if(iNewHealth > 255) iNewHealth = 255;
	set_user_health(id, iNewHealth);
	
	// Apply armor bonus
	new iArmor = pev(id, pev_armorvalue);
	new iNewArmor = iArmor + g_aVIPData[iVIPLevel][VIP_ARMOR];
	if(iNewArmor > 255) iNewArmor = 255;
	set_pev(id, pev_armorvalue, float(iNewArmor));
	
	// Give weapons if specified
	if(g_aVIPData[iVIPLevel][VIP_WEAPONS][0] != 0) {
		give_vip_weapons(id, g_aVIPData[iVIPLevel][VIP_WEAPONS]);
	}
}

give_vip_weapons(id, szWeapons[]) {
	new szWeaponList[10][32], iWeaponCount = 0;
	new szBuffer[256];
	copy(szBuffer, charsmax(szBuffer), szWeapons);
	
	// Split weapons by comma
	iWeaponCount = split(szBuffer, szWeaponList, charsmax(szWeaponList), charsmax(szWeaponList[]), ',');
	
	for(new i = 0; i < iWeaponCount; i++) {
		trim(szWeaponList[i]);
		
		switch_weapon_handler(id, szWeaponList[i]);
	}
}

switch_weapon_handler(id, szWeapon[]) {
	switch(szWeapon[0]) {
		case 'k': {
			if(equal(szWeapon, "knife")) give_item(id, "weapon_knife");
		}
		case 'g': {
			if(equal(szWeapon, "glock")) {
				give_item(id, "weapon_glock18");
				cs_set_user_bpammo(id, CSW_GLOCK18, 120);
			}
		}
		case 'a': {
			if(equal(szWeapon, "ak47")) {
				give_item(id, "weapon_ak47");
				cs_set_user_bpammo(id, CSW_AK47, 90);
			}
			else if(equal(szWeapon, "awp")) {
				give_item(id, "weapon_awp");
				cs_set_user_bpammo(id, CSW_AWP, 30);
			}
		}
		case 'm': {
			if(equal(szWeapon, "m4a1")) {
				give_item(id, "weapon_m4a1");
				cs_set_user_bpammo(id, CSW_M4A1, 90);
			}
		}
		case 'd': {
			if(equal(szWeapon, "deagle")) {
				give_item(id, "weapon_deagle");
				cs_set_user_bpammo(id, CSW_DEAGLE, 35);
			}
		}
	}
}

public task_give_vip_money() {
	for(new i = 1; i <= 32; i++) {
		if(is_user_connected(i) && is_user_alive(i)) {
			new iVIPLevel = g_iPlayerVIPLevel[i];
			
			if(iVIPLevel > VIP_NONE) {
				new iMoney = cs_get_user_money(i);
				new iNewMoney = iMoney + g_aVIPData[iVIPLevel][VIP_MONEY];
				
				if(iNewMoney > 16000) iNewMoney = 16000;
				
				cs_set_user_money(i, iNewMoney);
			}
		}
	}
}

public event_round_end() {
	// Additional logic can be added here if needed
}

public cmd_vip_menu(id) {
	show_vip_menu(id);
	return PLUGIN_HANDLED;
}

public cmd_vip_info(id) {
	new iVIPLevel = g_iPlayerVIPLevel[id];
	
	console_print(id, "^n=== VIP SYSTEM INFO ===");
	console_print(id, "Your VIP Level: %s", g_aVIPData[iVIPLevel][VIP_NAME]);
	console_print(id, "^n--- Your VIP Benefits ---");
	console_print(id, "Health Bonus: +%d HP", g_aVIPData[iVIPLevel][VIP_HEALTH]);
	console_print(id, "Armor Bonus: +%d AP", g_aVIPData[iVIPLevel][VIP_ARMOR]);
	console_print(id, "Money per Round: +$%d", g_aVIPData[iVIPLevel][VIP_MONEY]);
	console_print(id, "Weapons: %s", g_aVIPData[iVIPLevel][VIP_WEAPONS]);
	console_print(id, "=======================^n");
	
	return PLUGIN_HANDLED;
}

show_vip_menu(id) {
	new iVIPLevel = g_iPlayerVIPLevel[id];
	new szMenu[2048];
	new iLen;
	
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\yVIP SYSTEM MENU\R%s^n", g_aVIPData[iVIPLevel][VIP_NAME]);
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n");
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\w1. \yYour VIP Info^n");
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\w2. \yAvailable VIP Levels^n");
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\w3. \yYour Benefits^n");
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n");
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\w0. \yExit^n");
	
	show_motd(id, szMenu, "VIP Menu");
}

print_server_message(szMessage[]) {
	new iPlayers[32], iCount;
	get_players(iPlayers, iCount);
	
	for(new i = 0; i < iCount; i++) {
		client_print(iPlayers[i], print_chat, "%s", szMessage);
	}
}

// Stock function to split string
stock split(szText[], szParts[][32], iMaxParts, iMaxPartLen, szDelim[] = ",") {
	new iLen = strlen(szText);
	new iPartCount = 0;
	new iStart = 0;
	new iDelimLen = strlen(szDelim);
	
	for(new i = 0; i <= iLen && iPartCount < iMaxParts; i++) {
		if(i == iLen || equali(szText[i], szDelim, iDelimLen)) {
			new iPartLen = i - iStart;
			if(iPartLen > 0) {
				copy(szParts[iPartCount], iMaxPartLen, szText[iStart]);
				szParts[iPartCount][iPartLen] = 0;
				iPartCount++;
			}
			iStart = i + iDelimLen;
			i += iDelimLen - 1;
		}
	}
	
	return iPartCount;
}

stock trim(szText[]) {
	new iLen = strlen(szText) - 1;
	while(iLen >= 0 && (szText[iLen] == ' ' || szText[iLen] == 9)) {
		szText[iLen] = 0;
		iLen--;
	}
	
	new iStart = 0;
	while(szText[iStart] && (szText[iStart] == ' ' || szText[iStart] == 9)) {
		iStart++;
	}
	
	if(iStart > 0) {
		copy(szText, strlen(szText), szText[iStart]);
	}
}