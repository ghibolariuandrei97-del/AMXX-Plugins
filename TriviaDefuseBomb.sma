#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <engine>

#pragma semicolon 1

#define PLUGIN_NAME "Trivia Bomb Defuse"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "AI"

#define MAX_LENGTH 128

new Array:g_aQuestions;
new Array:g_aAnswers;
new Array:g_aMoney;

new bool:g_bBombPlanted;
new g_szCurrentQuestion[MAX_LENGTH];
new g_szCurrentAnswer[MAX_LENGTH];
new g_iCurrentMoney;
new g_iDefuseProgress;

// CVAR-uri
new g_pCvarDefusePercent;
new g_pCvarAllowDead;

public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    g_aQuestions = ArrayCreate(MAX_LENGTH);
    g_aAnswers = ArrayCreate(MAX_LENGTH);
    g_aMoney = ArrayCreate(1, 1); // Stocăm numere întregi (banii)

    // CVAR-uri
    g_pCvarDefusePercent = create_cvar("trivia_defuse_percent", "34", FCVAR_NONE, "Cat la suta din bomba se dezamorseaza per raspuns corect");
    g_pCvarAllowDead = create_cvar("trivia_allow_dead", "1", FCVAR_NONE, "Pot CT-ii morti sa raspunda? 1=Da, 0=Doar cei in viata");

    register_clcmd("say", "Cmd_Say");
    register_clcmd("say_team", "Cmd_Say");

    register_logevent("Event_BombPlanted", 3, "2=Planted_The_Bomb");
    
    RegisterHookChain(RG_CSGameRules_RestartRound, "Event_RoundStart", 0);
    RegisterHookChain(RG_CGrenade_DefuseBombStart, "OnDefuseBombStart", 0);
}

public plugin_cfg() {
    new szConfigsDir[64], szFile[128];
    get_configsdir(szConfigsDir, charsmax(szConfigsDir));
    formatex(szFile, charsmax(szFile), "%s/defuse_trivia.ini", szConfigsDir);

    if (!file_exists(szFile)) {
        write_file(szFile, "; Fisier de configurare Trivia Defuse");
        write_file(szFile, "; Format: ^"Intrebarea^" ^"Raspunsul^" Premiu_In_Bani");
        write_file(szFile, "^"Cat face 5 x 5?^" ^"25^" 500");
        write_file(szFile, "^"Care este capitala Romaniei?^" ^"Bucuresti^" 1500");
        write_file(szFile, "^"Care este prescurtarea de la Counter-Strike?^" ^"CS^" 16000");
    }

    new f = fopen(szFile, "rt");
    if (!f) return;

    new szLine[256], szQuestion[MAX_LENGTH], szAnswer[MAX_LENGTH], szMoney[16];
    new iMoneyAmount;

    while (!feof(f)) {
        fgets(f, szLine, charsmax(szLine));
        trim(szLine);

        if (!szLine[0] || szLine[0] == ';' || szLine[0] == '#' || szLine[0] == '/')
            continue;

        // Parsăm cele 3 argumente
        new parsed = parse(szLine, szQuestion, charsmax(szQuestion), szAnswer, charsmax(szAnswer), szMoney, charsmax(szMoney));

        if (parsed >= 2 && szQuestion[0] && szAnswer[0]) {
            // Dacă nu a pus argumentul 3 cu banii, setăm 0 pe default
            iMoneyAmount = (parsed >= 3) ? str_to_num(szMoney) : 0;

            ArrayPushString(g_aQuestions, szQuestion);
            ArrayPushString(g_aAnswers, szAnswer);
            ArrayPushCell(g_aMoney, iMoneyAmount);
        }
    }
    fclose(f);
}

public plugin_end() {
    if (g_aQuestions) ArrayDestroy(g_aQuestions);
    if (g_aAnswers) ArrayDestroy(g_aAnswers);
    if (g_aMoney) ArrayDestroy(g_aMoney);
}

public Event_RoundStart() {
    g_bBombPlanted = false;
    g_iDefuseProgress = 0;
}

public Event_BombPlanted() {
    if (ArraySize(g_aQuestions) == 0) return;

    g_bBombPlanted = true;
    g_iDefuseProgress = 0;

    client_print_color(0, print_team_red, "^4[Trivia] ^1Tero a plantat bomba! Dezamorsarea normala e blocata.");
    AskNextQuestion();
}

public OnDefuseBombStart(const ent, const player) {
    if (g_bBombPlanted) {
        client_print_color(player, print_team_default, "^4[Trivia] ^1Defuse blocat! Scrie in chat raspunsul la: ^3%s", g_szCurrentQuestion);
        return HC_SUPERCEDE;
    }
    return HC_CONTINUE;
}

public Cmd_Say(id) {
    if (!g_bBombPlanted) return PLUGIN_CONTINUE;

    // Doar echipa CT poate dezamorsa
    if (get_member(id, m_iTeam) != TEAM_CT)
        return PLUGIN_CONTINUE;

    // Verificam daca jucatorul e mort si daca are voie sa raspunda confom cvar-ului
    if (!is_user_alive(id) && get_pcvar_num(g_pCvarAllowDead) == 0)
        return PLUGIN_CONTINUE;

    new szMessage[128];
    read_args(szMessage, charsmax(szMessage));
    remove_quotes(szMessage);
    trim(szMessage);

    // Verificăm răspunsul (insensitive)
    if (equali(szMessage, g_szCurrentAnswer)) {
        new szName[32];
        get_user_name(id, szName, charsmax(szName));

        // Acordăm banii prin ReAPI dacă premiul este mai mare ca 0
        if (g_iCurrentMoney > 0) {
            rg_add_account(id, g_iCurrentMoney, AS_ADD);
        }

        // Adăugăm progres
        new iAddPercent = get_pcvar_num(g_pCvarDefusePercent);
        g_iDefuseProgress += iAddPercent;

        client_print_color(0, print_team_blue, "^4[Trivia] ^3%s ^1a raspuns corect (^4%s^1) si a castigat ^4%d$^1!", szName, g_szCurrentAnswer, g_iCurrentMoney);

        // Verificăm dacă s-a atins 100%
	if (g_iDefuseProgress >= 100) {
	client_print_color(0, print_team_red, "^4[Trivia] ^1Bomba a fost dezamorsata complet!");
	DefuseBomb();
        } else {
            client_print_color(0, print_team_default, "^4[Trivia] ^1Progres dezamorsare: ^4%d%%^1.", g_iDefuseProgress);
            AskNextQuestion(); // Punem următoarea întrebare
        }

        return PLUGIN_HANDLED; // Ascundem mesajul curent ca să nu dea de gol răspunsul
    }

    return PLUGIN_CONTINUE;
}

AskNextQuestion() {
    new iSize = ArraySize(g_aQuestions);
    if (iSize == 0) return;

    new iRandom = random_num(0, iSize - 1);
    ArrayGetString(g_aQuestions, iRandom, g_szCurrentQuestion, charsmax(g_szCurrentQuestion));
    ArrayGetString(g_aAnswers, iRandom, g_szCurrentAnswer, charsmax(g_szCurrentAnswer));
    g_iCurrentMoney = ArrayGetCell(g_aMoney, iRandom);

    client_print_color(0, print_team_blue, "^4[Trivia] ^1Raspunde pentru a continua dezamorsarea: ^3%s", g_szCurrentQuestion);
}

DefuseBomb() {
    g_bBombPlanted = false;
    g_iDefuseProgress = 0;

    new c4 = -1;
    while ((c4 = find_ent_by_class(c4, "grenade"))) {
        if (get_member(c4, m_Grenade_bIsC4)) {
            remove_entity(c4);
            break;
        }
    }

    rg_round_end(5.0, WINSTATUS_CTS, ROUND_BOMB_DEFUSED, "Bomba a fost dezamorsata!");
}
