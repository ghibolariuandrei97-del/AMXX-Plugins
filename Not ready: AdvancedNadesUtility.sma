#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <fun>
#include <hamsandwich>

#define PLUGIN "Advanced Nades Utility"
#define VERSION "1.0"
#define AUTHOR "AI"

#define OFFSET_TEAM 114
#define OFFSET_LINUX 5
#define m_rgAmmo_Slot0 376

new const LASER_SPRITE[] = "sprites/laserbeam.spr"
new const EXPLOSION_SPRITE[] = "sprites/zerogxplode.spr"

new g_sModelIndexLaser, g_sModelIndexExplo
new g_pCvarFlashType, g_pCvarHeKnock, g_pCvarHeRadius, g_pCvarHeDmg
new g_pCvarSmokeRadius, g_pCvarSmokeHeal, g_pCvarPlantLive, g_pCvarNadeImpact

new Float:g_fLastPlant[33]
new g_msgScreenFade

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)
    
    RegisterHam(Ham_Think, "grenade", "fw_GrenadeThink_Post", 1)
    register_forward(FM_Touch, "fw_GlobalTouch") 
    register_logevent("logevent_round_end", 2, "1=Round_End")
    
    RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_hegrenade", "fw_PlantMine")
    RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_smokegrenade", "fw_PlantMine")
    RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_flashbang", "fw_PlantMine")
    
    g_pCvarFlashType = register_cvar("amx_flash_teleporttype", "0")
    g_pCvarHeKnock = register_cvar("amx_hegrenade_knockback", "1200.0")
    g_pCvarHeRadius = register_cvar("amx_hegrenade_radius", "750.0")
    g_pCvarHeDmg = register_cvar("amx_hegrenade_damage", "50.0")
    g_pCvarSmokeRadius = register_cvar("amx_smoke_radius", "600.0")
    g_pCvarSmokeHeal = register_cvar("amx_smoke_heal", "50.0")
    g_pCvarPlantLive = register_cvar("amx_plant_live", "0") 
    g_pCvarNadeImpact = register_cvar("amx_nade_impact", "1")

    g_msgScreenFade = get_user_msgid("ScreenFade")
}

public plugin_precache() {
    g_sModelIndexLaser = precache_model(LASER_SPRITE)
    g_sModelIndexExplo = precache_model(EXPLOSION_SPRITE)
}

public logevent_round_end() {
    if (get_pcvar_num(g_pCvarPlantLive) == 0) {
        new ent = -1
        while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "grenade_mine")) != 0) {
            if (pev_valid(ent)) engfunc(EngFunc_RemoveEntity, ent)
        }
    }
}

public fw_GlobalTouch(ent, victim) {
    if (!pev_valid(ent)) return FMRES_IGNORED

    static classname[32]; pev(ent, pev_classname, classname, charsmax(classname))

    if (get_pcvar_num(g_pCvarNadeImpact) == 1 && equal(classname, "grenade")) {
        static model[64]; pev(ent, pev_model, model, charsmax(model))
        if (contain(model, "w_hegrenade.mdl") != -1 || contain(model, "w_smokegrenade.mdl") != -1 || contain(model, "w_flashbang.mdl") != -1) {
            set_pev(ent, pev_dmgtime, get_gametime()) 
        }
        return FMRES_IGNORED
    }

    if (equal(classname, "grenade_mine")) {
        if (!is_user_alive(victim)) return FMRES_IGNORED

        new type = pev(ent, pev_iuser1), owner = pev(ent, pev_owner)
        new Float:origin[3]; pev(ent, pev_origin, origin)
        
        if (victim == owner && (get_gametime() - g_fLastPlant[owner] < 1.2)) return FMRES_IGNORED

        new vTeam = get_pdata_int(victim, OFFSET_TEAM, OFFSET_LINUX)
        new oTeam = is_user_connected(owner) ? get_pdata_int(owner, OFFSET_TEAM, OFFSET_LINUX) : 0

        if (type == 1 && (vTeam != oTeam || get_cvar_num("mp_friendlyfire") == 1)) {
            create_blast_visuals(origin, 255, 0, 0, true)
            apply_he_effects(ent, origin)
            engfunc(EngFunc_RemoveEntity, ent)
        }
        else if (type == 2 && vTeam == oTeam) {
            handle_smoke_heal(ent, origin)
            engfunc(EngFunc_RemoveEntity, ent)
        }
        else if (type == 3) {
            teleport_to_team_spawn(victim)
            engfunc(EngFunc_RemoveEntity, ent)
        }
    }
    return FMRES_IGNORED
}

public fw_GrenadeThink_Post(ent) {
    if (!pev_valid(ent)) return HAM_IGNORED
    new Float:dmgtime; pev(ent, pev_dmgtime, dmgtime)
    if (dmgtime == 0.0 || dmgtime > get_gametime()) return HAM_IGNORED

    static model[64]; pev(ent, pev_model, model, charsmax(model))
    new Float:origin[3]; pev(ent, pev_origin, origin)

    if (contain(model, "w_hegrenade.mdl") != -1) {
        create_blast_visuals(origin, 255, 0, 0, true)
        apply_he_effects(ent, origin)
        engfunc(EngFunc_RemoveEntity, ent); return HAM_SUPERCEDE
    }
    else if (contain(model, "w_smokegrenade.mdl") != -1) {
        handle_smoke_heal(ent, origin)
        engfunc(EngFunc_RemoveEntity, ent); return HAM_SUPERCEDE
    }
    else if (contain(model, "w_flashbang.mdl") != -1) {
        handle_flash_teleport(ent, origin)
        engfunc(EngFunc_RemoveEntity, ent); return HAM_SUPERCEDE
    }
    return HAM_IGNORED
}

public apply_he_effects(grenade_ent, Float:origin[3]) {
    new owner = pev(grenade_ent, pev_owner)
    new Float:radius = get_pcvar_float(g_pCvarHeRadius)
    new Float:knockback = get_pcvar_float(g_pCvarHeKnock)
    new Float:extraDmg = get_pcvar_float(g_pCvarHeDmg)
    new bool:ff_on = get_cvar_num("mp_friendlyfire") == 1
    new oTeam = is_user_connected(owner) ? get_pdata_int(owner, OFFSET_TEAM, OFFSET_LINUX) : 0

    new ent = -1
    while ((ent = engfunc(EngFunc_FindEntityInSphere, ent, origin, radius)) != 0) {
        if (!pev_valid(ent)) continue
        
        static classname[32]; pev(ent, pev_classname, classname, charsmax(classname))
        new bool:isPlayer = is_user_alive(ent) ? true : false
        
        // If it's a player, check Friendly Fire
        if (isPlayer) {
            if (!ff_on && owner != ent) {
                if (get_pdata_int(ent, OFFSET_TEAM, OFFSET_LINUX) == oTeam) continue
            }
        } 
        // If not a player, check if it's a weapon/item (weaponbox = dropped, armoury = map spawn)
        else if (!equal(classname, "weaponbox") && !equal(classname, "armoury_entity") && !equal(classname, "item_thighpack")) {
            continue
        }

        new Float:entOrigin[3]; pev(ent, pev_origin, entOrigin)
        new Float:distance = get_distance_f(origin, entOrigin)
        if (distance < 1.0) distance = 1.0 
        
        new Float:push = knockback * (1.0 - (distance / radius))
        new Float:curVel[3]; pev(ent, pev_velocity, curVel)
        new Float:vel[3]
        
        vel[0] = curVel[0] + (entOrigin[0] - origin[0]) * (push / distance)
        vel[1] = curVel[1] + (entOrigin[1] - origin[1]) * (push / distance)
        vel[2] = curVel[2] + (push * 0.45)
        
        // For armoury_entities (static map weapons), we must change movetype to push them
        if (equal(classname, "armoury_entity")) {
            set_pev(ent, pev_movetype, MOVETYPE_TOSS)
        }

        set_pev(ent, pev_velocity, vel)

        if (isPlayer) {
            new Float:hp; pev(ent, pev_health, hp)
            if (hp <= extraDmg) {
                ExecuteHamB(Ham_Killed, ent, is_user_connected(owner) ? owner : 0, 0)
            } else {
                ExecuteHamB(Ham_TakeDamage, ent, grenade_ent, owner, extraDmg, DMG_BLAST)
                set_user_glow(ent, 255, 0, 0)
            }
        }
    }
}

public handle_smoke_heal(ent, Float:origin[3]) {
    new owner = pev(ent, pev_owner)
    if(!is_user_connected(owner)) return
    new oTeam = get_pdata_int(owner, OFFSET_TEAM, OFFSET_LINUX)
    create_blast_visuals(origin, 0, 255, 0, false)
    new players[32], num, target; get_players(players, num, "a")
    for (new i = 0; i < num; i++) {
        target = players[i]
        if (get_pdata_int(target, OFFSET_TEAM, OFFSET_LINUX) != oTeam) continue
        new Float:tOrigin[3]; pev(target, pev_origin, tOrigin)
        if (get_distance_f(origin, tOrigin) <= get_pcvar_float(g_pCvarSmokeRadius)) {
            new hp = get_user_health(target)
            set_user_health(target, min(hp + get_pcvar_num(g_pCvarSmokeHeal), 200)) 
            set_user_glow(target, 0, 255, 0)
        }
    }
}

public handle_flash_teleport(ent, Float:origin[3]) {
    new owner = pev(ent, pev_owner)
    if(!is_user_connected(owner)) return
    
    new type = get_pcvar_num(g_pCvarFlashType), target = 0
    if (type == 1) target = owner
    else {
        new players[32], num, teamList[32], teamCount = 0, oTeam = get_pdata_int(owner, OFFSET_TEAM, OFFSET_LINUX)
        get_players(players, num, "a")
        for(new i = 0; i < num; i++) {
            if(get_pdata_int(players[i], OFFSET_TEAM, OFFSET_LINUX) == oTeam && players[i] != owner)
                teamList[teamCount++] = players[i]
        }
        target = (teamCount > 0) ? teamList[random(teamCount)] : owner
    }
    
    if (is_user_connected(target) && is_user_alive(target)) {
        create_blast_visuals(origin, 255, 255, 255, false)
        engfunc(EngFunc_SetOrigin, target, origin)
        
        message_begin(MSG_ONE, g_msgScreenFade, _, target)
        write_short(1<<12); write_short(1<<8); write_short(0x0000)
        write_byte(0); write_byte(0); write_byte(0); write_byte(255)
        message_end()

        set_task(0.1, "check_and_fix_stuck", target)
    }
}

public check_and_fix_stuck(id) {
    if (!is_user_connected(id) || !is_user_alive(id)) return
    
    if (is_player_stuck(id)) {
        new Float:origin[3]; pev(id, pev_origin, origin)
        new Float:newOrigin[3]
        for (new i = 1; i < 15; i++) {
            newOrigin = origin; newOrigin[2] += (i * 12.0) 
            if (is_point_vacant(newOrigin, id)) {
                engfunc(EngFunc_SetOrigin, id, newOrigin); return
            }
        }
        teleport_to_team_spawn(id)
    }
}

public teleport_to_team_spawn(id) {
    if (!is_user_connected(id) || !is_user_alive(id)) return
    
    new team = get_pdata_int(id, OFFSET_TEAM, OFFSET_LINUX)
    static const spawn_classes[][] = { "", "info_player_deathmatch", "info_player_start" }
    new const target_idx = (team == 1) ? 1 : 2
    new ent = -1, spawns[64], count = 0
    while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", spawn_classes[target_idx])) != 0) {
        spawns[count++] = ent
        if (count >= 64) break
    }
    if (count > 0) {
        new Float:origin[3]; pev(spawns[random(count)], pev_origin, origin); origin[2] += 25.0
        
        message_begin(MSG_ONE, g_msgScreenFade, _, id)
        write_short(1<<12); write_short(1<<8); write_short(0x0000)
        write_byte(0); write_byte(0); write_byte(0); write_byte(255)
        message_end()
        
        engfunc(EngFunc_SetOrigin, id, origin)
    }
}

public fw_PlantMine(weapon_ent) {
    new id = pev(weapon_ent, pev_owner)
    if (!is_user_alive(id)) return HAM_IGNORED
    new Float:fCurTime = get_gametime()
    if (fCurTime - g_fLastPlant[id] < 0.7) return HAM_IGNORED
    g_fLastPlant[id] = fCurTime
    new type = 0, ammo_id = 0
    static classname[32]; pev(weapon_ent, pev_classname, classname, charsmax(classname))
    if (equal(classname, "weapon_hegrenade")) { type = 1; ammo_id = 12; }
    else if (equal(classname, "weapon_smokegrenade")) { type = 2; ammo_id = 13; }
    else if (equal(classname, "weapon_flashbang")) { type = 3; ammo_id = 11; }
    if (type > 0) {
        new ammo = get_pdata_int(id, m_rgAmmo_Slot0 + ammo_id, OFFSET_LINUX)
        if (ammo <= 0) return HAM_IGNORED
        new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"))
        if (ent) {
            new Float:origin[3]; pev(id, pev_origin, origin)
            set_pev(ent, pev_classname, "grenade_mine"); set_pev(ent, pev_iuser1, type); set_pev(ent, pev_owner, id)
            if (type == 1) engfunc(EngFunc_SetModel, ent, "models/w_hegrenade.mdl")
            else if (type == 2) engfunc(EngFunc_SetModel, ent, "models/w_smokegrenade.mdl")
            else engfunc(EngFunc_SetModel, ent, "models/w_flashbang.mdl")
            engfunc(EngFunc_SetSize, ent, Float:{-4.0, -4.0, -4.0}, Float:{4.0, 4.0, 4.0})
            set_pev(ent, pev_origin, origin); set_pev(ent, pev_solid, SOLID_TRIGGER); set_pev(ent, pev_movetype, MOVETYPE_TOSS)
            set_rendering(ent, kRenderFxGlowShell, (type==1)?255:0, (type==2)?255:0, (type==3)?255:255, kRenderNormal, 16)
            set_pdata_int(id, m_rgAmmo_Slot0 + ammo_id, ammo - 1, OFFSET_LINUX)
            if (ammo - 1 <= 0) engclient_cmd(id, "lastinv")
            emit_sound(ent, CHAN_WEAPON, "weapons/c4_plant.wav", 1.0, ATTN_NORM, 0, PITCH_NORM)
            return HAM_SUPERCEDE 
        }
    }
    return HAM_IGNORED
}

public set_user_glow(id, r, g, b) {
    if (!is_user_connected(id)) return
    set_rendering(id, kRenderFxGlowShell, r, g, b, kRenderNormal, 20)
    remove_task(id); set_task(2.0, "remove_glow", id)
}
public remove_glow(id) if (is_user_connected(id)) set_rendering(id)

stock bool:is_player_stuck(id) {
    new Float:origin[3]; pev(id, pev_origin, origin)
    engfunc(EngFunc_TraceHull, origin, origin, 0, (pev(id, pev_flags) & FL_DUCKING) ? HULL_HEAD : HULL_HUMAN, id, 0)
    return (get_tr2(0, TR_StartSolid) || get_tr2(0, TR_AllSolid) || !get_tr2(0, TR_InOpen))
}
stock bool:is_point_vacant(Float:origin[3], id) {
    engfunc(EngFunc_TraceHull, origin, origin, 0, (pev(id, pev_flags) & FL_DUCKING) ? HULL_HEAD : HULL_HUMAN, id, 0)
    return (!get_tr2(0, TR_StartSolid) && !get_tr2(0, TR_AllSolid) && get_tr2(0, TR_InOpen))
}
public create_blast_visuals(Float:origin[3], r, g, b, bool:explosion) {
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
    write_byte(TE_BEAMCYLINDER)
    engfunc(EngFunc_WriteCoord, origin[0]); engfunc(EngFunc_WriteCoord, origin[1]); engfunc(EngFunc_WriteCoord, origin[2])
    engfunc(EngFunc_WriteCoord, origin[0]); engfunc(EngFunc_WriteCoord, origin[1]); engfunc(EngFunc_WriteCoord, origin[2] + 250.0)
    write_short(g_sModelIndexLaser); write_byte(0); write_byte(0); write_byte(10); write_byte(60); write_byte(0)
    write_byte(r); write_byte(g); write_byte(b); write_byte(255); write_byte(0); message_end()
    if (explosion) {
        message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
        write_byte(TE_EXPLOSION)
        engfunc(EngFunc_WriteCoord, origin[0]); engfunc(EngFunc_WriteCoord, origin[1]); engfunc(EngFunc_WriteCoord, origin[2])
        write_short(g_sModelIndexExplo); write_byte(40); write_byte(15); write_byte(0); message_end()
    }
}
