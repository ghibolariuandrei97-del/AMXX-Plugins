#include <amxmodx>
#include <amxmisc>
#include <reapi>

#define PLUGIN      "Skin Models Menu (INI + Money)"
#define VERSION     "1.2"
#define AUTHOR      "Astarasefk"

#define MAX_CATEGORIES      32
#define MAX_SKINS_PER_CAT   64
#define MAX_SKIN_NAME       48
#define MAX_MODEL_PATH      96
#define MAX_WEAPON_NAME     16

enum _:SkinData
{
    SKIN_NAME[MAX_SKIN_NAME],
    V_MODEL[MAX_MODEL_PATH],
    P_MODEL[MAX_MODEL_PATH],
    WEAPON_ID,          // CSW_*
    PRICE               // preț în $
}

enum _:CategoryData
{
    CAT_NAME[32],
    Array:CAT_SKINS,
    CAT_COUNT
}

new Array:g_Categories;
new g_iCategoryCount;

new g_iPlayerSkin[33][CSW_P90 + 1];     // 0 = default, 1+ = index skin + 1
new g_iMenuCategory[33];

// Mapare nume armă → CSW
new const g_szWeaponNames[][] =
{
    "p228", "scout", "hegrenade", "xm1014", "c4",
    "mac10", "aug", "smokegrenade", "elite", "fiveseven",
    "ump45", "sg550", "galil", "famas", "usp",
    "glock", "glock18", "awp", "mp5", "mp5navy",
    "m249", "m3", "m4a1", "tmp", "g3sg1",
    "flashbang", "deagle", "sg552", "ak47", "knife", "p90"
};

new const g_iWeaponIDs[] =
{
    CSW_P228, CSW_SCOUT, CSW_HEGRENADE, CSW_XM1014, CSW_C4,
    CSW_MAC10, CSW_AUG, CSW_SMOKEGRENADE, CSW_ELITE, CSW_FIVESEVEN,
    CSW_UMP45, CSW_SG550, CSW_GALIL, CSW_FAMAS, CSW_USP,
    CSW_GLOCK18, CSW_GLOCK18, CSW_AWP, CSW_MP5NAVY, CSW_MP5NAVY,
    CSW_M249, CSW_M3, CSW_M4A1, CSW_TMP, CSW_G3SG1,
    CSW_FLASHBANG, CSW_DEAGLE, CSW_SG552, CSW_AK47, CSW_KNIFE, CSW_P90
};

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("say /skin",       "Cmd_OpenMenu");
    register_clcmd("say /skins",      "Cmd_OpenMenu");

    register_clcmd("say_team /skin",  "Cmd_OpenMenu");
    register_clcmd("say_team /skins", "Cmd_OpenMenu");

    register_event("CurWeapon", "Event_CurWeapon", "be", "1=1");
    register_clcmd("nightvision", "Cmd_OpenMenu");

    g_Categories = ArrayCreate(CategoryData);
    LoadConfig();
}

public plugin_cfg()
{
    new szPath[128];
    get_configsdir(szPath, charsmax(szPath));
    add(szPath, charsmax(szPath), "/skin_models.ini");

    if (!file_exists(szPath))
        GenerateDefaultConfig(szPath);
}

public plugin_end()
{
    for (new i = 0; i < g_iCategoryCount; i++)
    {
        new cat[CategoryData];
        ArrayGetArray(g_Categories, i, cat);
        if (cat[CAT_SKINS])
            ArrayDestroy(cat[CAT_SKINS]);
    }
    ArrayDestroy(g_Categories);
}

public client_putinserver(id)
{
    arrayset(g_iPlayerSkin[id], 0, sizeof(g_iPlayerSkin[]));
}

// ============================================================
// ÎNCĂRCARE CONFIG
// ============================================================
LoadConfig()
{
    new szPath[128];
    get_configsdir(szPath, charsmax(szPath));
    add(szPath, charsmax(szPath), "/skin_models.ini");

    if (!file_exists(szPath))
    {
        log_amx("[SkinModels] Fișierul nu există → se generează default.");
        GenerateDefaultConfig(szPath);
    }

    new fp = fopen(szPath, "rt");
    if (!fp)
    {
        log_amx("[SkinModels] Nu pot deschide %s", szPath);
        return;
    }

    new szLine[256], szSection[32];
    new currentCat = -1;
    new skin[SkinData];

    while (!feof(fp))
    {
        fgets(fp, szLine, charsmax(szLine));
        trim(szLine);

        if (!szLine[0] || szLine[0] == ';' || szLine[0] == '/')
            continue;

        // [Categorie]
        if (szLine[0] == '[')
        {
            new end = contain(szLine, "]");
            if (end == -1)
                continue;

            copy(szSection, end, szLine[1]);

            new cat[CategoryData];
            copy(cat[CAT_NAME], charsmax(cat[CAT_NAME]), szSection);
            cat[CAT_SKINS] = ArrayCreate(SkinData);
            cat[CAT_COUNT] = 0;

            ArrayPushArray(g_Categories, cat);
            currentCat = g_iCategoryCount++;
            continue;
        }

        if (currentCat == -1)
            continue;

        // Format: "Nume" "v_model" "p_model" "arma" "pret"
        new szName[MAX_SKIN_NAME], szV[MAX_MODEL_PATH], szP[MAX_MODEL_PATH];
        new szWeapon[MAX_WEAPON_NAME], szPrice[16];

        if (parse(szLine, szName, charsmax(szName),
                         szV, charsmax(szV),
                         szP, charsmax(szP),
                         szWeapon, charsmax(szWeapon),
                         szPrice, charsmax(szPrice)) < 5)
            continue;

        remove_quotes(szName);
        remove_quotes(szV);
        remove_quotes(szP);
        remove_quotes(szWeapon);
        remove_quotes(szPrice);

        copy(skin[SKIN_NAME], charsmax(skin[SKIN_NAME]), szName);
        copy(skin[V_MODEL], charsmax(skin[V_MODEL]), szV);
        copy(skin[P_MODEL], charsmax(skin[P_MODEL]), szP);
        skin[WEAPON_ID] = GetWeaponID(szWeapon);
        skin[PRICE] = str_to_num(szPrice);

        if (skin[WEAPON_ID] == 0)
        {
            log_amx("[SkinModels] Armă necunoscută: '%s' (skin: %s)", szWeapon, szName);
            continue;
        }

        if (szV[0]) precache_model(szV);
        if (szP[0]) precache_model(szP);

        new cat[CategoryData];
        ArrayGetArray(g_Categories, currentCat, cat);
        ArrayPushArray(cat[CAT_SKINS], skin);
        cat[CAT_COUNT]++;
        ArraySetArray(g_Categories, currentCat, cat);
    }

    fclose(fp);
    log_amx("[SkinModels] Încărcat: %d categorii.", g_iCategoryCount);
}

GenerateDefaultConfig(const szPath[])
{
    new fp = fopen(szPath, "wt");
    if (!fp)
        return;

    fputs(fp, "; ================================================================^n");
    fputs(fp, ";  skin_models.ini  -  CONTROLEZI TOT MENIUL AICI^n");
    fputs(fp, "; ================================================================^n");
    fputs(fp, ";^n");
    fputs(fp, "; CUM ADAUGI O CATEGORIE NOUĂ:^n");
    fputs(fp, ";   [Nume Categorie]^n");
    fputs(fp, ";^n");
    fputs(fp, "; CUM ADAUGI UN SKIN:^n");
    fputs(fp, ";   ^"Nume afisat in meniu^" ^"cale/v_model.mdl^" ^"cale/p_model.mdl^" ^"arma^" ^"pret^"^n");
    fputs(fp, ";^n");
    fputs(fp, "; Exemple de arme valide:^n");
    fputs(fp, ";   knife, ak47, m4a1, awp, deagle, usp, glock, mp5, p90,^n");
    fputs(fp, ";   famas, galil, aug, sg552, m3, xm1014, mac10, ump45, tmp, m249^n");
    fputs(fp, ";^n");
    fputs(fp, "; Pretul este in $ (bani din joc).^n");
    fputs(fp, "; Daca pretul este 0 → skin-ul e gratuit.^n");
    fputs(fp, ";^n");
    fputs(fp, "; Numarul din meniu (ex: Knife [3]) se calculeaza AUTOMAT.^n");
    fputs(fp, "; ================================================================^n^n");

    fputs(fp, "[Knife]^n");
    fputs(fp, "^"Default Knife^" ^"models/v_knife.mdl^" ^"models/p_knife.mdl^" ^"knife^" ^"0^"^n");
    fputs(fp, "^"Karambit (exemplu)^" ^"models/custom/v_karambit.mdl^" ^"models/custom/p_karambit.mdl^" ^"knife^" ^"5000^"^n");
    fputs(fp, "^"Butterfly (exemplu)^" ^"models/custom/v_butterfly.mdl^" ^"models/custom/p_butterfly.mdl^" ^"knife^" ^"8000^"^n^n");

    fputs(fp, "[AK-47]^n");
    fputs(fp, "^"Default AK^" ^"models/v_ak47.mdl^" ^"models/p_ak47.mdl^" ^"ak47^" ^"0^"^n");
    fputs(fp, "^"Redline (exemplu)^" ^"models/custom/v_ak47_redline.mdl^" ^"models/custom/p_ak47_redline.mdl^" ^"ak47^" ^"3500^"^n^n");

    fputs(fp, "[M4A1]^n");
    fputs(fp, "^"Default M4^" ^"models/v_m4a1.mdl^" ^"models/p_m4a1.mdl^" ^"m4a1^" ^"0^"^n");
    fputs(fp, "^"Howl (exemplu)^" ^"models/custom/v_m4a1_howl.mdl^" ^"models/custom/p_m4a1_howl.mdl^" ^"m4a1^" ^"6000^"^n");

    fclose(fp);
    log_amx("[SkinModels] Fișier default generat: %s", szPath);
}

GetWeaponID(const szWeapon[])
{
    for (new i = 0; i < sizeof(g_szWeaponNames); i++)
    {
        if (equali(szWeapon, g_szWeaponNames[i]))
            return g_iWeaponIDs[i];
    }
    return 0;
}

// ============================================================
// MENIU
// ============================================================
public Cmd_OpenMenu(id)
{
    if (!is_user_connected(id))
        return PLUGIN_HANDLED;

    ShowMainMenu(id);
    return PLUGIN_HANDLED;
}

ShowMainMenu(id)
{
    new menu = menu_create("\ySkin Models Menu \r[/skin /shop]", "MainMenu_Handler");

    for (new i = 0; i < g_iCategoryCount; i++)
    {
        new cat[CategoryData];
        ArrayGetArray(g_Categories, i, cat);

        new szItem[64];
        formatex(szItem, charsmax(szItem), "\w[%s] \r[%d]", cat[CAT_NAME], cat[CAT_COUNT]);

        new szInfo[8];
        num_to_str(i, szInfo, charsmax(szInfo));
        menu_additem(menu, szItem, szInfo);
    }

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public MainMenu_Handler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[8], access, callback;
    menu_item_getinfo(menu, item, access, szData, charsmax(szData), _, _, callback);

    g_iMenuCategory[id] = str_to_num(szData);
    menu_destroy(menu);

    ShowSubMenu(id, g_iMenuCategory[id]);
    return PLUGIN_HANDLED;
}

ShowSubMenu(id, catIndex)
{
    if (catIndex < 0 || catIndex >= g_iCategoryCount)
        return;

    new cat[CategoryData];
    ArrayGetArray(g_Categories, catIndex, cat);

    new szTitle[64];
    formatex(szTitle, charsmax(szTitle), "\y%s \r[%d modele]", cat[CAT_NAME], cat[CAT_COUNT]);

    new menu = menu_create(szTitle, "SubMenu_Handler");

    for (new i = 0; i < cat[CAT_COUNT]; i++)
    {
        new skin[SkinData];
        ArrayGetArray(cat[CAT_SKINS], i, skin);

        new bool:bOwned = (g_iPlayerSkin[id][skin[WEAPON_ID]] == i + 1);

        new szItem[80];
        if (bOwned)
            formatex(szItem, charsmax(szItem), "\y%s \r[ACTIV]", skin[SKIN_NAME]);
        else if (skin[PRICE] > 0)
            formatex(szItem, charsmax(szItem), "%s \y[$%d]", skin[SKIN_NAME], skin[PRICE]);
        else
            formatex(szItem, charsmax(szItem), "%s \y[GRATIS]", skin[SKIN_NAME]);

        new szInfo[8];
        num_to_str(i, szInfo, charsmax(szInfo));
        menu_additem(menu, szItem, szInfo);
    }

    menu_additem(menu, "\r« Inapoi", "back");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public SubMenu_Handler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[16], access, callback;
    menu_item_getinfo(menu, item, access, szData, charsmax(szData), _, _, callback);

    if (equal(szData, "back"))
    {
        menu_destroy(menu);
        ShowMainMenu(id);
        return PLUGIN_HANDLED;
    }

    new skinIndex = str_to_num(szData);
    new catIndex  = g_iMenuCategory[id];

    new cat[CategoryData];
    ArrayGetArray(g_Categories, catIndex, cat);

    if (skinIndex < 0 || skinIndex >= cat[CAT_COUNT])
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new skin[SkinData];
    ArrayGetArray(cat[CAT_SKINS], skinIndex, skin);

    // Deja deține skin-ul?
    if (g_iPlayerSkin[id][skin[WEAPON_ID]] == skinIndex + 1)
    {
        client_print_color(id, print_team_default, "^4[Skin]^1 Ai deja acest model activ.");
        menu_destroy(menu);
        ShowSubMenu(id, catIndex);
        return PLUGIN_HANDLED;
    }

    // Verificare bani
    if (skin[PRICE] > 0)
    {
        new money = get_member(id, m_iAccount);
        if (money < skin[PRICE])
        {
            client_print_color(id, print_team_default, "^4[Skin]^1 Nu ai destui bani! Ai nevoie de ^3$%d^1.", skin[PRICE]);
            menu_destroy(menu);
            ShowSubMenu(id, catIndex);
            return PLUGIN_HANDLED;
        }

        // Scade banii
        rg_add_account(id, -skin[PRICE], AS_SET);
        client_print_color(id, print_team_default, "^4[Skin]^1 Ai cumpărat ^3%s^1 pentru ^3$%d^1.", skin[SKIN_NAME], skin[PRICE]);
    }
    else
    {
        client_print_color(id, print_team_default, "^4[Skin]^1 Ai activat ^3%s^1 (gratuit).", skin[SKIN_NAME]);
    }

    // Setează skin-ul
    g_iPlayerSkin[id][skin[WEAPON_ID]] = skinIndex + 1;

    // Aplică imediat
    ApplySkin(id, skin[WEAPON_ID]);
    menu_destroy(menu);
    ShowSubMenu(id, catIndex);
    return PLUGIN_HANDLED;
}

// ============================================================
// APLICARE MODELE (doar V + P)
// ============================================================
public Event_CurWeapon(id)
{
    if (!is_user_alive(id))
        return;

    new weapon = read_data(2);
    ApplySkin(id, weapon);
}

ApplySkin(id, weaponid)
{
    if (weaponid < 1 || weaponid > CSW_P90)
        return;

    new skinIdx = g_iPlayerSkin[id][weaponid];
    if (skinIdx <= 0)
        return;

    skinIdx--; // index real

    for (new c = 0; c < g_iCategoryCount; c++)
    {
        new cat[CategoryData];
        ArrayGetArray(g_Categories, c, cat);

        for (new s = 0; s < cat[CAT_COUNT]; s++)
        {
            new skin[SkinData];
            ArrayGetArray(cat[CAT_SKINS], s, skin);

            if (skin[WEAPON_ID] == weaponid && s == skinIdx)
            {
                if (skin[V_MODEL][0])
                    set_entvar(id, var_viewmodel, skin[V_MODEL]);
                if (skin[P_MODEL][0])
                    set_entvar(id, var_weaponmodel, skin[P_MODEL]);
                return;
            }
        }
    }
}

stock Skin_ParseArg(const string[], start, output[], len)
{
    new i = start, j = 0;
    
    while (string[i] && string[i] != '|')
    {
        if (j < len - 1)
            output[j++] = string[i];
        i++;
    }
    
    output[j] = EOS;
    
    if (!string[i])
        return -1;
    
    return i + 1;
}
