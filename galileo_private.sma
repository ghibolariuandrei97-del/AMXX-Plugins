#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <engine>
#include <fakemeta>
#include <reapi>          // Comentează această linie dacă nu ai ReAPI

#pragma semicolon 1

#define PLUGIN  "PrivateGalileo"
#define VERSION "1.1"
#define AUTHOR  "Astarasefk"

// =====================================================
// CHANGELOG v1.1
// - Comenzile de chat (say ...) sunt acum interceptate direct prin
//   FakeMeta (FM_ClientCommand) in loc de register_clcmd, ca sa nu mai
//   fie "inghitite" de alte plugin-uri care hook-uiesc say (ex:
//   admin_hierarchy_metin2, care are un conflict cunoscut pe say).
// - Eliminat conflictul intern: hook-ul generic de say + hook-urile
//   specifice (say rtv, say maps etc.) se declansau amandoua pentru
//   aceeasi comanda scurta, generand mesaje in plus / gresite.
// - Meniul de vot se reafiseaza automat in fiecare secunda tuturor
//   celor care nu au votat inca, deci nu mai "dispare" definitiv.
// - Nominarile ramaneau blocate permanent dupa ce intrau la vot;
//   acum se elibereaza automat cand incepe votul.
// - RTV ramanea blocat tot restul hartii dupa o singura folosire;
//   acum se reseteaza la inceputul fiecarui vot (util la extend).
// - Eliminat un rand din plugin_cfg care rescria amx_nextmap cu un
//   sir gol la fiecare schimbare de harta.
// - Comenzi noi: unrtv, unnominate, vote (redeschide votul), mmhelp/
//   mmcmds/cmds, amx_cancelvote, amx_setnextmap.
// =====================================================

#define MAX_MAPS            512
#define MAX_MAPNAME         32
#define MAX_NOMINATIONS     8
#define SELECT_MAPS         5
#define VOTE_TIME           15
#define PRE_VOTE_TIME       5
#define BLOCK_RECENT        5

#define TASK_VOTE_START     1000
#define TASK_VOTE_END       1001
#define TASK_CHANGELEVEL    1002
#define TASK_CHECK_TIME     1003
#define TASK_SHOW_TIMER     1004

new Array:g_aMaps;
new Array:g_aNominated;
new Array:g_aNominatorId;
new Array:g_aRecentMaps;
new Array:g_aVoteMaps;

new g_szCurrentMap[MAX_MAPNAME];
new g_szNextMap[MAX_MAPNAME];
new g_iNominations[33];
new g_bVoted[33];
new g_iVotes[SELECT_MAPS + 2];          // + Extend + Stay
new g_iVoteCount;
new g_bVoteInProgress;
new g_bRTV[33];
new g_iRTVCount;
new g_iExtendCount;
new Float:g_fMapStartTime;
new Float:g_fVoteStartTime;

new g_pCvarRTVPercent;
new g_pCvarRTVMinPlayers;
new g_pCvarRTVDelay;
new g_pCvarVoteBeforeEnd;
new g_pCvarExtendMax;
new g_pCvarExtendStep;
new g_pCvarBlockRecent;
new g_pCvarChangeType;
new g_pCvarNominatePerPlayer;
new g_pCvarShowNominate;


new const g_szPrefix[] = "^4[MapManager]^1";

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // Interceptam say/say_team direct la nivel de FakeMeta, ca sa nu
    // depindem de ordinea de incarcare fata de alte plugin-uri care
    // hook-uiesc "say" (ex: admin_hierarchy_metin2) si care ar putea
    // bloca register_clcmd-urile noastre inainte sa apuce sa ruleze.
    register_forward(FM_ClientCommand, "fw_ClientCommand");

    register_concmd("amx_listmaps",     "cmd_AdminListMaps", ADMIN_MAP, " - Listeaza toate hartile");
    register_concmd("gal_startvote",    "cmd_ForceVote", ADMIN_MAP, " - Forteaza votul de mapa");
    register_concmd("amx_votemap",      "cmd_ForceVote", ADMIN_MAP, " - Forteaza votul de mapa");
    register_concmd("amx_cancelvote",   "cmd_CancelVote", ADMIN_MAP, " - Anuleaza votul de harta in desfasurare");
    register_concmd("amx_setnextmap",   "cmd_SetNextMap", ADMIN_MAP, "<harta> - Seteaza manual urmatoarea harta");
    register_concmd("gal_createmapfile","cmd_CreateMapFile", ADMIN_RCON, "<fisier> - Creeaza lista de harti");

    // Cvars
    g_pCvarRTVPercent         = register_cvar("mm_rtv_percent",        "60");
    g_pCvarRTVMinPlayers      = register_cvar("mm_rtv_minplayers",     "3");
    g_pCvarRTVDelay           = register_cvar("mm_rtv_delay",          "5.0");
    g_pCvarVoteBeforeEnd      = register_cvar("mm_vote_before_end",    "2.0");
    g_pCvarExtendMax          = register_cvar("mm_extend_max",         "3");
    g_pCvarExtendStep         = register_cvar("mm_extend_step",        "15");
    g_pCvarBlockRecent        = register_cvar("mm_block_recent",       "5");
    g_pCvarChangeType         = register_cvar("mm_change_type",        "1"); // 0=instant, 1=round end, 2=map end
    g_pCvarNominatePerPlayer  = register_cvar("mm_nominate_per_player","2");
    g_pCvarShowNominate       = register_cvar("mm_show_nominate_chat", "1");

    g_aMaps         = ArrayCreate(MAX_MAPNAME);
    g_aNominated    = ArrayCreate(MAX_MAPNAME);
    g_aNominatorId  = ArrayCreate(1);
    g_aRecentMaps   = ArrayCreate(MAX_MAPNAME);
    g_aVoteMaps     = ArrayCreate(MAX_MAPNAME);

    get_mapname(g_szCurrentMap, charsmax(g_szCurrentMap));
    g_fMapStartTime = get_gametime();

    LoadMaps();
    LoadRecentMaps();

    set_task(10.0, "Task_CheckTime", TASK_CHECK_TIME, _, _, "b");

    register_event("HLTV", "Event_NewRound", "a", "1=0", "2=0");

    #if defined _reapi_included
    RegisterHookChain(RG_CSGameRules_RestartRound, "OnRestartRound", false);
    #endif
}

public plugin_end()
{
    SaveRecentMaps();
    ArrayDestroy(g_aMaps);
    ArrayDestroy(g_aNominated);
    ArrayDestroy(g_aNominatorId);
    ArrayDestroy(g_aRecentMaps);
    ArrayDestroy(g_aVoteMaps);
}

// =====================================================
// LOAD MAPS
// =====================================================
LoadMaps()
{
    ArrayClear(g_aMaps);

    new szFile[128];
    get_configsdir(szFile, charsmax(szFile));
    add(szFile, charsmax(szFile), "/maps.ini");

    if (!file_exists(szFile))
    {
        // Fallback: mapcycle.txt
        get_cvar_string("mapcyclefile", szFile, charsmax(szFile));
    }

    new iFile = fopen(szFile, "rt");
    if (!iFile)
    {
        log_amx("[MapManager] Nu am putut deschide lista de harti!");
        return;
    }

    new szLine[64], szMap[MAX_MAPNAME];
    while (!feof(iFile))
    {
        fgets(iFile, szLine, charsmax(szLine));
        trim(szLine);

        if (!szLine[0] || szLine[0] == ';' || szLine[0] == '/')
            continue;

        parse(szLine, szMap, charsmax(szMap));

        if (is_map_valid(szMap) && !IsMapInArray(g_aMaps, szMap))
        {
            ArrayPushString(g_aMaps, szMap);
        }
    }
    fclose(iFile);

    log_amx("[MapManager] Incarcate %d harti valide.", ArraySize(g_aMaps));
}

bool:IsMapInArray(Array:a, const szMap[])
{
    new szTemp[MAX_MAPNAME];
    for (new i = 0; i < ArraySize(a); i++)
    {
        ArrayGetString(a, i, szTemp, charsmax(szTemp));
        if (equali(szTemp, szMap))
            return true;
    }
    return false;
}

// =====================================================
// COMENZI (apelate din fw_ClientCommand, mai jos in fisier)
// =====================================================
public cmd_RTV(id)
{
    if (g_bVoteInProgress)
    {
        client_print_color(id, print_team_default, "%s Votul este deja in desfasurare!", g_szPrefix);
        return;
    }

    if (g_bRTV[id])
    {
        client_print_color(id, print_team_default, "%s Ai votat deja pentru RTV!", g_szPrefix);
        return;
    }

    new iPlayers = get_playersnum_ex(GetPlayers_ExcludeBots);
    if (iPlayers < get_pcvar_num(g_pCvarRTVMinPlayers))
    {
        client_print_color(id, print_team_default, "%s Prea putini jucatori pentru RTV (minim %d).", g_szPrefix, get_pcvar_num(g_pCvarRTVMinPlayers));
        return;
    }

    new Float:fDelay = get_pcvar_float(g_pCvarRTVDelay) * 60.0;
    if (get_gametime() - g_fMapStartTime < fDelay)
    {
        client_print_color(id, print_team_default, "%s Trebuie sa astepti %.0f minute inainte de RTV.", g_szPrefix, get_pcvar_float(g_pCvarRTVDelay));
        return;
    }

    g_bRTV[id] = true;
    g_iRTVCount++;

    new iNeeded = floatround(iPlayers * (get_pcvar_float(g_pCvarRTVPercent) / 100.0), floatround_ceil);

    client_print_color(0, print_team_default, "%s ^3%n^1 a cerut RTV (^4%d^1/^4%d^1).", g_szPrefix, id, g_iRTVCount, iNeeded);

    if (g_iRTVCount >= iNeeded)
    {
        client_print_color(0, print_team_default, "%s ^4RTV reusit!^1 Votul incepe in %d secunde...", g_szPrefix, PRE_VOTE_TIME);
        set_task(float(PRE_VOTE_TIME), "Task_StartVote", TASK_VOTE_START);
    }
}

public cmd_UnRTV(id)
{
    if (!g_bRTV[id])
    {
        client_print_color(id, print_team_default, "%s Nu ai un vot RTV activ.", g_szPrefix);
        return;
    }

    g_bRTV[id] = false;
    g_iRTVCount = max(0, g_iRTVCount - 1);

    client_print_color(0, print_team_default, "%s ^3%n^1 si-a retras votul RTV (^4%d^1 ramase).", g_szPrefix, id, g_iRTVCount);
}

public cmd_NextMap(id)
{
    if (g_szNextMap[0])
        client_print_color(id, print_team_default, "%s Urmatoarea harta: ^4%s", g_szPrefix, g_szNextMap);
    else
        client_print_color(id, print_team_default, "%s Urmatoarea harta nu a fost inca stabilita.", g_szPrefix);
}

public cmd_TimeLeft(id)
{
    new iTimeleft = get_timeleft();
    if (iTimeleft > 0)
    {
        new iMin = iTimeleft / 60;
        new iSec = iTimeleft % 60;
        client_print_color(id, print_team_default, "%s Timp ramas: ^4%d:%02d", g_szPrefix, iMin, iSec);
    }
    else
        client_print_color(id, print_team_default, "%s Nu exista limita de timp.", g_szPrefix);
}

public cmd_TheTime(id)
{
    new szTime[32];
    get_time("%H:%M:%S", szTime, charsmax(szTime));
    client_print_color(id, print_team_default, "%s Ora serverului: ^4%s", g_szPrefix, szTime);
}

public cmd_CurrentMap(id)
{
    client_print_color(id, print_team_default, "%s Harta actuala: ^4%s", g_szPrefix, g_szCurrentMap);
}

public cmd_ShowNominations(id)
{
    new iSize = ArraySize(g_aNominated);
    if (!iSize)
    {
        client_print_color(id, print_team_default, "%s Nu exista nominari momentan.", g_szPrefix);
        return;
    }

    client_print_color(id, print_team_default, "%s Nominari curente:", g_szPrefix);

    new szMap[MAX_MAPNAME];
    for (new i = 0; i < iSize; i++)
    {
        ArrayGetString(g_aNominated, i, szMap, charsmax(szMap));
        client_print_color(id, print_team_default, "  ^4%d.^1 %s", i + 1, szMap);
    }
}

// =====================================================
// NOMINATE
// =====================================================
TryNominate(id, const szSearch[])
{
    if (g_bVoteInProgress)
        return;

    if (g_iNominations[id] >= get_pcvar_num(g_pCvarNominatePerPlayer))
    {
        client_print_color(id, print_team_default, "%s Ai atins limita de nominari (%d).", g_szPrefix, get_pcvar_num(g_pCvarNominatePerPlayer));
        return;
    }

    new Array:aMatches = ArrayCreate(MAX_MAPNAME);
    new szMap[MAX_MAPNAME];

    for (new i = 0; i < ArraySize(g_aMaps); i++)
    {
        ArrayGetString(g_aMaps, i, szMap, charsmax(szMap));

        if (containi(szMap, szSearch) != -1 && !IsMapBlocked(szMap) && !IsMapInArray(g_aNominated, szMap))
        {
            ArrayPushString(aMatches, szMap);
        }
    }

    new iMatches = ArraySize(aMatches);

    if (iMatches == 0)
    {
        client_print_color(id, print_team_default, "%s Nicio harta gasita pentru ^3%s^1.", g_szPrefix, szSearch);
        ArrayDestroy(aMatches);
        return;
    }

    if (iMatches == 1)
    {
        ArrayGetString(aMatches, 0, szMap, charsmax(szMap));
        DoNominate(id, szMap);
    }
    else
    {
        // Meniu cu rezultate
        new menu = menu_create("\r[MapManager] \yAlege harta de nominat:", "Menu_NominateHandler");

        for (new i = 0; i < iMatches && i < 8; i++)
        {
            ArrayGetString(aMatches, i, szMap, charsmax(szMap));
            menu_additem(menu, szMap, szMap);
        }

        menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
        menu_display(id, menu);
    }

    ArrayDestroy(aMatches);
}

DoNominate(id, const szMap[])
{
    if (IsMapInArray(g_aNominated, szMap))
    {
        client_print_color(id, print_team_default, "%s Harta ^3%s^1 este deja nominata.", g_szPrefix, szMap);
        return;
    }

    ArrayPushString(g_aNominated, szMap);
    ArrayPushCell(g_aNominatorId, id);
    g_iNominations[id]++;

    if (get_pcvar_num(g_pCvarShowNominate))
        client_print_color(0, print_team_default, "%s ^3%n^1 a nominat ^4%s", g_szPrefix, id, szMap);
    else
        client_print_color(id, print_team_default, "%s Ai nominat ^4%s", g_szPrefix, szMap);
}

public cmd_NominateMenu(id)
{
    if (g_bVoteInProgress)
    {
        client_print_color(id, print_team_default, "%s Nu poti nomina in timpul votului.", g_szPrefix);
        return;
    }

    new menu = menu_create("\r[MapManager] \yNominate Map:", "Menu_NominateHandler");

    new szMap[MAX_MAPNAME];
    new iCount;

    for (new i = 0; i < ArraySize(g_aMaps) && iCount < 50; i++)
    {
        ArrayGetString(g_aMaps, i, szMap, charsmax(szMap));

        if (!IsMapBlocked(szMap) && !IsMapInArray(g_aNominated, szMap) && !equali(szMap, g_szCurrentMap))
        {
            menu_additem(menu, szMap, szMap);
            iCount++;
        }
    }

    if (!iCount)
    {
        client_print_color(id, print_team_default, "%s Nu exista harti disponibile pentru nominare.", g_szPrefix);
        menu_destroy(menu);
        return;
    }

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu);
}

public Menu_NominateHandler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szMap[MAX_MAPNAME], access, callback;
    menu_item_getinfo(menu, item, access, szMap, charsmax(szMap), _, _, callback);

    DoNominate(id, szMap);

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public cmd_UnNominate(id)
{
    if (!g_iNominations[id])
    {
        client_print_color(id, print_team_default, "%s Nu ai nicio nominare activa.", g_szPrefix);
        return;
    }

    new iRemoved;
    for (new i = ArraySize(g_aNominated) - 1; i >= 0; i--)
    {
        if (ArrayGetCell(g_aNominatorId, i) == id)
        {
            ArrayDeleteItem(g_aNominated, i);
            ArrayDeleteItem(g_aNominatorId, i);
            iRemoved++;
        }
    }

    g_iNominations[id] = 0;
    client_print_color(id, print_team_default, "%s Ai retras %d nominare(i).", g_szPrefix, iRemoved);
}

public cmd_MapsMenu(id) cmd_NominateMenu(id);

// =====================================================
// LIST MAPS
// =====================================================
public cmd_ListMaps(id)
{
    console_print(id, "===== Lista harti disponibile (%d) =====", ArraySize(g_aMaps));

    new szMap[MAX_MAPNAME];
    for (new i = 0; i < ArraySize(g_aMaps); i++)
    {
        ArrayGetString(g_aMaps, i, szMap, charsmax(szMap));
        console_print(id, "%3d. %s%s", i + 1, szMap, IsMapBlocked(szMap) ? " [BLOCKED]" : "");
    }

    console_print(id, "========================================");
    client_print_color(id, print_team_default, "%s Lista completa a fost afisata in consola.", g_szPrefix);
}

public cmd_AdminListMaps(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED;

    cmd_ListMaps(id);
    return PLUGIN_HANDLED;
}

// =====================================================
// VOTE SYSTEM
// =====================================================
public Task_CheckTime()
{
    if (g_bVoteInProgress)
        return;

    new iTimeleft = get_timeleft();
    new Float:fBefore = get_pcvar_float(g_pCvarVoteBeforeEnd) * 60.0;

    if (iTimeleft > 0 && iTimeleft <= floatround(fBefore))
    {
        client_print_color(0, print_team_default, "%s Votul pentru urmatoarea harta incepe in %d secunde!", g_szPrefix, PRE_VOTE_TIME);
        set_task(float(PRE_VOTE_TIME), "Task_StartVote", TASK_VOTE_START);
        remove_task(TASK_CHECK_TIME);
    }
}

public Task_StartVote()
{
    if (g_bVoteInProgress)
        return;

    g_bVoteInProgress = true;
    g_fVoteStartTime = get_gametime();
    ArrayClear(g_aVoteMaps);

    // Adauga nominarile
    new szMap[MAX_MAPNAME];
    for (new i = 0; i < ArraySize(g_aNominated) && ArraySize(g_aVoteMaps) < SELECT_MAPS; i++)
    {
        ArrayGetString(g_aNominated, i, szMap, charsmax(szMap));
        if (!IsMapInArray(g_aVoteMaps, szMap))
            ArrayPushString(g_aVoteMaps, szMap);
    }

    // Nominarile au fost consumate - eliberam lista si contorul per jucator
    ArrayClear(g_aNominated);
    ArrayClear(g_aNominatorId);
    arrayset(g_iNominations, 0, sizeof(g_iNominations));

    // Completeaza cu harti random
    new iAttempts;
    while (ArraySize(g_aVoteMaps) < SELECT_MAPS && iAttempts < 100)
    {
        iAttempts++;
        new iRandom = random_num(0, ArraySize(g_aMaps) - 1);
        ArrayGetString(g_aMaps, iRandom, szMap, charsmax(szMap));

        if (!IsMapBlocked(szMap) && !IsMapInArray(g_aVoteMaps, szMap) && !equali(szMap, g_szCurrentMap))
            ArrayPushString(g_aVoteMaps, szMap);
    }

    // Reset votes
    arrayset(g_iVotes, 0, sizeof(g_iVotes));
    arrayset(g_bVoted, false, sizeof(g_bVoted));
    g_iVoteCount = 0;

    // Resetam si cererile de RTV, ca jucatorii sa poata folosi rtv din nou
    // daca harta continua (ex: dupa un extend)
    arrayset(g_bRTV, false, sizeof(g_bRTV));
    g_iRTVCount = 0;

    ShowVoteMenu(0);

    set_task(float(VOTE_TIME), "Task_EndVote", TASK_VOTE_END);
    set_task(1.0, "Task_ShowTimer", TASK_SHOW_TIMER, _, _, "b");
}

ShowVoteMenu(id, iRemaining = VOTE_TIME)
{
    new menu = menu_create(fmt("\r[MapManager] \yVoteaza harta: \d(%d sec)", iRemaining), "Menu_VoteHandler");

    new szMap[MAX_MAPNAME], szItem[64];

    for (new i = 0; i < ArraySize(g_aVoteMaps); i++)
    {
        ArrayGetString(g_aVoteMaps, i, szMap, charsmax(szMap));
        formatex(szItem, charsmax(szItem), "%s \d[%d]", szMap, g_iVotes[i]);
        menu_additem(menu, szItem, fmt("%d", i));
    }

    // Extend
    if (g_iExtendCount < get_pcvar_num(g_pCvarExtendMax))
    {
        formatex(szItem, charsmax(szItem), "\yExtend Map (+%d min) \d[%d]", get_pcvar_num(g_pCvarExtendStep), g_iVotes[SELECT_MAPS]);
        menu_additem(menu, szItem, fmt("%d", SELECT_MAPS));
    }

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);

    if (id == 0)
    {
        new players[32], num;
        get_players(players, num, "ch");
        for (new i = 0; i < num; i++)
            menu_display(players[i], menu);
    }
    else
        menu_display(id, menu);
}

public Menu_VoteHandler(id, menu, item)
{
    if (item == MENU_EXIT || !g_bVoteInProgress)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    if (g_bVoted[id])
    {
        client_print_color(id, print_team_default, "%s Ai votat deja!", g_szPrefix);
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[8], access, callback;
    menu_item_getinfo(menu, item, access, szData, charsmax(szData), _, _, callback);

    new iChoice = str_to_num(szData);
    g_iVotes[iChoice]++;
    g_bVoted[id] = true;
    g_iVoteCount++;

    new szMap[MAX_MAPNAME];
    if (iChoice < SELECT_MAPS)
        ArrayGetString(g_aVoteMaps, iChoice, szMap, charsmax(szMap));
    else
        copy(szMap, charsmax(szMap), "Extend Map");

    client_print_color(id, print_team_default, "%s Ai votat pentru ^4%s", g_szPrefix, szMap);

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public Task_ShowTimer()
{
    if (!g_bVoteInProgress)
        return;

    new iRemaining = VOTE_TIME - floatround(get_gametime() - g_fVoteStartTime);
    if (iRemaining <= 0)
        return;

    // Reafisam meniul in fiecare secunda tuturor celor care nu au votat
    // inca, ca sa nu ramana fara el daca li se suprascrie de altceva
    // (ex: alt meniu/HUD declansat de miscare).
    new players[32], num;
    get_players(players, num, "ch");

    for (new i = 0; i < num; i++)
    {
        if (!g_bVoted[players[i]])
            ShowVoteMenu(players[i], iRemaining);
    }
}

public Task_EndVote()
{
    remove_task(TASK_SHOW_TIMER);
    g_bVoteInProgress = false;

    new iWinner = 0;
    new iMaxVotes = g_iVotes[0];

    for (new i = 1; i <= SELECT_MAPS; i++)
    {
        if (g_iVotes[i] > iMaxVotes)
        {
            iMaxVotes = g_iVotes[i];
            iWinner = i;
        }
    }

    if (iWinner == SELECT_MAPS) // Extend
    {
        g_iExtendCount++;
        new iStep = get_pcvar_num(g_pCvarExtendStep);
        set_cvar_float("mp_timelimit", get_cvar_float("mp_timelimit") + float(iStep));

        client_print_color(0, print_team_default, "%s Harta a fost ^4prelungita^1 cu %d minute!", g_szPrefix, iStep);

        // Restart check
        set_task(10.0, "Task_CheckTime", TASK_CHECK_TIME, _, _, "b");
        return;
    }

    new szMap[MAX_MAPNAME];
    ArrayGetString(g_aVoteMaps, iWinner, szMap, charsmax(szMap));
    copy(g_szNextMap, charsmax(g_szNextMap), szMap);
    set_cvar_string("amx_nextmap", g_szNextMap);

    client_print_color(0, print_team_default, "%s Urmatoarea harta: ^4%s^1 (cu %d voturi)", g_szPrefix, g_szNextMap, iMaxVotes);

    // Add to recent
    ArrayPushString(g_aRecentMaps, g_szCurrentMap);
    while (ArraySize(g_aRecentMaps) > get_pcvar_num(g_pCvarBlockRecent))
        ArrayDeleteItem(g_aRecentMaps, 0);

    new iType = get_pcvar_num(g_pCvarChangeType);
    if (iType == 0)
        set_task(5.0, "Task_ChangeLevel", TASK_CHANGELEVEL);
    else if (iType == 1)
        client_print_color(0, print_team_default, "%s Harta se va schimba la finalul rundei.", g_szPrefix);
    // type 2 = la final de mapa (default behavior)
}

public Task_ChangeLevel()
{
    if (g_szNextMap[0])
        server_cmd("changelevel %s", g_szNextMap);
}

public Event_NewRound()
{
    if (g_szNextMap[0] && get_pcvar_num(g_pCvarChangeType) == 1 && !g_bVoteInProgress)
    {
        set_task(1.0, "Task_ChangeLevel", TASK_CHANGELEVEL);
    }
}

public cmd_ReshowVote(id)
{
    if (!g_bVoteInProgress)
    {
        client_print_color(id, print_team_default, "%s Niciun vot de harta in desfasurare momentan.", g_szPrefix);
        return;
    }

    if (g_bVoted[id])
    {
        client_print_color(id, print_team_default, "%s Ai votat deja!", g_szPrefix);
        return;
    }

    new iRemaining = VOTE_TIME - floatround(get_gametime() - g_fVoteStartTime);
    if (iRemaining < 1)
        iRemaining = 1;

    ShowVoteMenu(id, iRemaining);
}

public cmd_HelpMenu(id)
{
    client_print_color(id, print_team_default, "%s ^4Comenzi disponibile in chat:", g_szPrefix);
    client_print_color(id, print_team_default, "  ^3rtv^1 / ^3unrtv^1 - cere / anuleaza schimbarea hartii");
    client_print_color(id, print_team_default, "  ^3maps^1, ^3nominate^1 - nomineaza o harta din lista");
    client_print_color(id, print_team_default, "  ^3unnominate^1 - retrage nominarea ta");
    client_print_color(id, print_team_default, "  ^3nominations^1 - vezi nominarile curente");
    client_print_color(id, print_team_default, "  ^3nextmap^1, ^3currentmap^1, ^3timeleft^1 - info harta");
    client_print_color(id, print_team_default, "  ^3vote^1 - redeschide meniul de vot daca e activ");
}

// =====================================================
// HELPERS
// =====================================================
bool:IsMapBlocked(const szMap[])
{
    return IsMapInArray(g_aRecentMaps, szMap);
}

LoadRecentMaps()
{
    // Simplificat - poti salva in fisier daca vrei persistenta
}

SaveRecentMaps()
{
    // Simplificat
}

public cmd_ForceVote(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED;

    if (g_bVoteInProgress)
    {
        client_print_color(id, print_team_default, "%s Votul este deja in desfasurare!", g_szPrefix);
        return PLUGIN_HANDLED;
    }

    client_print_color(0, print_team_default, "%s Adminul ^3%n^1 a forțat votul de harta!", g_szPrefix, id);
    set_task(float(PRE_VOTE_TIME), "Task_StartVote", TASK_VOTE_START);

    return PLUGIN_HANDLED;
}

public cmd_CancelVote(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED;

    if (!g_bVoteInProgress)
    {
        console_print(id, "[MapManager] Niciun vot in desfasurare.");
        return PLUGIN_HANDLED;
    }

    g_bVoteInProgress = false;
    remove_task(TASK_VOTE_END);
    remove_task(TASK_SHOW_TIMER);
    set_task(10.0, "Task_CheckTime", TASK_CHECK_TIME, _, _, "b");

    client_print_color(0, print_team_default, "%s Votul a fost anulat de un admin.", g_szPrefix);
    return PLUGIN_HANDLED;
}

public cmd_SetNextMap(id, level, cid)
{
    if (!cmd_access(id, level, cid, 2))
        return PLUGIN_HANDLED;

    new szMap[MAX_MAPNAME];
    read_argv(1, szMap, charsmax(szMap));

    if (!szMap[0] || !is_map_valid(szMap))
    {
        console_print(id, "[MapManager] Harta invalida sau nespecificata. Foloseste: amx_setnextmap <harta>");
        return PLUGIN_HANDLED;
    }

    copy(g_szNextMap, charsmax(g_szNextMap), szMap);
    set_cvar_string("amx_nextmap", g_szNextMap);

    client_print_color(0, print_team_default, "%s Adminul ^3%n^1 a setat urmatoarea harta: ^4%s", g_szPrefix, id, g_szNextMap);
    return PLUGIN_HANDLED;
}

public cmd_CreateMapFile(id, level, cid)
{
    if (!cmd_access(id, level, cid, 2))
        return PLUGIN_HANDLED;

    new szFile[64];
    read_argv(1, szFile, charsmax(szFile));

    new szPath[128];
    get_configsdir(szPath, charsmax(szPath));
    format(szPath, charsmax(szPath), "%s/%s", szPath, szFile);

    new iFile = fopen(szPath, "wt");
    if (!iFile)
    {
        console_print(id, "[MapManager] Nu am putut crea fisierul.");
        return PLUGIN_HANDLED;
    }

    new szMap[MAX_MAPNAME];
    for (new i = 0; i < ArraySize(g_aMaps); i++)
    {
        ArrayGetString(g_aMaps, i, szMap, charsmax(szMap));
        fprintf(iFile, "%s^n", szMap);
    }
    fclose(iFile);

    console_print(id, "[MapManager] Fisier creat: %s (%d harti)", szPath, ArraySize(g_aMaps));
    return PLUGIN_HANDLED;
}

// =====================================================
// INTERCEPTARE SAY / SAY_TEAM
// Facuta prin FakeMeta (nu register_clcmd) ca sa functioneze
// indiferent de alte plugin-uri care hook-uiesc say pe server.
// =====================================================
public fw_ClientCommand(id)
{
    if (!is_user_connected(id))
        return FMRES_IGNORED;

    new szCmd[32];
    read_argv(0, szCmd, charsmax(szCmd));

    if (!equali(szCmd, "say") && !equali(szCmd, "say_team"))
        return FMRES_IGNORED;

    new szArgs[192];
    read_args(szArgs, charsmax(szArgs));
    remove_quotes(szArgs);
    trim(szArgs);

    if (!szArgs[0])
        return FMRES_IGNORED;

    new szKey[192];
    if (szArgs[0] == '/')
        copy(szKey, charsmax(szKey), szArgs[1]);
    else
        copy(szKey, charsmax(szKey), szArgs);

    new bool:bHandled = true;

    if (equali(szKey, "rtv") || equali(szKey, "rockthevote"))
        cmd_RTV(id);
    else if (equali(szKey, "unrtv"))
        cmd_UnRTV(id);
    else if (equali(szKey, "nextmap"))
        cmd_NextMap(id);
    else if (equali(szKey, "timeleft"))
        cmd_TimeLeft(id);
    else if (equali(szKey, "thetime") || equali(szKey, "time"))
        cmd_TheTime(id);
    else if (equali(szKey, "currentmap"))
        cmd_CurrentMap(id);
    else if (equali(szKey, "maps"))
        cmd_MapsMenu(id);
    else if (equali(szKey, "listmaps"))
        cmd_ListMaps(id);
    else if (equali(szKey, "nominate") || equali(szKey, "nom"))
        cmd_NominateMenu(id);
    else if (equali(szKey, "unnominate") || equali(szKey, "unnom"))
        cmd_UnNominate(id);
    else if (equali(szKey, "nominations") || equali(szKey, "noms"))
        cmd_ShowNominations(id);
    else if (equali(szKey, "vote") || equali(szKey, "votemap"))
        cmd_ReshowVote(id);
    else if (equali(szKey, "mmhelp") || equali(szKey, "mmcmds") || equali(szKey, "cmds"))
        cmd_HelpMenu(id);
    else
        bHandled = false;

    if (bHandled)
        return FMRES_SUPERCEDE;

    // Nominare rapida: "say de_dust2" sau "say dust" (fara spatiu, fara "/")
    if (strlen(szArgs) >= 3 && szArgs[0] != '/' && !containi(szArgs, " "))
    {
        TryNominate(id, szArgs);
    }

    return FMRES_IGNORED;
}

public client_disconnected(id)
{
    if (g_bRTV[id])
    {
        g_bRTV[id] = false;
        g_iRTVCount = max(0, g_iRTVCount - 1);
    }

    // Curatam nominarile jucatorului deconectat, ca sa nu ramana "agatate"
    for (new i = ArraySize(g_aNominated) - 1; i >= 0; i--)
    {
        if (ArrayGetCell(g_aNominatorId, i) == id)
        {
            ArrayDeleteItem(g_aNominated, i);
            ArrayDeleteItem(g_aNominatorId, i);
        }
    }

    g_iNominations[id] = 0;
    g_bVoted[id] = false;
}

#if defined _reapi_included
public OnRestartRound()
{
    // Poți adăuga logică extra aici dacă e nevoie
}
#endif
