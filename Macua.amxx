#include <amxmodx>
#include <amxmisc>

#define MAX_PLAYERS 32
#define MAX_CARDS 52
#define TASK_TURN 1000

new const g_Suits[][] = { "Inima Rosie", "Toba", "Trefla", "Pica" };
new const g_Ranks[][] = { "2","3","4","5","6","7","8","9","10","J","Q","K","As" };

new g_Deck[MAX_CARDS], g_DeckPtr;
new g_PlayerHand[MAX_PLAYERS+1][MAX_CARDS], g_HandCount[MAX_PLAYERS+1];

new g_Players[2]; 
new g_CurrentTurnIdx; 
new g_TableCard, g_ActiveSuit;

new g_DrawPenalty, g_SkipCount;
new bool:g_GameActive;

public plugin_init() {
    register_plugin("Macaua", "1.0", "Gemini & User");
    register_clcmd("say /macaua", "ShowMainMenu");
    register_clcmd("say_team /macaua", "ShowMainMenu");
}

public client_disconnected(id) {
    if(g_GameActive && (g_Players[0] == id || g_Players[1] == id)) {
        g_GameActive = false;
        remove_task(TASK_TURN);
    }
}

// ================= MENIURI =================

public ShowMainMenu(id) {
    new menu = menu_create("\yMacaua \rElite \w- Meniu", "MainMenuHandler");
    menu_additem(menu, "Provoaca Jucator", "1");
    menu_additem(menu, "Joaca cu BOT", "2");
    menu_display(id, menu);
    return PLUGIN_HANDLED;
}

public MainMenuHandler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    if(item == 0) ShowPlayersMenu(id);
    else StartGame(id, 0);
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public ShowPlayersMenu(id) {
    new menu = menu_create("Alege oponent:", "PlayerSelectHandler");
    new players[32], pnum, tid;
    get_players(players, pnum, "ch");
    for(new i=0; i<pnum; i++) {
        tid = players[i];
        if(tid == id) continue;
        new name[32], info[5];
        get_user_name(tid, name, 31);
        num_to_str(tid, info, 4);
        menu_additem(menu, name, info);
    }
    menu_display(id, menu);
}

public PlayerSelectHandler(id, menu, item) {
    if(item != MENU_EXIT) {
        new data[6], iName[32], a, c;
        menu_item_getinfo(menu, item, a, data, 5, iName, 31, c);
        StartGame(id, str_to_num(data));
    }
    menu_destroy(menu);
}

// ================= CORE LOGIC =================

public StartGame(p1, p2) {
    g_Players[0] = p1;
    g_Players[1] = p2;
    g_GameActive = true;
    g_DrawPenalty = 0;
    g_SkipCount = 0;
    
    for(new i=0; i<52; i++) g_Deck[i] = i;
    for(new i=51; i>0; i--) {
        new j = random(i+1);
        new tmp = g_Deck[i]; g_Deck[i] = g_Deck[j]; g_Deck[j] = tmp;
    }
    g_DeckPtr = 0;

    for(new i=0; i<2; i++) {
        new id = g_Players[i];
        if(id == 0 && i == 0) continue; 
        g_HandCount[id] = 0;
        for(new j=0; j<5; j++) DrawOne(id);
    }

    g_TableCard = DrawRaw();
    g_ActiveSuit = g_TableCard / 13;
    g_CurrentTurnIdx = 0;

    client_print(0, print_center, "[Macaua] Start! Masa: %s de %s", g_Ranks[g_TableCard%13], g_Suits[g_ActiveSuit]);
    ManageTurns();
}

public ManageTurns() {
    if(!g_GameActive) return;
    new id = g_Players[g_CurrentTurnIdx];

    if(id == 0) set_task(1.0, "BotLogic");
    else ShowGameMenu(id);
}

public ShowGameMenu(id) {
    if(!g_GameActive || id == 0) return;

    new title[192];
    if(g_DrawPenalty > 0)
        formatex(title, 191, "\rATAC! \wTrebuie sa iei \r%d \wcarti!^n\yMasa: \r%s %s", g_DrawPenalty, g_Ranks[g_TableCard%13], g_Suits[g_ActiveSuit]);
    else if(g_SkipCount > 0)
        formatex(title, 191, "\rBLOCAJ! \wTrebuie sa pui 4 sau stai o tura!^n\yMasa: \r%s %s", g_Ranks[g_TableCard%13], g_Suits[g_ActiveSuit]);
    else
        formatex(title, 191, "\yMasa: \r%s %s \w(Culoare: \y%s\w)", g_Ranks[g_TableCard%13], g_Suits[g_ActiveSuit], g_Suits[g_ActiveSuit]);

    new menu = menu_create(title, "GameHandler");

    for(new i=0; i<g_HandCount[id]; i++) {
        new card = g_PlayerHand[id][i];
        new bool:valid = IsValid(card);
        new txt[64], info[5];
        formatex(txt, 63, "%s %s %s", g_Ranks[card%13], g_Suits[card/13], valid ? "" : "\d(X)");
        num_to_str(i, info, 4);
        menu_additem(menu, txt, info, valid ? 0 : (1<<31));
    }

    menu_additem(menu, g_DrawPenalty > 0 ? "\rIa Cartile" : "\yTrage o carte / Pas", "DRAW");
    
    // Setam meniul sa nu se inchida la tasta 0 decat daca vrem
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu);
}

public GameHandler(id, menu, item) {
    if(item == MENU_EXIT) { 
        menu_destroy(menu); 
        return PLUGIN_HANDLED; 
    }

    new data[6], iName[32], a, c;
    menu_item_getinfo(menu, item, a, data, 5, iName, 31, c);

    if(equal(data, "DRAW")) {
        if(g_DrawPenalty > 0) {
            for(new i=0; i<g_DrawPenalty; i++) DrawOne(id);
            g_DrawPenalty = 0;
            client_print(id, print_center, "[Macaua] Ai umflat cartile!");
        } else if(g_SkipCount > 0) {
            g_SkipCount = 0;
            client_print(id, print_center, "[Macaua] Ai stat o tura!");
        } else {
            DrawOne(id);
            client_print(id, print_center, "[Macaua] Ai tras o carte.");
        }
        AdvanceTurn();
    } else {
        PlayCard(id, str_to_num(data));
    }
    
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

bool:IsValid(card) {
    new r = card % 13;
    new s = card / 13;
    new tr = g_TableCard % 13;

    if(g_DrawPenalty > 0) return (r == 0 || r == 1); 
    if(g_SkipCount > 0) return (r == 2);
    if(r == 5) return true; // 7-le merge mereu

    return (s == g_ActiveSuit || r == tr);
}

public PlayCard(id, idx) {
    new card = g_PlayerHand[id][idx];
    new rank = card % 13;

    g_TableCard = card;
    g_ActiveSuit = card / 13;

    if(rank == 0) g_DrawPenalty += 2; 
    else if(rank == 1) g_DrawPenalty += 3; 
    else if(rank == 2) g_SkipCount++; 

    for(new i=idx; i<g_HandCount[id]-1; i++) g_PlayerHand[id][i] = g_PlayerHand[id][i+1];
    g_HandCount[id]--;

    new name[32];
    if(id == 0) copy(name, 31, "BOT"); else get_user_name(id, name, 31);
    client_print(0, print_center, "[Macaua] %s a pus %s de %s", name, g_Ranks[rank], g_Suits[card/13]);

    if(g_HandCount[id] == 0) {
        client_print(0, print_center, "[Macaua] %s a CASTIGAT!", name);
        g_GameActive = false;
        return;
    }

    // AICI E REPARATIA:
    if(rank == 5) {
        if(id == 0) { // Daca e bot, alege random culoarea
            g_ActiveSuit = random(4);
            client_print(0, print_center, "[Macaua] BOT-ul a schimbat culoarea in: %s", g_Suits[g_ActiveSuit]);
            AdvanceTurn();
        } else {
            ShowSuitMenu(id);
        }
    } else {
        AdvanceTurn();
    }
}

public ShowSuitMenu(id) {
    if(id == 0) return; // Siguranta extra pentru bot

    new menu = menu_create("\yAlege noua culoare:", "SuitHandler");
    menu_additem(menu, "Inima Rosie", "0");
    menu_additem(menu, "Toba", "1");
    menu_additem(menu, "Trefla", "2");
    menu_additem(menu, "Pica", "3");
    menu_display(id, menu);
}

public SuitHandler(id, menu, item) {
    if(item != MENU_EXIT) {
        new data[2], iName[32], a, c;
        menu_item_getinfo(menu, item, a, data, 1, iName, 31, c);
        g_ActiveSuit = str_to_num(data);
        client_print(0, print_center, "[Macaua] Culoarea s-a schimbat in %s", g_Suits[g_ActiveSuit]);
    }
    AdvanceTurn();
    menu_destroy(menu);
}

public AdvanceTurn() {
    g_CurrentTurnIdx = (g_CurrentTurnIdx + 1) % 2;
    ManageTurns();
}

// ================= BOT & UTILS =================

public BotLogic() {
    if(!g_GameActive) return;
    new id = 0; 
    new bool:found = false;

    for(new i=0; i<g_HandCount[id]; i++) {
        if(IsValid(g_PlayerHand[id][i])) {
            PlayCard(id, i);
            found = true;
            break;
        }
    }

    if(!found) {
        if(g_DrawPenalty > 0) {
            for(new i=0; i<g_DrawPenalty; i++) DrawOne(id);
            g_DrawPenalty = 0;
            client_print(0, print_center, "[Macaua] BOT-ul a umflat cartile.");
        } else if(g_SkipCount > 0) {
            g_SkipCount = 0;
            client_print(0, print_center, "[Macaua] BOT-ul a stat o tura.");
        } else {
            DrawOne(id);
            client_print(0, print_center, "[Macaua] BOT-ul a tras o carte.");
        }
        AdvanceTurn();
    }
}

public DrawOne(id) {
    if(g_DeckPtr >= 52) { 
        for(new i=0; i<52; i++) g_Deck[i] = i;
        g_DeckPtr = 0;
    }
    if(g_HandCount[id] < MAX_CARDS) g_PlayerHand[id][g_HandCount[id]++] = g_Deck[g_DeckPtr++];
}

public DrawRaw() {
    return g_Deck[g_DeckPtr++];
}
