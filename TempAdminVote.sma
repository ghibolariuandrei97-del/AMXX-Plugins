#include <amxmodx>
#include <amxmisc>

#define PLUGIN "Temp Admin"
#define VERSION "1.0"
#define AUTHOR "AI"

// Cvar Pointers
new pcv_flags, pcv_noadmins, pcv_unanimous, pcv_votetime, pcv_tag, pcv_minplayers, pcv_allowbots, pcv_selfvote, pcv_maxadmins;

// Variabile Globale
new g_admins_elected_count = 0; // Contorizam cati admini au fost alesi
new bool:g_vote_in_progress = false;
new bool:g_vote_this_round = false;

new g_votes[33];
new g_voters;

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("say /voteadmin", "cmd_voteadmin");
    register_clcmd("say_team /voteadmin", "cmd_voteadmin");

    // Cvars
    pcv_flags = register_cvar("amx_voteadmin_flags", "bcdefijtu");
    pcv_noadmins = register_cvar("amx_voteadmin_noadmins", "1");
    pcv_unanimous = register_cvar("amx_voteadmin_unanimous", "0");
    pcv_votetime = register_cvar("amx_voteadmin_time", "15.0");
    pcv_tag = register_cvar("amx_voteadmin_tag", "DAEVA");
    pcv_minplayers = register_cvar("amx_voteadmin_minplayers", "2");
    pcv_allowbots = register_cvar("amx_voteadmin_allow_bots", "1");
    pcv_selfvote = register_cvar("amx_voteadmin_selfvote", "0");
    pcv_maxadmins = register_cvar("amx_voteadmin_max", "1"); // Cati admini pot fi alesi per harta

    register_event("HLTV", "Event_NewRound", "a", "1=0", "2=0");
}

public Event_NewRound() {
    g_vote_this_round = false;
}

print_msg(id, const msg[], any:...) {
    new buffer[192], tag[32];
    get_pcvar_string(pcv_tag, tag, charsmax(tag));
    vformat(buffer, charsmax(buffer), msg, 3);
    client_print_color(id, print_team_default, "^4[%s] ^1%s", tag, buffer);
}

public cmd_voteadmin(id) {
    new max_allowed = get_pcvar_num(pcv_maxadmins);

    if (g_admins_elected_count >= max_allowed) {
        print_msg(id, "S-a atins limita maxima de admini votati (%d) pe aceasta harta!", max_allowed);
        return PLUGIN_HANDLED;
    }
    if (g_vote_in_progress) {
        print_msg(id, "Un vot este deja in desfasurare!");
        return PLUGIN_HANDLED;
    }
    if (g_vote_this_round) {
        print_msg(id, "S-a votat deja runda aceasta. Incearca runda viitoare!");
        return PLUGIN_HANDLED;
    }

    new players[32], num;
    get_players(players, num, get_pcvar_num(pcv_allowbots) ? "h" : "ch"); 
    
    if (num < get_pcvar_num(pcv_minplayers)) {
        print_msg(id, "Nu sunt destui jucatori (minim %d) pentru a porni votul!", get_pcvar_num(pcv_minplayers));
        return PLUGIN_HANDLED;
    }

    if (get_pcvar_num(pcv_noadmins) == 1) {
        new all_players[32], total;
        get_players(all_players, total, "ch"); 
        for (new i = 0; i < total; i++) {
            if ((get_user_flags(all_players[i]) & ~ADMIN_USER) > 0) {
                print_msg(id, "Nu poti porni votul deoarece exista deja admini online!");
                return PLUGIN_HANDLED;
            }
        }
    }

    start_vote(id);
    return PLUGIN_HANDLED;
}

public start_vote(initiator) {
    g_vote_in_progress = true;
    g_vote_this_round = true;
    g_voters = 0;

    for (new i = 1; i <= 32; i++) g_votes[i] = 0;

    new name_initiator[32];
    get_user_name(initiator, name_initiator, charsmax(name_initiator));
    print_msg(0, "^3%s ^1a pornit votul pentru un Admin temporar!", name_initiator);

    new players[32], num;
    get_players(players, num, "ch"); 

    for (new i = 0; i < num; i++) {
        show_vote_menu(players[i]);
    }

    set_task(get_pcvar_float(pcv_votetime), "end_vote");
}

public show_vote_menu(id) {
    new menu_title[64], tag[32];
    get_pcvar_string(pcv_tag, tag, charsmax(tag));
    formatex(menu_title, charsmax(menu_title), "\r[%s] \yPe cine votezi Admin?", tag);
    
    new menu = menu_create(menu_title, "menu_handler");

    new players[32], num;
    get_players(players, num, get_pcvar_num(pcv_allowbots) ? "h" : "ch"); 

    new bool:can_self_vote = get_pcvar_num(pcv_selfvote) == 1;

    for (new i = 0; i < num; i++) {
        new target = players[i];
        
        if (target == id && !can_self_vote) continue; 
        
        // Nu are rost sa votam pe cineva care ARE deja admin (ales anterior sau setat manual)
        if ((get_user_flags(target) & ~ADMIN_USER) > 0) continue;

        new name[32], temp_id[10];
        get_user_name(target, name, charsmax(name));
        num_to_str(target, temp_id, charsmax(temp_id));

        if (is_user_bot(target)) format(name, charsmax(name), "%s (BOT)", name);

        menu_additem(menu, name, temp_id, 0);
    }

    menu_addblank(menu, 0);
    menu_additem(menu, "\wI DONT WANT TO VOTE!", "0", 0);

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public menu_handler(id, menu, item) {
    if (item == MENU_EXIT || !g_vote_in_progress) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);

    new target = str_to_num(data);
    new name[32]; get_user_name(id, name, charsmax(name));

    if (target == 0) {
        print_msg(0, "^3%s ^1a refuzat sa voteze.", name);
    } else {
        g_votes[target]++;
        g_voters++;
        print_msg(0, "^3%s ^1a votat!", name);
    }

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public end_vote() {
    g_vote_in_progress = false;

    new players[32], num;
    get_players(players, num, "ch");
    for (new i = 0; i < num; i++) show_menu(players[i], 0, "^n", 1);

    if (g_voters == 0) {
        print_msg(0, "Nimeni nu a votat un candidat valid. Vot anulat.");
        return;
    }

    new winner = 0, max_votes = 0, tie = false;

    for (new i = 1; i <= 32; i++) {
        if (g_votes[i] > max_votes) {
            max_votes = g_votes[i];
            winner = i;
            tie = false;
        } else if (g_votes[i] == max_votes && max_votes > 0) {
            tie = true;
        }
    }

    if (tie) {
        print_msg(0, "Votul s-a incheiat la egalitate! Niciun admin ales.");
        return;
    }

    if (get_pcvar_num(pcv_unanimous) == 1 && max_votes < g_voters) {
        print_msg(0, "Votul nu a fost unanim! Niciun admin ales.");
        return;
    }

    if (is_user_connected(winner)) {
        new name[32], flags_str[32];
        get_user_name(winner, name, charsmax(name));
        get_pcvar_string(pcv_flags, flags_str, charsmax(flags_str));

        print_msg(0, "^3%s ^1a fost ales admin temporar cu ^4%d ^1voturi!", name, max_votes);
        
        g_admins_elected_count++; // Incrementam numarul de admini alesi
        set_user_flags(winner, read_flags(flags_str));
        
        print_msg(0, "Admini votati pe aceasta harta: ^4%d/%d", g_admins_elected_count, get_pcvar_num(pcv_maxadmins));
    }
}
