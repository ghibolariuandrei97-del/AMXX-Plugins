#include <amxmodx>
#include <amxmisc>

new bool:g_bExecBan = false;  

public plugin_init()
{
	register_plugin("XBan", "1.0", "Daeva" );
	register_concmd("amx_xban", "cmd_xban", ADMIN_BAN, "<nume/#userid> <minute> [motiv]");
}

public cmd_xban(id, level, cid)
{
    if (!cmd_access(id, level, cid, 3))
        return PLUGIN_HANDLED;
    
    new arg[32], minutes[8], reason[64];
    
    read_argv(1, arg, charsmax(arg));
    read_argv(2, minutes, charsmax(minutes));
    read_argv(3, reason, charsmax(reason));
    
    if (!reason[0])
        copy(reason, charsmax(reason), "Nespecificat");
    
    new target = cmd_target(id, arg, CMDTARGET_OBEY_IMMUNITY | CMDTARGET_ALLOW_SELF | CMDTARGET_NO_BOTS);
    
    if (!target)
        return PLUGIN_HANDLED;
    
    new name[32];
    get_user_name(target, name, charsmax(name));
    
    if (!g_bExecBan)
    {
        new ban_cmd[128];
		formatex(ban_cmd, charsmax(ban_cmd), "amx_ban #%d %d %s", get_user_userid(target), str_to_num(minutes), reason);
	     
        
        server_cmd(ban_cmd);       // Trimiți comanda
        server_exec();             // Execuți imediat buffer-ul
        
        g_bExecBan = true;         // Setăm pe true ca să nu rămână în loop
        

        set_task(0.1, "ResetExecBan");
        
        client_print(id, print_console, "[XBan] Jucătorul %s a fost banat pentru %s minute. Motiv: %s", name, minutes, reason);
    }
    else
    {
        client_print(id, print_console, "[XBan] Server_exec este deja activ. Încearcă din nou peste o secundă.");
    }
    
    return PLUGIN_HANDLED;
}

public ResetExecBan()
{
    g_bExecBan = false;
}
