#include <amxmodx>
#include <amxmisc>     
#include <cstrike>
#include <fun>
#include <nvault>
#include <engine>
#include <hamsandwich>

#define MAX_ITEMS 20             
#define MAX_MARKET_ITEMS 60      

enum _:ItemData {
    I_NAME[24],
    I_AMMO,
    I_PRICE,
    I_OWNER[24]
}

new g_PlayerPocket[33][MAX_ITEMS][ItemData]
new g_PlayerCount[33], g_PlayerMoney[33], g_SelectedSlot[33]
new g_MarketItems[MAX_MARKET_ITEMS][ItemData], g_MarketCount
new g_Vault

new const g_szValidWeapons[][] = { 
    "p228", "scout", "xm1014", "mac10", "aug", "elite", "fiveseven", 
    "ump45", "sg550", "galil", "famas", "usp", "glock18", "awp", 
    "mp5navy", "m249", "m3", "m4a1", "tmp", "g3sg1", "deagle", 
    "sg552", "ak47", "p90", "hegrenade", "flashbang", "smokegrenade"
}

public plugin_init() {
    register_plugin("Pocket AMXX", "1.0", "AIs")

    register_clcmd("say", "handle_say")
    register_clcmd("say_team", "handle_say")
    register_clcmd("POCKET_PRICE", "cmd_set_price")

    register_concmd("amx_cleanmarket", "cmd_clean_market", ADMIN_KICK, "- Sterge toate itemele din Market")

    g_Vault = nvault_open("pocket_system")
    set_task(1.0, "load_market")
}

public cmd_clean_market(id, level, cid) {
    if(!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED

    // Resetam numaratoarea la zero
    g_MarketCount = 0
    
    // Salvam noul status in nVault (golirea bazei de date)
    save_market()
    
    // Log si notificare
    new admin_name[32]
    get_user_name(id, admin_name, 31)
    
    client_print(0, print_chat, "[Admin] %s a golit intregul Market Global!", admin_name)
    console_print(id, "[Pocket] Market-ul a fost curatat cu succes.")
    
    return PLUGIN_HANDLED
}


public handle_say(id) {
    new args[192]; read_args(args, 191); remove_quotes(args)
    
    if(equal(args, "/pocket")) { cmd_pocket(id); return PLUGIN_HANDLED; }
    if(equal(args, "/market")) { cmd_market(id); return PLUGIN_HANDLED; }
    
    if(containi(args, "/store") == 0) {
        replace(args, 191, "/store", ""); trim(args)
        if(!args[0]) {
            client_print(id, print_chat, "[Pocket] Comenzi: /store <arma>, /store <suma>, /store pack sau /store help.")
            return PLUGIN_HANDLED
        }
        if(equal(args, "help")) { show_help_motd(id); return PLUGIN_HANDLED; }
        if(equal(args, "pack")) { logic_store_pack(id); return PLUGIN_HANDLED; }
        logic_store(id, args); return PLUGIN_HANDLED;
    }
    
    if(containi(args, "/donate") == 0) {
        replace(args, 191, "/donate", ""); trim(args)
        if(!args[0]) {
            client_print(id, print_chat, "[Pocket] Foloseste: /donate <item/suma> <nume_jucator>")
            return PLUGIN_HANDLED
        }
        logic_donate(id, args); return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE
}

// --- LOGICA POCKET HANDLER (Optiuni Item) ---
public pocket_handler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[10], dummy; menu_item_getinfo(menu, item, dummy, data, 9, _, _, _); menu_destroy(menu)
    
    if(equal(data, "money")) {
        if(!is_user_alive(id)) { client_print(id, print_chat, "[Pocket] Trebuie sa fii viu!"); return PLUGIN_HANDLED; }
        cs_set_user_money(id, cs_get_user_money(id) + g_PlayerMoney[id]); g_PlayerMoney[id] = 0; save_data(id); cmd_pocket(id)
    } else { 
        g_SelectedSlot[id] = str_to_num(data); 
        new sMenu = menu_create("\rOptiuni Item:", "opt_handler")
        menu_additem(sMenu, "Extrage", "1")
        menu_additem(sMenu, "Vinde la Market", "2")
        menu_additem(sMenu, "\ySterge Item \r(Atentie!)", "3") // Optiunea noua
        menu_display(id, sMenu); 
    }
    return PLUGIN_HANDLED
}

public opt_handler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6], dummy; menu_item_getinfo(menu, item, dummy, data, 5, _, _, _); menu_destroy(menu)
    new idx = g_SelectedSlot[id]
    
    switch(str_to_num(data)) {
        case 1: { // Extrage
            if(!is_user_alive(id)) { client_print(id, print_chat, "[Pocket] Trebuie sa fii viu!"); return PLUGIN_HANDLED; }
            new wName[32]; copy(wName, 31, g_PlayerPocket[id][idx][I_NAME])
            
            if(user_has_weapon(id, get_weaponid(wName)) && get_weaponid(wName) != CSW_HEGRENADE && get_weaponid(wName) != CSW_FLASHBANG) {
                client_print(id, print_chat, "[Pocket] Ai deja aceasta arma!"); cmd_pocket(id); return PLUGIN_HANDLED;
            }

            give_item(id, wName); cs_set_user_bpammo(id, get_weaponid(wName), g_PlayerPocket[id][idx][I_AMMO])
            remove_pocket_item(id, idx); save_data(id); cmd_pocket(id)
        }
        case 2: { // Market
            client_cmd(id, "messagemode POCKET_PRICE")
        }
        case 3: { // Sterge
            new wName[32]; copy(wName, 31, g_PlayerPocket[id][idx][I_NAME])
            remove_pocket_item(id, idx); save_data(id)
            client_print(id, print_chat, "[Pocket] Itemul %s a fost distrus definitiv.", wName[7])
            cmd_pocket(id) // Duce inapoi la meniu
        }
    }
    return PLUGIN_HANDLED
}

// --- LOGICA DONATE ---
public logic_donate(id, const args[]) {
    new argItem[32], argTarget[32]
    parse(args, argItem, 31, argTarget, 31)
    
    new target = cmd_target(id, argTarget, CMDTARGET_OBEY_IMMUNITY)
    if(!target) { client_print(id, print_chat, "[Pocket] Jucatorul nu a fost gasit."); return; }
    if(target == id) { client_print(id, print_chat, "[Pocket] Nu iti poti dona singur!"); return; }

    if(is_str_num(argItem)) {
        new amount = str_to_num(argItem)
        if(amount > 0 && cs_get_user_money(id) >= amount) {
            cs_set_user_money(id, cs_get_user_money(id) - amount)
            g_PlayerMoney[target] += amount
            save_data(target); save_data(id)
            client_print(id, print_chat, "[Pocket] I-ai donat %d$ lui %n.", amount, target)
        }
    } else {
        new full[32]; formatex(full, 31, (containi(argItem, "weapon_") == -1) ? "weapon_%s" : "%s", argItem)
        if(user_has_weapon(id, get_weaponid(full))) {
            if(g_PlayerCount[target] >= MAX_ITEMS) { client_print(id, print_chat, "[Pocket] Buzunar plin la destinatar!"); return; }
            copy(g_PlayerPocket[target][g_PlayerCount[target]][I_NAME], 23, full)
            g_PlayerPocket[target][g_PlayerCount[target]][I_AMMO] = cs_get_user_bpammo(id, get_weaponid(full))
            g_PlayerCount[target]++; ham_strip_weapon(id, full)
            save_data(target); save_data(id)
            client_print(id, print_chat, "[Pocket] I-ai trimis %s lui %n.", argItem, target)
        }
    }
}

// --- MARKET & OFFLINE SYSTEM ---
public market_handler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[10], dummy; menu_item_getinfo(menu, item, dummy, data, 9, _, _, _); 
    if(equal(data, "none")) { menu_destroy(menu); return PLUGIN_HANDLED; }
    
    new idx = str_to_num(data), price = g_MarketItems[idx][I_PRICE], wName[32]
    copy(wName, 31, g_MarketItems[idx][I_NAME])

    if(cs_get_user_money(id) < price) { client_print(id, print_chat, "[Market] Bani insuficienti!"); return PLUGIN_HANDLED; }
    if(user_has_weapon(id, get_weaponid(wName)) && get_weaponid(wName) != CSW_HEGRENADE && get_weaponid(wName) != CSW_FLASHBANG) {
        client_print(id, print_chat, "[Market] Ai deja aceasta arma!"); return PLUGIN_HANDLED;
    }

    cs_set_user_money(id, cs_get_user_money(id) - price)
    give_item(id, wName); cs_set_user_bpammo(id, get_weaponid(wName), g_MarketItems[idx][I_AMMO])
    add_offline_money(g_MarketItems[idx][I_OWNER], price)
    
    for(new i = idx; i < g_MarketCount - 1; i++) g_MarketItems[i] = g_MarketItems[i+1]
    g_MarketCount--; save_market(); menu_destroy(menu); cmd_market(id)
    return PLUGIN_HANDLED
}

stock add_offline_money(const ownerName[], amount) {
    new target = get_user_index(ownerName)
    if(target) { g_PlayerMoney[target] += amount; save_data(target); }
    else {
        new key[64], current; formatex(key, 63, "%s_MONEY", ownerName)
        current = nvault_get(g_Vault, key); current += amount
        new szVal[16]; num_to_str(current, szVal, 15); nvault_set(g_Vault, key, szVal)
    }
}

// --- LOGICA STORE & PACK ---
public logic_store_pack(id) {
    if(!is_user_alive(id)) return; new money = cs_get_user_money(id)
    if(money > 0) { g_PlayerMoney[id] += money; cs_set_user_money(id, 0); }
    for(new i = 0; i < sizeof(g_szValidWeapons); i++) {
        new full[32]; formatex(full, 31, "weapon_%s", g_szValidWeapons[i])
        if(user_has_weapon(id, get_weaponid(full)) && g_PlayerCount[id] < MAX_ITEMS) {
            g_PlayerPocket[id][g_PlayerCount[id]][I_AMMO] = cs_get_user_bpammo(id, get_weaponid(full))
            copy(g_PlayerPocket[id][g_PlayerCount[id]][I_NAME], 23, full)
            g_PlayerCount[id]++; ham_strip_weapon(id, full)
        }
    }
    save_data(id); client_print(id, print_chat, "[Pocket] Pack salvat cu succes!")
}

public logic_store(id, const arg[]) {
    if(is_str_num(arg)) {
        new val = str_to_num(arg); if(val > 0 && cs_get_user_money(id) >= val) {
            cs_set_user_money(id, cs_get_user_money(id) - val); g_PlayerMoney[id] += val; save_data(id)
            client_print(id, print_chat, "[Pocket] Ai depus %d$.", val)
        }
        return
    }
    new clean[32]; copy(clean, 31, arg); replace(clean, 31, "weapon_", "")
    new bool:ok = false; for(new i=0; i<sizeof(g_szValidWeapons); i++) if(equal(clean, g_szValidWeapons[i])) { ok = true; break; }
    if(ok) {
        new full[32]; formatex(full, 31, "weapon_%s", clean)
        if(user_has_weapon(id, get_weaponid(full)) && g_PlayerCount[id] < MAX_ITEMS) {
            copy(g_PlayerPocket[id][g_PlayerCount[id]][I_NAME], 23, full)
            g_PlayerPocket[id][g_PlayerCount[id]][I_AMMO] = cs_get_user_bpammo(id, get_weaponid(full))
            g_PlayerCount[id]++; ham_strip_weapon(id, full); save_data(id)
            client_print(id, print_chat, "[Pocket] Depozitat: %s", clean)
        } else client_print(id, print_chat, "[Pocket] Buzunar plin sau nu ai arma!")
    }
}

// --- MENIURI ---
public cmd_pocket(id) {
    new menu = menu_create("\yPortofel:", "pocket_handler")
    new txt[128], nm[6]; formatex(txt, 127, "Bani: \g%d$", g_PlayerMoney[id]); menu_additem(menu, txt, "money")
    for(new i=0; i<g_PlayerCount[id]; i++) {
        formatex(txt, 127, "%s \d(Ammo: %d)", g_PlayerPocket[id][i][I_NAME][7], g_PlayerPocket[id][i][I_AMMO])
        num_to_str(i, nm, 5); menu_additem(menu, txt, nm)
    }
    menu_display(id, menu)
}

public cmd_market(id) {
    new menu = menu_create("\yMarket Global", "market_handler")
    if(g_MarketCount == 0) menu_additem(menu, "\dMomentan nu sunt iteme de vanzare", "none")
    else {
        for(new i=0; i<g_MarketCount; i++) {
            new txt[128], nm[6]; formatex(txt, 127, "%s \y[%d$] \d(V: %s)", g_MarketItems[i][I_NAME][7], g_MarketItems[i][I_PRICE], g_MarketItems[i][I_OWNER])
            num_to_str(i, nm, 5); menu_additem(menu, txt, nm)
        }
    }
    menu_display(id, menu)
}

public cmd_set_price(id) {
    new szP[16]; read_args(szP, 15); remove_quotes(szP); new price = str_to_num(szP)
    if(price <= 0 || g_MarketCount >= MAX_MARKET_ITEMS) { client_print(id, print_chat, "[Market] Pret invalid sau Market plin!"); return PLUGIN_HANDLED; }
    new idx = g_SelectedSlot[id]
    copy(g_MarketItems[g_MarketCount][I_NAME], 23, g_PlayerPocket[id][idx][I_NAME])
    g_MarketItems[g_MarketCount][I_AMMO] = g_PlayerPocket[id][idx][I_AMMO]
    g_MarketItems[g_MarketCount][I_PRICE] = price
    get_user_name(id, g_MarketItems[g_MarketCount][I_OWNER], 23)
    g_MarketCount++; remove_pocket_item(id, idx); save_data(id); save_market()
    client_print(id, print_chat, "[Market] Item scos la vanzare!"); cmd_pocket(id)
    return PLUGIN_HANDLED
}

// --- MOTD HELP ---
public show_help_motd(id) {
    new motd[1536], len = 0
    len += formatex(motd[len], 1535-len, "<html><body style='background:#1a1a1a; color:#ccc; font-family:sans-serif; padding:20px;'>")
    len += formatex(motd[len], 1535-len, "<h1 style='color:#ff9900; border-bottom:1px solid #444;'>Ghid Pocket & Market</h1>")
    len += formatex(motd[len], 1535-len, "<p><b style='color:#fff;'>/store [arma/suma]</b><br>Salveaza ce ai in mana sau banii in portofelul personal.</p>")
    len += formatex(motd[len], 1535-len, "<p><b style='color:#fff;'>/store pack</b><br>Pune tot ce ai pe tine in buzunar instant.</p>")
    len += formatex(motd[len], 1535-len, "<p><b style='color:#fff;'>/pocket</b><br>Vezi inventarul tau personal nVault.</p>")
    len += formatex(motd[len], 1535-len, "<p><b style='color:#fff;'>/market</b><br>Poti vinde iteme chiar si cand esti offline.</p>")
    len += formatex(motd[len], 1535-len, "<p><b style='color:#fff;'>/donate [item/suma] [nume]</b><br>Trimite cadouri prietenilor.</p>")
    len += formatex(motd[len], 1535-len, "<hr><small>Limita Pocket: %d sloturi | Market: %d sloturi</small>", MAX_ITEMS, MAX_MARKET_ITEMS)
    len += formatex(motd[len], 1535-len, "</body></html>")
    show_motd(id, motd, "Ghid Complet")
}

// --- UTILS SALVARE ---
public load_data(id) {
    new name[32], key[64], data[128]; get_user_name(id, name, 31)
    formatex(key, 63, "%s_MONEY", name); g_PlayerMoney[id] = nvault_get(g_Vault, key)
    formatex(key, 63, "%s_COUNT", name); g_PlayerCount[id] = nvault_get(g_Vault, key)
    for(new i = 0; i < g_PlayerCount[id]; i++) {
        formatex(key, 63, "%s_ITM_%d", name, i)
        if(nvault_get(g_Vault, key, data, 127)) {
            new strAmmo[8]; parse(data, g_PlayerPocket[id][i][I_NAME], 23, strAmmo, 7)
            g_PlayerPocket[id][i][I_AMMO] = str_to_num(strAmmo)
        }
    }
}

public save_data(id) {
    new name[32], key[64], data[128]; get_user_name(id, name, 31)
    formatex(key, 63, "%s_MONEY", name); num_to_str(g_PlayerMoney[id], data, 127); nvault_set(g_Vault, key, data)
    formatex(key, 63, "%s_COUNT", name); num_to_str(g_PlayerCount[id], data, 127); nvault_set(g_Vault, key, data)
    for(new i = 0; i < g_PlayerCount[id]; i++) {
        formatex(key, 63, "%s_ITM_%d", name, i)
        formatex(data, 127, "^"%s^" %d", g_PlayerPocket[id][i][I_NAME], g_PlayerPocket[id][i][I_AMMO])
        nvault_set(g_Vault, key, data)
    }
}

public load_market() {
    new data[192], key[32]; g_MarketCount = nvault_get(g_Vault, "MARKET_COUNT")
    for(new i = 0; i < g_MarketCount; i++) {
        formatex(key, 31, "MKITM_%d", i)
        if(nvault_get(g_Vault, key, data, 191)) {
            new sAmmo[8], sPrice[12]; parse(data, g_MarketItems[i][I_NAME], 23, sAmmo, 7, g_MarketItems[i][I_OWNER], 23, sPrice, 11)
            g_MarketItems[i][I_AMMO] = str_to_num(sAmmo); g_MarketItems[i][I_PRICE] = str_to_num(sPrice)
        }
    }
}

public save_market() {
    new data[192], key[32]; num_to_str(g_MarketCount, data, 31); nvault_set(g_Vault, "MARKET_COUNT", data)
    for(new i = 0; i < g_MarketCount; i++) {
        formatex(key, 31, "MKITM_%d", i)
        formatex(data, 191, "^"%s^" %d ^"%s^" %d", g_MarketItems[i][I_NAME], g_MarketItems[i][I_AMMO], g_MarketItems[i][I_OWNER], g_MarketItems[i][I_PRICE])
        nvault_set(g_Vault, key, data)
    }
}

remove_pocket_item(id, index) {
    for(new i = index; i < g_PlayerCount[id] - 1; i++) g_PlayerPocket[id][i] = g_PlayerPocket[id][i+1]
    g_PlayerCount[id]--
}

public client_putinserver(id) load_data(id)
public client_disconnected(id) save_data(id)
public plugin_end() save_market()

stock ham_strip_weapon(id, const wName[]) {
    new ent = find_ent_by_owner(-1, wName, id)
    if(ent > 0) {
        engclient_cmd(id, "weapon_knife")
        ExecuteHamB(Ham_Weapon_RetireWeapon, ent)
        ExecuteHamB(Ham_RemovePlayerItem, id, ent)
        ExecuteHamB(Ham_Item_Kill, ent)
    }
}
