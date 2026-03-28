#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <fun>
#include <hamsandwich>

#define PLUGIN "Advanced Utility Grenades"
#define VERSION "1.0
#define AUTHOR "AI"

// Offsets si Constante
#define OFFSET_TEAM 114
#define OFFSET_LINUX 5
#define HE_RADIUS 750.0
#define SMOKE_RADIUS 600.0

new const LASER_SPRITE[] = "sprites/laserbeam.spr"
new const EXPLOSION_SPRITE[] = "sprites/zerogxplode.spr"

new g_sModelIndexLaser, g_sModelIndexExplo
new g_msgTeamInfo, g_msgScoreInfo

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)
    register_forward(FM_Think, "fw_Think")
    
    g_msgTeamInfo = get_user_msgid("TeamInfo")
    g_msgScoreInfo = get_user_msgid("ScoreInfo")
}

public plugin_precache() {
    g_sModelIndexLaser = precache_model(LASER_SPRITE)
    g_sModelIndexExplo = precache_model(EXPLOSION_SPRITE)
    precache_sound("weapons/c4_explode1.wav")
}

public fw_Think(ent) {
    if (!pev_valid(ent)) return FMRES_IGNORED

    static classname[32]; pev(ent, pev_classname, classname, charsmax(classname))
    if (!equal(classname, "grenade")) return FMRES_IGNORED

    new Float:dmgtime; pev(ent, pev_dmgtime, dmgtime)
    if (dmgtime > get_gametime() || dmgtime <= 0.0) return FMRES_IGNORED

    static model[32]; pev(ent, pev_model, model, charsmax(model))
    new Float:origin[3]; pev(ent, pev_origin, origin)

    // --- HE GRENADE ---
    if (contain(model, "w_hegrenade.mdl") != -1) {
        handle_he_advanced(ent, origin)
    }
    // --- SMOKE GRENADE ---
    else if (contain(model, "w_smokegrenade.mdl") != -1) {
        handle_smoke_advanced(ent, origin)
        engfunc(EngFunc_RemoveEntity, ent)
        return FMRES_SUPERCEDE
    }
    // --- FLASHBANG ---
    else if (contain(model, "w_flashbang.mdl") != -1) {
        handle_flash_teleport(ent, origin)
        engfunc(EngFunc_RemoveEntity, ent)
        return FMRES_SUPERCEDE
    }
    return FMRES_IGNORED
}

public handle_he_advanced(ent, Float:origin[3]) {
    create_blast_visuals(origin, 255, 0, 0)
    emit_sound(ent, CHAN_WEAPON, "weapons/c4_explode1.wav", 1.0, ATTN_NORM, 0, PITCH_NORM)

    new players[32], num, target, owner = pev(ent, pev_owner)
    get_players(players, num, "a")

    for (new i = 0; i < num; i++) {
        target = players[i]
        new Float:tOrigin[3]; pev(target, pev_origin, tOrigin)
        
        if (get_distance_f(origin, tOrigin) <= HE_RADIUS) {
            // Damage de explozie
            fane_damage(target, 190.0, owner)
            
            // Efect de ardere (Doar Damage, fara sprite)
            new data[1]; data[0] = target
            set_task(0.5, "apply_burn_dmg", target + 1234, data, 1, "a", 10)
        }
    }
}

public apply_burn_dmg(data[1]) {
    new id = data[0]
    if (!is_user_alive(id)) return

    // Damage periodic (Burn)
    set_user_health(id, get_user_health(id) - 10)
    
    // Un mic flash rosu pe ecranul jucatorului ca sa stie ca "arde"
    message_begin(MSG_ONE_UNRELIABLE, get_user_msgid("ScreenFade"), _, id)
    write_short(1<<10); write_short(1<<10); write_short(0x0000)
    write_byte(255); write_byte(0); write_byte(0); write_byte(70)
    message_end()
}

public handle_smoke_advanced(ent, Float:origin[3]) {
    new owner = pev(ent, pev_owner)
    if (!is_user_connected(owner)) return

    new ownerTeam = get_pdata_int(owner, OFFSET_TEAM, OFFSET_LINUX)
    create_blast_visuals(origin, 0, 255, 0)

    new players[32], num, target; get_players(players, num, "a")
    for (new i = 0; i < num; i++) {
        target = players[i]
        new Float:tOrigin[3]; pev(target, pev_origin, tOrigin)
        
        if (get_distance_f(origin, tOrigin) <= SMOKE_RADIUS) {
            new targetTeam = get_pdata_int(target, OFFSET_TEAM, OFFSET_LINUX)
            if (targetTeam != ownerTeam && targetTeam != 0 && targetTeam != 3) {
                update_player_team(target, ownerTeam)
            } else if (targetTeam == ownerTeam) {
                set_user_health(target, get_user_health(target) + 50)
            }
        }
    }
}

public update_player_team(id, team) {
    set_pdata_int(id, OFFSET_TEAM, team, OFFSET_LINUX)
    
    static const team_names[][] = { "UNASSIGNED", "TERRORIST", "CT", "SPECTATOR" }
    
    message_begin(MSG_ALL, g_msgTeamInfo)
    write_byte(id)
    write_string(team_names[team])
    message_end()

    message_begin(MSG_ALL, g_msgScoreInfo)
    write_byte(id)
    write_short(get_user_frags(id))
    write_short(get_user_deaths(id))
    write_short(0)
    write_short(team)
    message_end()

    client_print(id, print_center, "TEAM CONVERTED!")
}

public handle_flash_teleport(ent, Float:origin[3]) {
    new owner = pev(ent, pev_owner)
    if (!is_user_connected(owner)) return

    new ownerTeam = get_pdata_int(owner, OFFSET_TEAM, OFFSET_LINUX)
    new players[32], num, teamList[32], teamCount = 0
    get_players(players, num, "a")

    for(new i=0; i<num; i++) {
        if(get_pdata_int(players[i], OFFSET_TEAM, OFFSET_LINUX) == ownerTeam)
            teamList[teamCount++] = players[i]
    }

    new teammate = (teamCount > 1) ? teamList[random(teamCount)] : owner
    
    origin[2] += 45.0
    engfunc(EngFunc_SetOrigin, teammate, origin)
    drop_to_floor(teammate)
    
    // Efect vizual de teleportare (Flash alb scurt)
    message_begin(MSG_ONE_UNRELIABLE, get_user_msgid("ScreenFade"), _, teammate)
    write_short(1<<10); write_short(1<<10); write_short(0x0000)
    write_byte(255); write_byte(255); write_byte(255); write_byte(200)
    message_end()
}

public fane_damage(target, Float:dmg, attacker) {
    new Float:hp; pev(target, pev_health, hp)
    if (hp <= dmg) 
        ExecuteHamB(Ham_Killed, target, attacker, 0)
    else 
        set_user_health(target, floatround(hp - dmg))
}

public create_blast_visuals(Float:origin[3], r, g, b) {
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
    write_byte(TE_BEAMCYLINDER)
    engfunc(EngFunc_WriteCoord, origin[0]); engfunc(EngFunc_WriteCoord, origin[1]); engfunc(EngFunc_WriteCoord, origin[2])
    engfunc(EngFunc_WriteCoord, origin[0]); engfunc(EngFunc_WriteCoord, origin[1]); engfunc(EngFunc_WriteCoord, origin[2] + 250.0)
    write_short(g_sModelIndexLaser); write_byte(0); write_byte(0); write_byte(10); write_byte(60); write_byte(0)
    write_byte(r); write_byte(g); write_byte(b); write_byte(255); write_byte(0)
    message_end()

    message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
    write_byte(TE_EXPLOSION); engfunc(EngFunc_WriteCoord, origin[0]); engfunc(EngFunc_WriteCoord, origin[1]); engfunc(EngFunc_WriteCoord, origin[2])
    write_short(g_sModelIndexExplo); write_byte(90); write_byte(15); write_byte(0) 
    message_end()
}
