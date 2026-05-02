#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <hamsandwich>
#include <cstrike>

#define PLUGIN "Drone Ghost Final"
#define VERSION "7.0"
#define AUTHOR "Gemini_AI"

new bool:g_IsDrone[33];
new bool:g_HasDroneAccess[33];
new Float:g_OldOrigin[33][3];

new pcvar_price;

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    
    register_impulse(201, "Cmd_ToggleDrone");
    register_clcmd("say /drona", "Cmd_BuyDrone");
    register_clcmd("say_team /drona", "Cmd_BuyDrone");
    
    pcvar_price = register_cvar("amx_drone_price", "2500");
    
    // Detectăm când drona lovește un perete
    register_touch("player", "*", "Fwd_DroneTouch");
    
    // Blocăm damage-ul primit cât timp ești dronă
    RegisterHam(Ham_TakeDamage, "player", "Fwd_TakeDamage");
}

public Cmd_BuyDrone(id) {
    if(!is_user_alive(id)) {
        client_print_color(id, print_team_default, "^4[DRONA] ^1Trebuie sa fii viu pentru a cumpara!");
        return PLUGIN_HANDLED;
    }
    
    if(g_HasDroneAccess[id]) {
        client_print_color(id, print_team_default, "^4[DRONA] ^1Ai deja o drona! Apasa ^3T ^1pentru lansare.");
        return PLUGIN_HANDLED;
    }
    
    new money = cs_get_user_money(id);
    new price = get_pcvar_num(pcvar_price);
    
    if(money < price) {
        client_print_color(id, print_team_default, "^4[DRONA] ^1Nu ai destui bani! Ai nevoie de ^3%d$^1.", price);
        return PLUGIN_HANDLED;
    }
    
    cs_set_user_money(id, money - price);
    g_HasDroneAccess[id] = true;
    client_print_color(id, print_team_default, "^4[DRONA] ^1Cumparata cu succes! Apasa tasta ^3T ^1pentru decolare.");
    
    return PLUGIN_HANDLED;
}

public Cmd_ToggleDrone(id) {
    if (!is_user_alive(id)) return PLUGIN_CONTINUE;

    if (!g_IsDrone[id]) {
        if(!g_HasDroneAccess[id]) {
            client_print_color(id, print_team_default, "^4[DRONA] ^1Nu detii o drona. Scrie ^3/drona ^1pentru a cumpara.");
            return PLUGIN_HANDLED;
        }
        ActivateDrone(id);
    } else {
        DeactivateDrone(id);
    }

    return PLUGIN_HANDLED;
}

public ActivateDrone(id) {
    pev(id, pev_origin, g_OldOrigin[id]);
    
    g_IsDrone[id] = true;
    g_HasDroneAccess[id] = false; // Se consumă la utilizare

    // Setări mișcare și invizibilitate
    set_pev(id, pev_movetype, MOVETYPE_FLY);
    set_rendering(id, kRenderFxNone, 0, 0, 0, kRenderTransAdd, 0);

    // Activăm loop-ul de control
    set_task(0.1, "DroneLoop", id + 100, _, _, "b");
    client_cmd(id, "nightvision");
    
    // Ascundem HUD-ul de joc
    message_begin(MSG_ONE, get_user_msgid("HideWeapon"), _, id);
    write_byte((1<<3) | (1<<4) | (1<<5) | (1<<6)); 
    message_end();
}

public DeactivateDrone(id) {
    if(!g_IsDrone[id]) return;
    
    g_IsDrone[id] = false;
    remove_task(id + 100);

    // Teleportare înapoi la poziția inițială
    set_pev(id, pev_origin, g_OldOrigin[id]);
    set_pev(id, pev_movetype, MOVETYPE_WALK);
    set_rendering(id, kRenderFxNone, 0, 0, 0, kRenderNormal, 255);

    // Revenire HUD normal
    message_begin(MSG_ONE, get_user_msgid("HideWeapon"), _, id);
    write_byte(0);
    message_end();
    
    // Fix vizual pentru armă și nightvision
    client_cmd(id, "lastinv; wait; lastinv; nightvision");
}

public DroneLoop(id) {
    id -= 100;
    if(!is_user_alive(id) || !g_IsDrone[id]) return;

    // Ascundem arma (insistent, în fiecare frame de task)
    set_pev(id, pev_viewmodel2, "");
    set_pev(id, pev_weaponmodel2, "");

    // Aplicăm viteza constantă ÎNAINTE
    new Float:fVelocity[3];
    velocity_by_aim(id, 450, fVelocity); 
    set_pev(id, pev_velocity, fVelocity);

    // HUD Militar (Vizorul verde)
    set_hudmessage(0, 255, 0, 0.02, 0.2, 0, 0.0, 0.12, 0.0, 0.0, -1);
    show_hudmessage(id, "[ MODE: REMOTE DRONE ]^nSIGNAL: STABLE^nBATTERY: 98%%^n^n[T] RECALL DEVICE");

    set_hudmessage(0, 255, 0, -1.0, 0.1, 0, 0.0, 0.12, 0.0, 0.0, -1);
    show_hudmessage(id, "[ ------------------------------------------------------ ]");
    set_hudmessage(0, 255, 0, -1.0, 0.9, 0, 0.0, 0.12, 0.0, 0.0, -1);
    show_hudmessage(id, "[ ------------------------------------------------------ ]");

    // Dacă apasă butoanele de acțiune, se întoarce la corp
    if(pev(id, pev_button) & (IN_ATTACK | IN_ATTACK2 | IN_USE)) {
        DeactivateDrone(id);
    }
}

public Fwd_DroneTouch(id, world) {
    if(!is_user_alive(id) || !g_IsDrone[id]) return;
    
    // Coliziunea cu orice obiect solid forțează revenirea
    DeactivateDrone(id);
}

public Fwd_TakeDamage(id) {
    // Drona nu poate lua damage în timpul zborului
    if(g_IsDrone[id]) return HAM_SUPERCEDE;
    return HAM_IGNORED;
}

public client_disconnected(id) {
    if(g_IsDrone[id]) DeactivateDrone(id);
    g_HasDroneAccess[id] = false;
}
