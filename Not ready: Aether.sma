
#include <engine>
#include <hamsandwich>

#define MAX_PLAYERS 32
#define DANGER_RADIUS 600.0
#define NEAR_MISS_DIST 45.0 

new Float:gStress[33];
new bool:gHud[33];
new Float:gLastHeartbeat[33];
new Float:gLastHallucination[33];
new gHudSync;
new gMsgFade;

// Array of psychological trigger sounds
new const g_SndHallucinations[][] = {
    "weapons/explode3.wav",     // Distant Blast
    "weapons/c4_beep1.wav",     // Ghost C4
    "player/pl_step1.wav",      // Ghost Footstep Left
    "player/pl_step2.wav",      // Ghost Footstep Right
    "weapons/dryfire_pistol.wav" // Ghost Jam/Empty Click
};

public plugin_precache() {
    precache_sound("player/heartbeat1.wav");
    precache_sound("weapons/debris1.wav"); 
    for(new i = 0; i < sizeof g_SndHallucinations; i++) {
        precache_sound(g_SndHallucinations[i]);
    }
}

public plugin_init() {
    register_plugin("AETHER: PARANOIA", "2.6", "SUPER_GENIUS");

    RegisterHookChain(RG_CBasePlayer_PreThink, "OnThink", 0);
    RegisterHookChain(RG_CBasePlayer_TakeDamage, "OnDamage", 1);
    RegisterHookChain(RG_CBasePlayer_TraceAttack, "OnTraceAttack", 1);
    RegisterHookChain(RG_CBasePlayer_Killed, "OnDeath", 1);

    register_clcmd("say /stress", "CmdStress");

    gHudSync = CreateHudSyncObj();
    gMsgFade = get_user_msgid("ScreenFade");

    set_task(0.4, "HudLoop", 0, _, _, "b");
}

public CmdStress(id) {
    gHud[id] = !gHud[id];
    client_print(id, print_chat, "[AETHER] Neural Paranoia: %s", gHud[id] ? "ACTIVE" : "OFF");
}

public OnThink(id) {
    if (!is_user_alive(id)) return;

    static Float:origin[3], Float:eOrigin[3];
    get_entvar(id, var_origin, origin);
    new Float:hp; get_entvar(id, var_health, hp);
    
    new team = get_member(id, m_iTeam);
    new bool:threatDetected = false;
    new Float:closestDist = DANGER_RADIUS;

    // 1. ADVANCED THREAT SCAN
    for (new i = 1; i <= MAX_PLAYERS; i++) {
        if (is_user_alive(i) && get_member(i, m_iTeam) != team) {
            get_entvar(i, var_origin, eOrigin);
            new Float:dist = get_distance_f(origin, eOrigin);

            if (dist < DANGER_RADIUS && (is_in_viewcone(id, eOrigin) || is_in_viewcone(i, origin))) {
                if (is_visible(id, i)) {
                    threatDetected = true;
                    if (dist < closestDist) closestDist = dist;
                }
            }
        }
    }

    // 2. STRESS DYNAMICS (Very slow recovery)
    if (threatDetected) {
        new Float:proximityMult = 1.0 + (1.0 - (closestDist / DANGER_RADIUS));
        gStress[id] = floatmin(100.0, gStress[id] + (0.6 * proximityMult));
    } else {
        new flags = get_entvar(id, var_flags);
        new Float:recoveryRate = (flags & FL_DUCKING) ? 0.12 : 0.04; 
        
        new Float:stressFloor = (hp < 30.0) ? 65.0 : 0.0;
        if (gStress[id] > stressFloor) gStress[id] -= recoveryRate;
    }

    new Float:now = get_gametime();
    new Float:s = gStress[id];

    // 3. THE AURAL DISTORTION ENGINE (Hallucinations)
    if (s > 80.0 && (now - gLastHallucination[id] > random_float(7.0, 15.0))) {
        new soundIndex = random_num(0, sizeof g_SndHallucinations - 1);
        
        // Play sound directly to player's client only
        client_cmd(id, "spk %s", g_SndHallucinations[soundIndex]);
        
        // Visual twitch to match the sound panic
        message_begin(MSG_ONE_UNRELIABLE, gMsgFade, _, id);
        write_short(512); write_short(256); write_short(0);
        write_byte(255); write_byte(255); write_byte(255); write_byte(30);
        message_end();
        
        gLastHallucination[id] = now;
    }

    // 4. HEARTBEAT & PULSE
    if (s > 50.0) {
        if (now - gLastHeartbeat[id] > (1.1 - (s / 100.0))) {
            emit_sound(id, CHAN_STATIC, "player/heartbeat1.wav", 0.4, ATTN_NORM, 0, PITCH_NORM);
            
            // Pulse Effect
            message_begin(MSG_ONE_UNRELIABLE, gMsgFade, _, id);
            write_short(1024); write_short(400); write_short(0);
            write_byte(hp < 25.0 ? 180 : 0); // Red pulse if dying
            write_byte(0); write_byte(0); 
            write_byte(floatround(s / 2.0)); 
            message_end();
            
            gLastHeartbeat[id] = now;
        }
    }

    // 5. ADRENALINE BUFF (Speed)
    if (s > 85.0) set_entvar(id, var_maxspeed, 330.0);
}

public OnTraceAttack(victim, attacker, Float:damage, Float:dir[3], tr, bits) {
    if (!is_user_alive(victim) || !is_user_alive(attacker)) return;

    static Float:endPos[3], Float:vOrigin[3];
    get_tr2(tr, TR_vecEndPos, endPos);
    get_entvar(victim, var_origin, vOrigin);
    vOrigin[2] += 26.0; 

    if (get_distance_f(endPos, vOrigin) < NEAR_MISS_DIST) {
        gStress[victim] = floatmin(100.0, gStress[victim] + 15.0);
        emit_sound(victim, CHAN_AUTO, "weapons/debris1.wav", 0.5, ATTN_NORM, 0, PITCH_HIGH);
    }
}

public OnDamage(id, ent, attacker, Float:damage, bits) {
    if (is_user_alive(id)) {
        // High stress = 25% extra damage taken (Panic makes you vulnerable)
        if (gStress[id] > 80.0) SetHamParamFloat(4, damage * 1.25);
        gStress[id] = floatmin(100.0, gStress[id] + (damage * 0.9));
    }
}

public OnDeath(victim, attacker) {
    gStress[victim] = 0.0;
}

public HudLoop() {
    static iPlayers[32], iNum, id;
    get_players(iPlayers, iNum, "a");

    for (new i = 0; i < iNum; i++) {
        id = iPlayers[i];
        if (!gHud[id]) continue;

        new Float:s = gStress[id];
        new Float:hp; get_entvar(id, var_health, hp);

        if (hp < 25.0) {
            set_hudmessage(255, 0, 0, 0.02, 0.9, 0, 0.0, 0.5, 0.0, 0.0, -1);
            ShowSyncHudMsg(id, gHudSync, "[ STATE: HYPOVOLEMIC SHOCK ]^nNEURAL LOCK: %.0f%%", s);
        } else {
            set_hudmessage(100, 255, 100, 0.02, 0.9, 0, 0.0, 0.5, 0.0, 0.0, -1);
            if (s < 40.0) ShowSyncHudMsg(id, gHudSync, "[ NEURAL: STABLE ]^nLOAD: %.0f%%", s);
            else if (s < 80.0) ShowSyncHudMsg(id, gHudSync, "[ NEURAL: ALERT ]^nLOAD: %.0f%%", s);
            else ShowSyncHudMsg(id, gHudSync, "[ NEURAL: OVERLOAD (PARANOIA) ]^nLOAD: %.0f%%", s);
        }
    }
}
