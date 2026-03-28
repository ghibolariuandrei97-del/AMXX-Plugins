#include <amxmodx>
#include <amxmisc>

new const HINT_CMDS[][] = { "slap", "ban", "kick", "slay", "map", "vote", "votemap", "cvar", "chat", "psay" }
new const HINT_ARGS[][] = { "<target> [damage]", "<target> <timp> [motiv]", "<target> [motiv]", "<target>", "<mapa>", "<intrebare> <r1> <r2>", "<map1> [map2] [map3]", "<cvar> <valoare>", "<mesaj>", "<target> <mesaj>" }

public plugin_init() {
    register_plugin("Chat Command Wrapper", "5.0", "Gemini")
    
    register_clcmd("say", "handle_say")
    register_clcmd("say_team", "handle_say")
    register_clcmd("say /cmd", "show_cmd_motd")
    register_clcmd("say /exec", "show_exec_motd")
}

public show_cmd_motd(id) {
    new html[1024]
    formatex(html, charsmax(html), "<html><body bgcolor='#1a1a1a' text='#ffffff' style='font-family: Verdana, sans-serif; padding: 20px;'><h2 style='color: #4CAF50;'>Comanda CMD</h2><p>Foloseste <b>cmd</b> sau <b>!cmd</b> in chat pentru comenzi rapide asupra jucatorilor.</p><br><p><b style='color: #FF9800;'>Sintaxa:</b> cmd &lt;comanda&gt; &lt;target&gt; [argumente_extra]</p><br><p><b>Exemple:</b><br><ul><li>cmd slap David 10</li><li>cmd ban Jucator 0 Motiv</li><li>cmd kick Jucator</li></ul></p></body></html>")
    show_motd(id, html, "Ajutor: CMD")
    return PLUGIN_HANDLED
}

public show_exec_motd(id) {
    new html[1024]
    formatex(html, charsmax(html), "<html><body bgcolor='#1a1a1a' text='#ffffff' style='font-family: Verdana, sans-serif; padding: 20px;'><h2 style='color: #2196F3;'>Comanda EXEC</h2><p>Foloseste <b>exec</b> sau <b>!exec</b> in chat pentru a forta serverul sa ruleze comenzi de sistem sau texte lungi.</p><br><p><b style='color: #FF9800;'>Sintaxa:</b> exec &lt;comanda&gt; [text_sau_argumente]</p><br><p><b>Exemple:</b><br><ul><li>exec vote ^"Schimbam mapa?^" Da Nu</li><li>exec map de_dust2</li><li>exec chat Salutare tuturor</li></ul></p></body></html>")
    show_motd(id, html, "Ajutor: EXEC")
    return PLUGIN_HANDLED
}

public handle_say(id) {
    new message[192], prefix[16], rest_all[176]
    read_args(message, charsmax(message))
    remove_quotes(message)

    if (!message[0]) return PLUGIN_CONTINUE

    argbreak(message, prefix, charsmax(prefix), rest_all, charsmax(rest_all))

    new is_cmd = (equali(prefix, "cmd") || equali(prefix, "!cmd"))
    new is_exec = (equali(prefix, "exec") || equali(prefix, "!exec"))

    if (!is_cmd && !is_exec) return PLUGIN_CONTINUE

    if (!is_user_admin(id)) {
        client_print_color(id, print_team_default, "^4[SISTEM]^1 Eroare: Doar ^3adminii^1 pot folosi aceasta comanda!")
        return PLUGIN_HANDLED
    }

    new arg1_cmd[32], rest_args[144]
    argbreak(rest_all, arg1_cmd, charsmax(arg1_cmd), rest_args, charsmax(rest_args))

    if (!arg1_cmd[0]) {
        client_print_color(id, print_team_default, "^4[SISTEM]^1 Sintaxa: ^3%s <comanda> [argumente]", prefix)
        return PLUGIN_HANDLED
    }

    if (is_exec) {
        if (rest_args[0]) {
            server_cmd("amx_%s %s", arg1_cmd, rest_args)
            client_print_color(id, print_team_default, "^4[EXEC]^1 Serverul a executat: ^3amx_%s %s", arg1_cmd, rest_args)
        } else {
            server_cmd("amx_%s", arg1_cmd)
            client_print_color(id, print_team_default, "^4[EXEC]^1 Serverul a executat: ^3amx_%s", arg1_cmd)
        }
        server_exec()
        show_cmd_hint(id, arg1_cmd)
        return PLUGIN_HANDLED
    }

    if (is_cmd) {
        new amx_cmd[64], target[32], args_extra[112]
        formatex(amx_cmd, charsmax(amx_cmd), "amx_%s", arg1_cmd)
        
        argbreak(rest_args, target, charsmax(target), args_extra, charsmax(args_extra))

        if (args_extra[0]) {
            amxclient_cmd(id, amx_cmd, target, args_extra)
        } else if (target[0]) {
            amxclient_cmd(id, amx_cmd, target)
        } else {
            amxclient_cmd(id, amx_cmd)
        }

        client_print_color(id, print_team_default, "^4[CMD]^1 Executat: ^3%s %s %s", amx_cmd, target, args_extra)
        show_cmd_hint(id, arg1_cmd)
        return PLUGIN_HANDLED
    }

    return PLUGIN_CONTINUE
}

show_cmd_hint(id, const command[]) {
    for (new i = 0; i < sizeof(HINT_CMDS); i++) {
        if (equali(command, HINT_CMDS[i])) {
            client_print_color(id, print_team_default, "^4[INFO]^1 Tip argumente: ^3amx_%s %s", HINT_CMDS[i], HINT_ARGS[i])
            break
        }
    }
}
