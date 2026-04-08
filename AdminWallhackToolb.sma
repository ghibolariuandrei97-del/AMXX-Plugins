#include <amxmodx>
#include <engine>

#define PLUGIN "Admin Wallhack Tool"
#define VERSION "1.0"
#define AUTHOR "Ai"

#define ADMIN_WH_ACCESS ADMIN_BAN
#define REFRESH_RATE 0.6 // Rata de refresh stabila

new bool:g_is_detecting[33];
new g_spr_beam;
new g_maxplayers;

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    register_clcmd("say /wh", "cmd_toggle_detector");
    register_clcmd("say_team /wh", "cmd_toggle_detector");
    g_maxplayers = get_maxplayers();
}

public plugin_precache() {
    g_spr_beam = precache_model("sprites/zbeam4.spr");
}

public client_disconnected(id) {
    if (g_is_detecting[id]) {
        g_is_detecting[id] = false;
        remove_task(id);
    }
}

public cmd_toggle_detector(id) {
    if (!(get_user_flags(id) & ADMIN_WH_ACCESS)) return PLUGIN_HANDLED;
    
    g_is_detecting[id] = !g_is_detecting[id];
    
    if (g_is_detecting[id]) {
        set_task(REFRESH_RATE, "draw_visuals", id, _, _, "b");
        client_print(id, print_chat, "[WH] Mod Vizualizare prin pereti: ACTIV");
    } else {
        remove_task(id);
        client_print(id, print_chat, "[WH] Mod Vizualizare prin pereti: DEZACTIVAT");
    }
    return PLUGIN_HANDLED;
}

public draw_visuals(admin) {
    if (!is_user_connected(admin)) return;

    new target = entity_get_int(admin, EV_INT_iuser2);
    if (!(1 <= target <= g_maxplayers) || !is_user_alive(target))
        return;

    new target_team = get_user_team(target);

    for (new i = 1; i <= g_maxplayers; i++) {
        if (!is_user_alive(i) || i == target || get_user_team(i) == target_team) 
            continue;

        static Float:origin[3];
        entity_get_vector(i, EV_VEC_origin, origin);
        
        new x = floatround(origin[0]);
        new y = floatround(origin[1]);
        new z = floatround(origin[2]);

        // --- 1. LUMINA DINAMICA (DLIGHT) ---
        // Aceasta creeaza o aura rosie pe podea/pereti care se vede prin ziduri
        message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, admin);
        write_byte(TE_DLIGHT); 
        write_coord(x);         // X
        write_coord(y);         // Y
        write_coord(z);         // Z
        write_byte(15);         // Radius (cat de mare e aura)
        write_byte(255);        // R
        write_byte(0);          // G
        write_byte(0);          // B
        write_byte(8);          // Viata (0.8s)
        write_byte(0);          // Decay rate
        message_end();

        // --- 2. PUNCTUL / LINIA VERTICALA (Vizibila prin pereti) ---
        // Desenam o linie verticala foarte scurta si groasa (arata ca un punct mare)
        // Laserele verticale in GoldSrc sunt mult mai vizibile prin obstacole
        message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, admin);
        write_byte(TE_BEAMPOINTS);
        write_coord(x); write_coord(y); write_coord(z + 20); // Start
        write_coord(x); write_coord(y); write_coord(z + 22); // End
        write_short(g_spr_beam);
        write_byte(0); write_byte(0);
        write_byte(8);          // Viata (0.8s)
        write_byte(20);         // Grosime (Width) - Aici o faci cat de mare vrei
        write_byte(0);          // Noise
        write_byte(255); write_byte(0); write_byte(0); // Rosu
        write_byte(200);        // Luminozitate
        write_byte(0);
        message_end();

        // --- 3. LINIA DE CONEXIUNE (Spider-Web) ---
        message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, admin);
        write_byte(TE_BEAMENTS);
        write_short(target);
        write_short(i);
        write_short(g_spr_beam);
        write_byte(0); write_byte(0);
        write_byte(8); 
        write_byte(2); 
        write_byte(0);
        write_byte(255); write_byte(255); write_byte(255);
        write_byte(50); 
        write_byte(0);
        message_end();
    }
}
