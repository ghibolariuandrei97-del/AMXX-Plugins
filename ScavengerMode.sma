#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <engine>

#define PLUGIN  "Scavenger Mode"
#define VERSION "1.0"
#define AUTHOR  "Astafaresk"

new const g_szLootClass[] = "scavenger_item";
new const g_szHealthModel[] = "models/w_battery.mdl"; 
new const g_szMoneyModel[] = "models/w_antidote.mdl"; 

// Lista completa de arme CS 1.6
new const g_szWeaponNames[][] = {
    "weapon_ak47", "weapon_m4a1", "weapon_mp5navy", "weapon_awp", "weapon_famas", 
    "weapon_galil", "weapon_deagle", "weapon_usp", "weapon_glock18", "weapon_m3", 
    "weapon_xm1014", "weapon_scout", "weapon_p90", "weapon_aug", "weapon_sg552", 
    "weapon_g3sg1", "weapon_sg550", "weapon_m249", "weapon_tmp", "weapon_mac10", 
    "weapon_ump45", "weapon_p228", "weapon_elite", "weapon_fiveseven", 
    "weapon_hegrenade", "weapon_flashbang", "weapon_smokegrenade", "weapon_knife"
};

new const g_szWeaponModels[][] = {
    "models/w_ak47.mdl", "models/w_m4a1.mdl", "models/w_mp5.mdl", "models/w_awp.mdl", "models/w_famas.mdl",
    "models/w_galil.mdl", "models/w_deagle.mdl", "models/w_usp.mdl", "models/w_glock18.mdl", "models/w_m3.mdl",
    "models/w_xm1014.mdl", "models/w_scout.mdl", "models/w_p90.mdl", "models/w_aug.mdl", "models/w_sg552.mdl",
    "models/w_g3sg1.mdl", "models/w_sg550.mdl", "models/w_m249.mdl", "models/w_tmp.mdl", "models/w_mac10.mdl",
    "models/w_ump45.mdl", "models/w_p228.mdl", "models/w_elite.mdl", "models/w_fiveseven.mdl",
    "models/w_hegrenade.mdl", "models/w_flashbang.mdl", "models/w_smokegrenade.mdl", "models/w_knife.mdl"
};

new g_pLootDensity, g_pItemsPerPlayer, g_pReviveCost;

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);

    g_pLootDensity = register_cvar("amx_loot_density", "3"); 
    g_pItemsPerPlayer = register_cvar("amx_loot_per_player", "3");
    g_pReviveCost = register_cvar("amx_revive_cost", "9000");

    RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawn_Post", 1);
    RegisterHookChain(RG_CSGameRules_RestartRound, "OnRoundRestart", 0);
    
    register_clcmd("say /rev", "CmdRevive");
    register_clcmd("say_team /rev", "CmdRevive");

    new const szBuyCommands[][] = { "buy", "client_buy_open", "buyammo1", "buyammo2", "cl_autobuy", "cl_rebuy" };
    for(new i = 0; i < sizeof(szBuyCommands); i++) register_clcmd(szBuyCommands[i], "BlockCommand");

    register_touch(g_szLootClass, "player", "OnLootTouch");
}

public plugin_precache() {
    precache_model(g_szHealthModel);
    precache_model(g_szMoneyModel);
    precache_model("models/w_c4.mdl");
    for(new i = 0; i < sizeof(g_szWeaponModels); i++) precache_model(g_szWeaponModels[i]);
}

public BlockCommand(id) {
    client_print(id, print_center, "Magazinul este BLOCAT!");
    return PLUGIN_HANDLED;
}

public CmdRevive(id) {
    if (is_user_alive(id)) {
        client_print(id, print_chat, "[SCAVENGER] Esti deja in viata!");
        return PLUGIN_HANDLED;
    }

    new iMoney = get_member(id, m_iAccount);
    new iCost = get_pcvar_num(g_pReviveCost);

    if (iMoney < iCost) {
        client_print(id, print_chat, "[SCAVENGER] Nu ai $%d pentru reinviere!", iCost);
        return PLUGIN_HANDLED;
    }

    rg_add_account(id, -iCost);
    rg_round_respawn(id);
    client_print(id, print_chat, "[SCAVENGER] Ai fost reinviat pentru $%d!", iCost);
    return PLUGIN_HANDLED;
}

public OnRoundRestart() {
    // Stergere Buyzone
    new iBuyZone = -1;
    while ((iBuyZone = find_ent_by_class(iBuyZone, "func_buyzone"))) {
        if (is_valid_ent(iBuyZone)) entity_set_origin(iBuyZone, Float:{9999.0, 9999.0, 9999.0});
    }
    set_member_game(m_bMapHasBuyZone, false);

    // Mesaj HUD Global
    set_hudmessage(255, 255, 255, -1.0, 0.2, 0, 6.0, 10.0);
    show_hudmessage(0, "Scavenger Mode: Cautati arme pe jos!");

    // Curatare loot
    new iEnt = -1;
    while ((iEnt = find_ent_by_class(iEnt, g_szLootClass))) {
        if (is_valid_ent(iEnt)) rg_remove_entity(iEnt);
    }

    set_task(0.6, "GenerateMapLoot");
}

public OnPlayerSpawn_Post(const iId) {
    if (!is_user_alive(iId)) return;

    rg_remove_all_items(iId);
    
    // Task pentru a sterge C4 (uneori jocul il da dupa spawn)
    set_task(0.1, "TaskRemoveC4", iId);
}

public TaskRemoveC4(id) {
    if (is_user_connected(id)) {
        rg_remove_item(id, "weapon_c4");
    }
}

public GenerateMapLoot() {
    new iTotalItems = (get_pcvar_num(g_pLootDensity) * 15) + (get_playersnum() * get_pcvar_num(g_pItemsPerPlayer)); 

    SpawnLootItem(-1); // Spawn C4

    for (new i = 0; i < iTotalItems; i++) {
        new iRand = random_num(1, 100);
        if (iRand <= 75) SpawnLootItem(random_num(0, charsmax(g_szWeaponNames)));
        else if (iRand <= 90) SpawnCustomLoot(100); // Bani
        else SpawnCustomLoot(200); // HP
    }
}

public OnLootTouch(iEnt, iId) {
    if (!is_user_alive(iId)) return;

    new iVal = get_entvar(iEnt, var_iuser1);

    if (iVal == 100) { // BANI
        rg_add_account(iId, random_num(1000, 3000), AS_ADD);
        client_print(iId, print_center, "Ai gasit bani!");
        emit_sound(iId, CHAN_ITEM, "items/gunpickup2.wav", 1.0, ATTN_NORM, 0, PITCH_NORM);
        rg_remove_entity(iEnt);
        return;
    } 
    
    if (iVal == 200) { // HP
        new Float:fHP = get_entvar(iId, var_health);
        if (fHP >= 100.0) return; // BLOCARE: Nu poate lua daca are 100 HP
        
        set_entvar(iId, var_health, floatmin(100.0, fHP + 35.0));
        client_print(iId, print_center, "Ai gasit o trusa medicala!");
        emit_sound(iId, CHAN_ITEM, "items/smallmedkit1.wav", 1.0, ATTN_NORM, 0, PITCH_NORM);
        rg_remove_entity(iEnt);
        return;
    }

    if (iVal == 300) { // C4
        if (get_member(iId, m_iTeam) == TEAM_TERRORIST) {
            rg_give_item(iId, "weapon_c4");
            client_print(iId, print_chat, "[SCAVENGER] Ai gasit BOMBA!");
            rg_remove_entity(iEnt);
        }
        return;
    }

    // ARME
    new szWpnName[32];
    copy(szWpnName, charsmax(szWpnName), g_szWeaponNames[iVal]);
    new iSlot = get_weapon_slot(szWpnName);
    
    if (iSlot == 1 || iSlot == 2) {
        if (get_member(iId, m_rgpPlayerItems, iSlot) != NULLENT) {
            client_print(iId, print_center, "Slot ocupat! Arunca arma actuala (G).");
            return; 
        }
    }

    rg_give_item(iId, szWpnName);
    
    if (equal(szWpnName, "weapon_hegrenade") || equal(szWpnName, "weapon_flashbang") || equal(szWpnName, "weapon_smokegrenade")) {
        rg_set_user_bpammo(iId, WeaponIdType:rg_get_weapon_info(szWpnName, WI_ID), 1); 
    } else if (!equal(szWpnName, "weapon_knife")) {
        rg_set_user_bpammo(iId, WeaponIdType:rg_get_weapon_info(szWpnName, WI_ID), 60); 
    }

    client_print(iId, print_center, "Ai gasit: %s", szWpnName[7]);
    emit_sound(iId, CHAN_ITEM, "items/gunpickup2.wav", 1.0, ATTN_NORM, 0, PITCH_NORM);
    rg_remove_entity(iEnt);
}

stock get_weapon_slot(const szName[]) {
    if (equal(szName, "weapon_deagle") || equal(szName, "weapon_usp") || equal(szName, "weapon_glock18") || 
        equal(szName, "weapon_p228") || equal(szName, "weapon_elite") || equal(szName, "weapon_fiveseven")) return 2;
    if (equal(szName, "weapon_knife") || equal(szName, "weapon_hegrenade") || 
        equal(szName, "weapon_flashbang") || equal(szName, "weapon_smokegrenade")) return 0;
    return 1; 
}

stock SpawnLootItem(iWpnIdx) {
    new Float:fOrigin[3];
    if (FindSurface(fOrigin)) {
        new iEnt = rg_create_entity("info_target");
        if (is_valid_ent(iEnt)) {
            set_entvar(iEnt, var_classname, g_szLootClass);
            set_entvar(iEnt, var_movetype, MOVETYPE_TOSS);
            set_entvar(iEnt, var_solid, SOLID_TRIGGER);
            if (iWpnIdx == -1) {
                set_entvar(iEnt, var_iuser1, 300); 
                engfunc(EngFunc_SetModel, iEnt, "models/w_c4.mdl");
                util_set_rendering(iEnt, kRenderFxGlowShell, 255, 255, 0, 20); 
            } else {
                set_entvar(iEnt, var_iuser1, iWpnIdx); 
                engfunc(EngFunc_SetModel, iEnt, g_szWeaponModels[iWpnIdx]);
                util_set_rendering(iEnt, kRenderFxGlowShell, 255, 255, 255, 10); 
            }
            engfunc(EngFunc_SetOrigin, iEnt, fOrigin);
        }
    }
}

stock SpawnCustomLoot(iType) {
    new Float:fOrigin[3];
    if (FindSurface(fOrigin)) {
        new iEnt = rg_create_entity("info_target");
        if (is_valid_ent(iEnt)) {
            set_entvar(iEnt, var_classname, g_szLootClass);
            set_entvar(iEnt, var_movetype, MOVETYPE_TOSS);
            set_entvar(iEnt, var_solid, SOLID_TRIGGER);
            set_entvar(iEnt, var_iuser1, iType); 
            engfunc(EngFunc_SetModel, iEnt, iType == 100 ? g_szMoneyModel : g_szHealthModel);
            engfunc(EngFunc_SetOrigin, iEnt, fOrigin);
            if (iType == 100) util_set_rendering(iEnt, kRenderFxGlowShell, 0, 255, 0, 20); 
            else util_set_rendering(iEnt, kRenderFxGlowShell, 255, 0, 0, 20); 
        }
    }
}

stock bool:FindSurface(Float:fOutOrigin[3]) {
    new iAttempts = 0;
    while (iAttempts < 200) {
        iAttempts++;
        fOutOrigin[0] = random_float(-2500.0, 2500.0);
        fOutOrigin[1] = random_float(-2500.0, 2500.0);
        fOutOrigin[2] = random_float(-400.0, 800.0);
        new Float:fStart[3], Float:fEnd[3];
        fStart[0] = fOutOrigin[0]; fStart[1] = fOutOrigin[1]; fStart[2] = fOutOrigin[2] + 400.0;
        fEnd[0] = fOutOrigin[0]; fEnd[1] = fOutOrigin[1]; fEnd[2] = fOutOrigin[2] - 800.0;
        new iTrace = create_tr2();
        engfunc(EngFunc_TraceLine, fStart, fEnd, IGNORE_MONSTERS, 0, iTrace);
        new Float:fFraction; get_tr2(iTrace, TR_flFraction, fFraction);
        if (fFraction < 1.0) {
            get_tr2(iTrace, TR_vecEndPos, fOutOrigin);
            free_tr2(iTrace);
            if (engfunc(EngFunc_PointContents, fOutOrigin) == CONTENTS_EMPTY) {
                fOutOrigin[2] += 8.0;
                return true;
            }
        } else free_tr2(iTrace);
    }
    return false;
}

stock util_set_rendering(iEnt, iFx, iR, iG, iB, iAmount) {
    new Float:fColor[3]; fColor[0] = float(iR); fColor[1] = float(iG); fColor[2] = float(iB);
    set_entvar(iEnt, var_renderfx, iFx);
    set_entvar(iEnt, var_rendercolor, fColor);
    set_entvar(iEnt, var_rendermode, kRenderNormal); 
    set_entvar(iEnt, var_renderamt, float(iAmount));
}
