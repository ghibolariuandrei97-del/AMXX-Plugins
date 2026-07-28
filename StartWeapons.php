#include <amxmodx>
#include <fun>
#include <cstrike>
#include <engine>
#include <hamsandwich>

#define PLUGIN "Meniu Arme Gratuite ZXC"
#define VERSION "1.1"
#define AUTHOR "AMXX Daeva Astarasefk"

// Sloturi pentru a verifica si sterge armele vechi
const PRIMARY_WEAPONS_BIT_SUM = (1<<CSW_SCOUT)|(1<<CSW_XM1014)|(1<<CSW_MAC10)|(1<<CSW_AUG)|(1<<CSW_UMP45)|(1<<CSW_SG550)|(1<<CSW_GALIL)|(1<<CSW_FAMAS)|(1<<CSW_AWP)|(1<<CSW_MP5NAVY)|(1<<CSW_M249)|(1<<CSW_M3)|(1<<CSW_M4A1)|(1<<CSW_TMP)|(1<<CSW_G3SG1)|(1<<CSW_SG552)|(1<<CSW_AK47)|(1<<CSW_P90);
const SECONDARY_WEAPONS_BIT_SUM = (1<<CSW_P228)|(1<<CSW_ELITE)|(1<<CSW_FIVESEVEN)|(1<<CSW_USP)|(1<<CSW_GLOCK18)|(1<<CSW_DEAGLE);

new Float:g_RoundStartTime;
new g_pCvarMenuTime;

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // Inregistram comenzile de radio
    register_clcmd("radio1", "CmdMenuPrimare");
    register_clcmd("radio2", "CmdMenuSecundare");
    register_clcmd("radio3", "CmdMenuItems");

    // Event pentru a afla cand incepe runda (pentru countdown)
    register_event("HLTV", "Event_RoundStart", "a", "1=0", "2=0");
    
    // Inregistram Spawn-ul
    RegisterHam(Ham_Spawn, "player", "fw_PlayerSpawn", 1);

    // CVAR pentru timpul de cumparare (implicit 20 secunde)
    g_pCvarMenuTime = register_cvar("amx_weapons_time", "20");
}

public Event_RoundStart() {
    g_RoundStartTime = get_gametime();
}

public fw_PlayerSpawn(id) {
    if(!is_user_alive(id)) return;

    // Afisam mesajul HUD doar la spawn
    set_hudmessage(0, 255, 127, -1.0, 0.20, 0, 6.0, 8.0, 0.1, 0.2, -1);
    show_hudmessage(id, "🎁 ECHIPAMENT GRATUIT 🎁^n[Z] Arme Primare | [X] Pistoale | [C] Utilitare^nAlege-ti arsenalul in primele %d secunde!", get_pcvar_num(g_pCvarMenuTime));
}

// Functie pentru a verifica daca timpul a expirat
bool:CheckTime(id) {
    new Float:fTimeLimit = get_pcvar_float(g_pCvarMenuTime);
    if(get_gametime() - g_RoundStartTime > fTimeLimit) {
        client_print(id, print_center, "Timpul de echipare a expirat! (%d secunde)", floatround(fTimeLimit));
        return false;
    }
    return true;
}

// -----------------------------------------
// MENIU RADIO 1 - ARME PRIMARE
// -----------------------------------------
public CmdMenuPrimare(id) {
    if(!is_user_alive(id) || !CheckTime(id)) return PLUGIN_HANDLED;

    new menu = menu_create("\yAlege o Arma Primara \r(Gratis):", "HandlePrimare");

    menu_additem(menu, "AK-47 Kalashnikov", "1");
    menu_additem(menu, "M4A1 Carbine", "2");
    menu_additem(menu, "AWP Magnum Sniper", "3");
    menu_additem(menu, "FAMAS Clarion", "4");
    menu_additem(menu, "Galil IMI", "5");
    menu_additem(menu, "Krieg 552", "6");
    menu_additem(menu, "Bullpup AUG", "7");
    menu_additem(menu, "Scout Sniper", "8");
    menu_additem(menu, "MP5 Navy", "9");
    menu_additem(menu, "M249 MachineGun", "10");

    // Aici era eroarea: MPROP_EXITNAME in loc de MEXIT_ALL
    menu_setprop(menu, MPROP_EXITNAME, "Inchide");
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public HandlePrimare(id, menu, item) {
    if(item == MENU_EXIT || !is_user_alive(id)) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    if(!CheckTime(id)) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    drop_weapons(id, 1); 

    switch(item) {
        case 0: give_user_weapon(id, CSW_AK47, 30, 90);
        case 1: give_user_weapon(id, CSW_M4A1, 30, 90);
        case 2: give_user_weapon(id, CSW_AWP, 10, 30);
        case 3: give_user_weapon(id, CSW_FAMAS, 25, 90);
        case 4: give_user_weapon(id, CSW_GALIL, 35, 90);
        case 5: give_user_weapon(id, CSW_SG552, 30, 90);
        case 6: give_user_weapon(id, CSW_AUG, 30, 90);
        case 7: give_user_weapon(id, CSW_SCOUT, 10, 90);
        case 8: give_user_weapon(id, CSW_MP5NAVY, 30, 120);
        case 9: give_user_weapon(id, CSW_M249, 100, 200);
    }
    
    client_print(id, print_center, "Ai primit arma primara!");
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// -----------------------------------------
// MENIU RADIO 2 - PISTOALE
// -----------------------------------------
public CmdMenuSecundare(id) {
    if(!is_user_alive(id) || !CheckTime(id)) return PLUGIN_HANDLED;

    new menu = menu_create("\yAlege un Pistol \r(Gratis):", "HandleSecundare");

    menu_additem(menu, "Desert Eagle", "1");
    menu_additem(menu, "USP .45 Tactical", "2");
    menu_additem(menu, "Glock 18 Select Fire", "3");
    menu_additem(menu, "SIG P228", "4");
    menu_additem(menu, "Five-SeveN", "5");
    menu_additem(menu, "Dual Elites", "6");

    menu_setprop(menu, MPROP_EXITNAME, "Inchide");
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public HandleSecundare(id, menu, item) {
    if(item == MENU_EXIT || !is_user_alive(id)) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    if(!CheckTime(id)) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    drop_weapons(id, 2);

    switch(item) {
        case 0: give_user_weapon(id, CSW_DEAGLE, 7, 35);
        case 1: give_user_weapon(id, CSW_USP, 12, 100);
        case 2: give_user_weapon(id, CSW_GLOCK18, 20, 120);
        case 3: give_user_weapon(id, CSW_P228, 13, 52);
        case 4: give_user_weapon(id, CSW_FIVESEVEN, 20, 100);
        case 5: give_user_weapon(id, CSW_ELITE, 30, 120);
    }

    client_print(id, print_center, "Ai primit pistolul!");
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// -----------------------------------------
// MENIU RADIO 3 - UTILITIES
// -----------------------------------------
public CmdMenuItems(id) {
    if(!is_user_alive(id) || !CheckTime(id)) return PLUGIN_HANDLED;

    new menu = menu_create("\yEchipament Tactic \r(Gratis):", "HandleItems");

    menu_additem(menu, "Pachet Grenazi (HE, 2xF, Smoke)", "1");
    menu_additem(menu, "Armura + Coif (Vest/Helm)", "2");
    menu_additem(menu, "Defuse Kit (Doar CT)", "3");
    menu_additem(menu, "Pachet Complet (Toate cele de sus)", "4");

    menu_setprop(menu, MPROP_EXITNAME, "Inchide");
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public HandleItems(id, menu, item) {
    if(item == MENU_EXIT || !is_user_alive(id)) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    if(!CheckTime(id)) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    switch(item) {
        case 0: {
            give_user_weapon(id, CSW_HEGRENADE, 1, 1);
            give_user_weapon(id, CSW_FLASHBANG, 2, 2);
            give_user_weapon(id, CSW_SMOKEGRENADE, 1, 1);
        }
        case 1: cs_set_user_armor(id, 100, CS_ARMOR_VESTHELM);
        case 2: if(get_user_team(id) == 2) cs_set_user_defuse(id, 1);
        case 3: {
            give_user_weapon(id, CSW_HEGRENADE, 1, 1);
            give_user_weapon(id, CSW_FLASHBANG, 2, 2);
            give_user_weapon(id, CSW_SMOKEGRENADE, 1, 1);
            cs_set_user_armor(id, 100, CS_ARMOR_VESTHELM);
            if(get_user_team(id) == 2) cs_set_user_defuse(id, 1);
        }
    }

    client_print(id, print_center, "Echipament primit!");
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// -----------------------------------------
// FUNCTIE DROP
// -----------------------------------------
stock drop_weapons(id, slot) {
    new weapons[32], num;
    get_user_weapons(id, weapons, num);
    for (new i = 0; i < num; i++) {
        new weaponid = weapons[i];
        if ((slot == 1 && ((1<<weaponid) & PRIMARY_WEAPONS_BIT_SUM)) ||
            (slot == 2 && ((1<<weaponid) & SECONDARY_WEAPONS_BIT_SUM))) {
            new wname[32];
            get_weaponname(weaponid, wname, charsmax(wname));
            engclient_cmd(id, "drop", wname);
        }
    }
}

// -----------------------------------------
// STOCK give_user_weapon
// -----------------------------------------
stock give_user_weapon( index , iWeaponTypeID , iClip=0 , iBPAmmo=0 , szWeapon[]="" , maxchars=0 )
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
