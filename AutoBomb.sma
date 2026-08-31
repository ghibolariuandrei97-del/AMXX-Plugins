#include <amxmodx>
#include <reapi>
#include <hamsandwich>

#define PLUGIN  "Auto Plant + Auto Defuse"
#define VERSION "1.3"
#define AUTHOR  "Grok"

new bool:g_bBombPlanted;
new g_iPlantedC4;
new Float:g_flC4Origin[3];
new Float:g_flDefuseProgress[33];
new Float:g_flBombPlantTime;
new Float:g_flC4Timer;

new g_pCvarEnabled;
new g_pCvarDefuseTime;
new g_pCvarDistance;
new g_pCvarKillTs;

new g_iSyncBombTimer;
new g_iSyncDefuse;
new g_iSyncPlant;

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR);

	g_pCvarEnabled    = register_cvar("apd_enabled", "1");
	g_pCvarDefuseTime = register_cvar("apd_defuse_time", "10.0");
	g_pCvarDistance   = register_cvar("apd_distance", "120.0");
	g_pCvarKillTs     = register_cvar("apd_kill_ts", "1");

	g_iSyncBombTimer = CreateHudSyncObj();
	g_iSyncDefuse    = CreateHudSyncObj();
	g_iSyncPlant     = CreateHudSyncObj();

	RegisterHookChain(RG_CSGameRules_RestartRound, "OnRestartRound", false);
	RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawn", true);
	RegisterHookChain(RG_PlantBomb, "OnBombPlanted", true);

	set_task(0.5, "Task_Check", _, _, _, "b");
	set_task(0.1, "Task_BombTimer", _, _, _, "b");
}

public OnRestartRound()
{
	g_bBombPlanted = false;
	g_iPlantedC4 = 0;
	g_flBombPlantTime = 0.0;
	arrayset(_:g_flDefuseProgress, 0, sizeof(g_flDefuseProgress));
}

public OnPlayerSpawn(const id)
{
	g_flDefuseProgress[id] = 0.0;
}

public OnBombPlanted(const id)
{
	g_bBombPlanted = true;
	g_flBombPlantTime = get_gametime();
	g_flC4Timer = get_pcvar_float(get_cvar_pointer("mp_c4timer"));
	FindPlantedC4();

	// Fade roșu + HUD doar pentru Tero
	new players[MAX_PLAYERS], num;
	get_players(players, num, "ae", "TERRORIST");

	for (new i = 0; i < num; i++)
	{
		new tid = players[i];
		if (!is_user_connected(tid))
			continue;

		// Fade roșu
		message_begin(MSG_ONE, get_user_msgid("ScreenFade"), _, tid);
		write_short(1<<10);		// duration
		write_short(1<<10);		// hold time
		write_short(0x0001);	// fade in
		write_byte(255);		// R
		write_byte(0);			// G
		write_byte(0);			// B
		write_byte(120);		// alpha
		message_end();

		// HUD plant
		set_hudmessage(255, 50, 50, -1.0, 0.30, 0, 0.0, 4.0, 0.5, 1.0, -1);
		ShowSyncHudMsg(tid, g_iSyncPlant, "BOMBA A FOST PLANTATA!");
	}
}

public Task_BombTimer()
{
	if (!g_bBombPlanted || !is_entity(g_iPlantedC4))
		return;

	new Float:timeleft = g_flC4Timer - (get_gametime() - g_flBombPlantTime);
	if (timeleft < 0.0)
		timeleft = 0.0;

	set_hudmessage(255, 255, 0, -1.0, 0.02, 0, 0.0, 0.15, 0.0, 0.0, -1);
	ShowSyncHudMsg(0, g_iSyncBombTimer, "Timp ramaș: %.1f sec", timeleft);
}

public Task_Check()
{
	if (!get_pcvar_num(g_pCvarEnabled))
		return;

	if (!g_bBombPlanted)
	{
		new players[MAX_PLAYERS], num;
		get_players(players, num, "ae", "TERRORIST");

		for (new i = 0; i < num; i++)
		{
			new id = players[i];
			if (!is_user_alive(id))
				continue;

			if (IsPlayerInBombSite(id))
			{
				ForcePlant(id);
				break;
			}
		}
	}
	else
	{
		if (!is_entity(g_iPlantedC4))
		{
			FindPlantedC4();
			if (!is_entity(g_iPlantedC4))
				return;
		}

		get_entvar(g_iPlantedC4, var_origin, g_flC4Origin);

		new Float:flRequired = get_pcvar_float(g_pCvarDefuseTime);
		new Float:flDistMax  = get_pcvar_float(g_pCvarDistance);

		new players[MAX_PLAYERS], num;
		get_players(players, num, "ae", "CT");

		new bool:bNear = false;

		for (new i = 0; i < num; i++)
		{
			new id = players[i];
			if (!is_user_alive(id))
				continue;

			new Float:origin[3];
			get_entvar(id, var_origin, origin);

			if (get_distance_f(origin, g_flC4Origin) <= flDistMax)
			{
				bNear = true;
				g_flDefuseProgress[id] += 0.5;

				// HUD pentru CT când începe defuse-ul automat
				if (g_flDefuseProgress[id] >= 0.5)
				{
					set_hudmessage(0, 255, 100, -1.0, 0.40, 0, 0.0, 0.6, 0.0, 0.0, -1);
					ShowSyncHudMsg(id, g_iSyncDefuse, "Dezamorsare automata: %.1f / %.1f", g_flDefuseProgress[id], flRequired);
				}

				if (g_flDefuseProgress[id] >= flRequired)
				{
					ForceDefuse(id);
					return;
				}
			}
			else
			{
				g_flDefuseProgress[id] = 0.0;
			}
		}

		if (!bNear)
		{
			for (new i = 1; i <= MaxClients; i++)
				g_flDefuseProgress[i] = 0.0;
		}
	}
}

bool:IsPlayerInBombSite(const id)
{
	new Float:origin[3];
	get_entvar(id, var_origin, origin);

	new ent = NULLENT;
	while ((ent = rg_find_ent_by_class(ent, "func_bomb_target")))
	{
		if (is_entity(ent) && entity_intersects_player(ent, id))
			return true;
	}

	ent = NULLENT;
	while ((ent = rg_find_ent_by_class(ent, "info_bomb_target")))
	{
		if (is_entity(ent) && entity_intersects_player(ent, id))
			return true;
	}

	return false;
}

bool:entity_intersects_player(const ent, const id)
{
	new Float:mins[3], Float:maxs[3], Float:origin[3];
	get_entvar(ent, var_absmin, mins);
	get_entvar(ent, var_absmax, maxs);
	get_entvar(id, var_origin, origin);

	return (origin[0] >= mins[0] && origin[0] <= maxs[0] &&
	        origin[1] >= mins[1] && origin[1] <= maxs[1] &&
	        origin[2] >= mins[2] && origin[2] <= maxs[2]);
}

ForcePlant(const id)
{
	if (g_bBombPlanted)
		return;

	new Float:origin[3], Float:angles[3];
	get_entvar(id, var_origin, origin);
	get_entvar(id, var_angles, angles);

	origin[2] -= 2.0;

	new bomb = rg_plant_bomb(id, origin, angles);
	if (is_entity(bomb))
	{
		g_bBombPlanted = true;
		g_iPlantedC4 = bomb;
		g_flBombPlantTime = get_gametime();
		g_flC4Timer = get_pcvar_float(get_cvar_pointer("mp_c4timer"));
		get_entvar(bomb, var_origin, g_flC4Origin);

		// Fade + HUD pentru Tero (în caz că plantarea vine din auto)
		new players[MAX_PLAYERS], num;
		get_players(players, num, "ae", "TERRORIST");

		for (new i = 0; i < num; i++)
		{
			new tid = players[i];
			if (!is_user_connected(tid))
				continue;

			message_begin(MSG_ONE, get_user_msgid("ScreenFade"), _, tid);
			write_short(1<<10);
			write_short(1<<10);
			write_short(0x0001);
			write_byte(255);
			write_byte(0);
			write_byte(0);
			write_byte(120);
			message_end();

			set_hudmessage(255, 50, 50, -1.0, 0.30, 0, 0.0, 4.0, 0.5, 1.0, -1);
			ShowSyncHudMsg(tid, g_iSyncPlant, "BOMBA A FOST PLANTATA!");
		}
	}
}

FindPlantedC4()
{
	g_iPlantedC4 = 0;

	new ent = NULLENT;
	while ((ent = rg_find_ent_by_class(ent, "planted_c4")))
	{
		if (is_entity(ent))
		{
			g_iPlantedC4 = ent;
			get_entvar(ent, var_origin, g_flC4Origin);
			return;
		}
	}
}

ForceDefuse(const id)
{
	if (!g_bBombPlanted)
		return;

	if (is_entity(g_iPlantedC4))
		set_entvar(g_iPlantedC4, var_flags, FL_KILLME);

	g_bBombPlanted = false;
	g_iPlantedC4 = 0;

	if (get_pcvar_num(g_pCvarKillTs))
	{
		new players[MAX_PLAYERS], num;
		get_players(players, num, "ae", "TERRORIST");

		for (new i = 0; i < num; i++)
		{
			new tid = players[i];
			if (is_user_alive(tid))
				set_entvar(tid, var_health, 0.0);
		}
	}

	rg_round_end(0.0, WINSTATUS_CTS, ROUND_BOMB_DEFUSED);
}
