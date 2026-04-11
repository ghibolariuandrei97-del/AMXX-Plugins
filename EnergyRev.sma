/* 
 * Energy Revive Plugin for CS 1.6
 * Generated via CS 1.6 Plugin Studio
*
 */

#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <cstrike>
#include <hamsandwich>

#define PLUGIN "Energy Revive"
#define VERSION "1.0"
#define AUTHOR "AI Studio"

#define ENT_CLASSNAME "energy_revive_ball"

// Configuration Constants
new const Float:BALL_SIZE = 10.0;
new const Float:BALL_LIFE = 15.0;
new const REVIVE_HEALTH = 100;

// CVAR Pointers
new p_enemy_mode, p_reward_hp, p_screen_flash;
new g_msgScreenFade;
new g_sprite_white, g_sprite_explosion;
new g_info_target;

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    
    // Cache the string allocation for performance
    g_info_target = engfunc(EngFunc_AllocString, "info_target");
    
    // CVARs
    // energyrev_ball: 0=nothing, 1=kill, 2=explosion, 3=delete
    p_enemy_mode = register_cvar("energyrev_ball", "1");
    p_reward_hp = register_cvar("energyrev_reward", "15");
    p_screen_flash = register_cvar("energyrev_screen", "1");
    
    register_event("DeathMsg", "ev_DeathMsg", "a");
    register_event("HLTV", "ev_RoundStart", "a", "1=0", "2=0");
    
    register_touch(ENT_CLASSNAME, "player", "fwd_BallTouch");
    register_think(ENT_CLASSNAME, "fwd_BallThink");
    
    g_msgScreenFade = get_user_msgid("ScreenFade");
}

public plugin_precache() {
    g_sprite_white = precache_model("sprites/white.spr");
    g_sprite_explosion = precache_model("sprites/zerogxplode.spr");
    precache_model("sprites/glow01.spr");
}

public ev_RoundStart() {
    new ent = -1;
    while ((ent = find_ent_by_class(ent, ENT_CLASSNAME))) {
        remove_entity(ent);
    }
}

public ev_DeathMsg() {
    new victim = read_data(2);
    if (!is_user_connected(victim)) return;
    
    spawn_energy_ball(victim);
}

spawn_energy_ball(id) {
    new ent = engfunc(EngFunc_CreateNamedEntity, g_info_target);
    if (!pev_valid(ent)) return;
    
    set_pev(ent, pev_classname, ENT_CLASSNAME);
    
    new CsTeams:team = cs_get_user_team(id);
    set_pev(ent, pev_iuser1, _:team); // Team ID
    set_pev(ent, pev_iuser2, id);    // Victim ID (Owner)
    
    new Float:origin[3];
    pev(id, pev_origin, origin);
    origin[2] += 15.0;
    
    set_pev(ent, pev_origin, origin);
    set_pev(ent, pev_model, "sprites/glow01.spr");
    
    set_pev(ent, pev_solid, SOLID_TRIGGER);
    set_pev(ent, pev_movetype, MOVETYPE_TOSS);
    
    new Float:mins[3], Float:maxs[3];
    mins[0] = -BALL_SIZE; mins[1] = -BALL_SIZE; mins[2] = -BALL_SIZE;
    maxs[0] = BALL_SIZE; maxs[1] = BALL_SIZE; maxs[2] = BALL_SIZE;
    engfunc(EngFunc_SetSize, ent, mins, maxs);
    
    set_pev(ent, pev_rendermode, kRenderTransAdd);
    set_pev(ent, pev_renderamt, 200.0);
    set_pev(ent, pev_scale, 0.5);
    
    if (team == CS_TEAM_T) {
        set_pev(ent, pev_rendercolor, Float:{ 255.0, 0.0, 0.0 });
    } else {
        set_pev(ent, pev_rendercolor, Float:{ 0.0, 0.0, 255.0 });
    }
    
    set_pev(ent, pev_nextthink, get_gametime() + BALL_LIFE);
}

public fwd_BallThink(ent) {
    if (pev_valid(ent)) engfunc(EngFunc_RemoveEntity, ent);
}

public fwd_BallTouch(ent, id) {
    if (!pev_valid(ent) || !is_user_alive(id)) return;
    
    new victim = pev(ent, pev_iuser2);
    new ball_team = pev(ent, pev_iuser1);
    new toucher_team = _:cs_get_user_team(id);
    
    if (ball_team == toucher_team) {
        // Teammate Revive
        if (is_user_connected(victim) && !is_user_alive(victim)) {
            ExecuteHamB(Ham_CS_RoundRespawn, victim);
            set_user_health(victim, REVIVE_HEALTH);
            
            new reward = get_pcvar_num(p_reward_hp);
            if (reward > 0) {
                set_user_health(id, get_user_health(id) + reward);
            }
            
            if (get_pcvar_num(p_screen_flash)) {
                util_screen_fade(id, (ball_team == _:CS_TEAM_T) ? {255, 0, 0} : {0, 0, 255});
            }
            
            new Float:origin[3];
            pev(victim, pev_origin, origin);
            create_revive_effect(origin);
            
            engfunc(EngFunc_RemoveEntity, ent);
        }
    } else {
        // Enemy logic
        new mode = get_pcvar_num(p_enemy_mode);
        if (mode == 1 || mode == 2) {
            if (mode == 2) {
                new Float:origin[3];
                pev(ent, pev_origin, origin);
                create_explosion_effect(origin);
            }
            
            // Kill and give credit to the ball owner (victim)
            if (is_user_connected(victim)) {
                ExecuteHamB(Ham_Killed, id, victim, 0);
            } else {
                user_kill(id);
            }
            
            engfunc(EngFunc_RemoveEntity, ent);
        } else if (mode == 3) {
            engfunc(EngFunc_RemoveEntity, ent);
        }
    }
}

util_screen_fade(id, color[3]) {
    message_begin(MSG_ONE_UNRELIABLE, g_msgScreenFade, _, id);
    write_short(1<<12); 
    write_short(1<<12); 
    write_short(0x0000); 
    write_byte(color[0]);
    write_byte(color[1]);
    write_byte(color[2]);
    write_byte(100);    
    message_end();
}

create_explosion_effect(Float:origin[3]) {
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_EXPLOSION);
    engfunc(EngFunc_WriteCoord, origin[0]);
    engfunc(EngFunc_WriteCoord, origin[1]);
    engfunc(EngFunc_WriteCoord, origin[2]);
    write_short(g_sprite_explosion);
    write_byte(30); // scale
    write_byte(30); // framerate
    write_byte(0);  // flags
    message_end();
}

create_revive_effect(Float:origin[3]) {
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_SPRITETRAIL);
    engfunc(EngFunc_WriteCoord, origin[0]);
    engfunc(EngFunc_WriteCoord, origin[1]);
    engfunc(EngFunc_WriteCoord, origin[2]);
    engfunc(EngFunc_WriteCoord, origin[0]);
    engfunc(EngFunc_WriteCoord, origin[1]);
    engfunc(EngFunc_WriteCoord, origin[2] + 40.0);
    write_short(g_sprite_white);
    write_byte(15); 
    write_byte(10); 
    write_byte(2);  
    write_byte(40); 
    write_byte(5);  
    message_end();
}

stock set_user_health(id, health) {
    set_pev(id, pev_health, float(health));
}
