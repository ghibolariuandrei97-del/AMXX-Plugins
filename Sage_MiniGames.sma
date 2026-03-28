#include <amxmodx>
#include <cstrike>
#include <fun>
#include <engine>
#include <great_sage> // Aici tragem functia is_user_sage() din include-ul tau

// Variabile globale pentru a tine minte ce e activ
new g_MathAnswer;
new g_ActiveMode;

public plugin_init() {
    register_plugin("Great Sage: Games", "1.0", "AI");

    register_clcmd("say /games", "cmd_games");
    register_clcmd("say_team /games", "cmd_games");

    // Hook pentru Quiz-ul de matematica
    register_clcmd("say", "hook_say");
    register_clcmd("say_team", "hook_say");

    // Resetam efectele speciale la inceputul rundei
    register_event("HLTV", "event_round_start", "a", "1=0", "2=0");
    
    // Viteza se reseteaza in CS cand schimbi arma, asa ca o fortam aici pentru Speed Mode
    register_event("CurWeapon", "event_curweapon", "be", "1=1");
}

public cmd_games(id) {
    // Verificam daca jucatorul este Sage
    if (!is_user_sage(id)) {
        client_print(id, print_chat, "[Sage Games] Acces respins! Doar Great Sage poate comanda aceste jocuri.");
        return PLUGIN_HANDLED;
    }

    new menu = menu_create("\yOrdin de la Sage: \wCe jucam?", "menu_handler_games");
    
    menu_additem(menu, "\wKnife Only \y(Macel cu cutitele)", "1");
    menu_additem(menu, "\w1 HP Sudden Death \y(Atentie la picioare!)", "2");
    menu_additem(menu, "\wAWP Snipers \y(Lunetistii)", "3");
    menu_additem(menu, "\wInvisible Ghosts \y(Invizibilitate totala)", "4");
    menu_additem(menu, "\wMoon Gravity \y(Zburam pe luna)", "5");
    menu_additem(menu, "\wMath Quiz \y(Intrebare de mate - Primul ia premiul)", "6");
    menu_additem(menu, "\wFlashbang Party \y(Orbeti toti)", "7");
    menu_additem(menu, "\wSpeed Demons \y(Viteza maxima)", "8");
    menu_additem(menu, "\wTank Mode \y(500 HP + 500 Armura)", "9");
    menu_additem(menu, "\wGrenade Rain \y(Doar explozibil)", "10");

    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public menu_handler_games(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, 5, iName, 63, callback);
    new choice = str_to_num(data);
    g_ActiveMode = choice;

    new sage_name[32];
    get_user_name(id, sage_name, 31);

    // Iteram prin toti jucatorii vii pentru a aplica efectele
    for (new i = 1; i <= 32; i++) {
        if (!is_user_alive(i)) continue;

        // Daca vrei ca Sage-ul sa NU fie afectat de propriile jocuri, poti lasa linia de mai jos:
        // if (is_user_sage(i)) continue;

        switch (choice) {
            case 1: { // Knife Only
                strip_user_weapons(i);
                give_item(i, "weapon_knife");
            }
            case 2: { // 1 HP
                set_user_health(i, 1);
            }
            case 3: { // AWP
                strip_user_weapons(i);
                give_item(i, "weapon_knife");
                give_item(i, "weapon_awp");
                cs_set_user_bpammo(i, CSW_AWP, 30);
            }
            case 4: { // Invizibilitate (Setam Render pe invizibil complet)
                set_user_rendering(i, kRenderFxNone, 0, 0, 0, kRenderTransAlpha, 0);
            }
            case 5: { // Gravitatie
                set_user_gravity(i, 0.3); // 30% din gravitatia normala
            }
            case 7: { // Flashbang
                strip_user_weapons(i);
                give_item(i, "weapon_knife");
                give_item(i, "weapon_flashbang");
                cs_set_user_bpammo(i, CSW_FLASHBANG, 99); // Ii umplem de flashuri
            }
            case 8: { // Speed
                set_user_maxspeed(i, 800.0);
            }
            case 9: { // Tanc
                set_user_health(i, 500);
                cs_set_user_armor(i, 500, CS_ARMOR_VESTHELM);
            }
            case 10: { // HE Only
                strip_user_weapons(i);
                give_item(i, "weapon_knife");
                give_item(i, "weapon_hegrenade");
                cs_set_user_bpammo(i, CSW_HEGRENADE, 99);
            }
        }
    }

    // Mesajele publice
    switch (choice) {
        case 1: client_print(0, print_chat, "[Sage Games] %s v-a lasat fara arme! KNIFE ONLY!", sage_name);
        case 2: client_print(0, print_chat, "[Sage Games] %s a injumatatit viata tututor... la 1 HP!", sage_name);
        case 3: client_print(0, print_chat, "[Sage Games] %s a pornit modul AWP SNIPERS!", sage_name);
        case 4: client_print(0, print_chat, "[Sage Games] %s v-a facut INVIZIBILI pe toti!", sage_name);
        case 5: client_print(0, print_chat, "[Sage Games] %s a taiat gravitatia! Zbor placut!", sage_name);
        case 6: {
            // Generam doua numere pentru quiz
            new a = random_num(10, 100);
            new b = random_num(10, 50);
            g_MathAnswer = a + b;
            client_print(0, print_chat, "[Sage Quiz] %s intreaba: Cat face %d + %d?", sage_name, a, b);
            client_print(0, print_chat, "[Sage Quiz] Primul care raspunde castiga 100 HP si 16000$!");
        }
        case 7: client_print(0, print_chat, "[Sage Games] %s a inceput FLASHBANG PARTY!", sage_name);
        case 8: client_print(0, print_chat, "[Sage Games] %s v-a pompat cu adrenalina! SPEED DEMONS!", sage_name);
        case 9: client_print(0, print_chat, "[Sage Games] %s v-a transformat in TANCURI (500 HP)!", sage_name);
        case 10: client_print(0, print_chat, "[Sage Games] %s a pornit PLOAIA DE GRENADE!", sage_name);
    }

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// Interceptam mesajele in chat pentru a verifica raspunsurile la Quiz
public hook_say(id) {
    if (g_MathAnswer == 0) return PLUGIN_CONTINUE;

    new msg[32];
    read_args(msg, charsmax(msg));
    remove_quotes(msg); // Scoatem ghilimelele puse automat de AMXX

    if (str_to_num(msg) == g_MathAnswer) {
        new name[32];
        get_user_name(id, name, 31);
        
        client_print(0, print_chat, "[Sage Quiz] %s a raspuns corect (%d) si a castigat premiul!", name, g_MathAnswer);
        
        if (is_user_alive(id)) {
            set_user_health(id, get_user_health(id) + 100);
        }
        cs_set_user_money(id, 16000);
        
        g_MathAnswer = 0; // Oprim quiz-ul pentru ca cineva a castigat
        return PLUGIN_HANDLED; // Blocam mesajul cu raspunsul sa nu mai apara dublu in chat
    }

    return PLUGIN_CONTINUE;
}

public event_curweapon(id) {
    if (!is_user_alive(id)) return;
    
    // In CS, viteza se reseteaza automat cand schimbi arma. 
    // Daca modul e activ (8), fortam constant viteza mare.
    if (g_ActiveMode == 8) {
        set_user_maxspeed(id, 800.0);
    }
}

public event_round_start() {
    g_ActiveMode = 0;
    g_MathAnswer = 0;

    // Resetam jucatorii la valorile normale de Counter-Strike
    for (new i = 1; i <= 32; i++) {
        if (is_user_connected(i)) {
            set_user_rendering(i); // Scoate invizibilitatea
            set_user_gravity(i, 1.0); // Reset gravitatie
            set_user_maxspeed(i, 250.0); // Reset viteza
        }
    }
}
