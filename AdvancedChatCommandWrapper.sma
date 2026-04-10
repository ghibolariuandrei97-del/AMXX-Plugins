/* 
*   Advanced Chat Command Wrapper (DYNAMIC LISTS)
*   Developed for AMX Mod X 1.10+
*/

#include <amxmodx>
#include <amxmisc>

#pragma semicolon 1

// --- Configurații ---
#define PLUGIN_NAME    "Advanced Chat Command Wrapper"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR  "AI Studio"

#define LOG_FILE       "chat_wrapper.log"
#define HINT_FILE      "chat_wrapper_hints.ini"
#define CMD_HELP_FILE  "cmd_help.html"
#define EXEC_HELP_FILE "exec_help.html"
#define LIST_TEMP_FILE "wrapper_list.html"
#define COOLDOWN_TIME  0.5

enum { TYPE_CMD = 0, TYPE_EXEC };

// --- Variabile Globale ---
new Float:g_LastCommandTime[33];
new g_PendingCommand[33][256];

enum _:HintData {
    HintType,
    HintCmd[32],
    HintArgs[128]
};
new Array:g_HintsArray;

public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
    
    register_clcmd("say", "HandleSay");
    register_clcmd("say_team", "HandleSay");
    
    register_clcmd("say /cmd", "ShowCmdHelp");
    register_clcmd("say /exec", "ShowExecHelp");
    
    register_menu("ConfirmMenu", 1023, "HandleConfirmMenu");
    
    g_HintsArray = ArrayCreate(HintData);
    
    LoadHints();
    CreateHelpFiles();
}

public plugin_end() {
    ArrayDestroy(g_HintsArray);
}

// --- Logică Parsare Chat ---
public HandleSay(id) {
    if(!is_user_connected(id)) return PLUGIN_CONTINUE;

    static message[192];
    read_args(message, charsmax(message));
    remove_quotes(message);
    trim(message);

    if(!message[0]) return PLUGIN_CONTINUE;

    new Float:currentTime = get_gametime();
    if(currentTime - g_LastCommandTime[id] < COOLDOWN_TIME) {
        client_print_color(id, print_team_default, "^4[SISTEM]^1 Te rugam sa nu faci ^3spam^1!");
        return PLUGIN_HANDLED;
    }

    static prefix[16], rest[176];
    argbreak(message, prefix, charsmax(prefix), rest, charsmax(rest));

    new bool:isCmd = !!(equali(prefix, "cmd") || equali(prefix, "!cmd"));
    new bool:isExec = !!(equali(prefix, "exec") || equali(prefix, "!exec"));

    if(!isCmd && !isExec) return PLUGIN_CONTINUE;

    if(contain(rest, ";") != -1 || contain(rest, "&") != -1) {
        client_print_color(id, print_team_default, "^4[SECURITATE]^1 Caractere interzise detectate (^3;^1 sau ^3&^1)!");
        return PLUGIN_HANDLED;
    }

    if(!(get_user_flags(id) & ADMIN_MENU)) {
        client_print_color(id, print_team_default, "^4[SISTEM]^1 Nu ai ^3acces^1 la aceasta functie.");
        return PLUGIN_HANDLED;
    }

    g_LastCommandTime[id] = currentTime;
    
    if(isExec) ProcessExec(id, rest);
    else if(isCmd) ProcessCmd(id, rest);

    return PLUGIN_HANDLED;
}

// --- Procesare EXEC ---
ProcessExec(id, const args[]) {
    if(!(get_user_flags(id) & ADMIN_RCON)) {
        client_print_color(id, print_team_default, "^4[EXEC]^1 Ai nevoie de flag-ul ^3L (RCON)^1 pentru exec!");
        return;
    }

    static cmdName[32], cmdArgs[144];
    argbreak(args, cmdName, charsmax(cmdName), cmdArgs, charsmax(cmdArgs));

    if(!cmdName[0]) {
        client_print_color(id, print_team_default, "^4[SISTEM]^1 Sintaxa: ^3exec <comanda> [argumente]");
        return;
    }

    if(equali(cmdName, "list")) {
        ShowDynamicList(id, TYPE_EXEC);
        return;
    }

    if(!IsValidCommand(cmdName, TYPE_EXEC)) {
        client_print_color(id, print_team_default, "^4[SISTEM]^1 Comanda ^3%s^1 nu este in lista EXEC! Scrie ^3exec list^1.", cmdName);
        return;
    }

    if(IsDangerous(cmdName)) {
        copy(g_PendingCommand[id], charsmax(g_PendingCommand[]), args);
        ShowConfirmationMenu(id, cmdName);
        return;
    }

    ExecuteServerCommand(id, cmdName, cmdArgs);
}

// --- Procesare CMD ---
ProcessCmd(id, const args[]) {
    static cmdName[32], targetRaw[176];
    argbreak(args, cmdName, charsmax(cmdName), targetRaw, charsmax(targetRaw));

    if(!cmdName[0]) {
        client_print_color(id, print_team_default, "^4[SISTEM]^1 Sintaxa: ^3cmd <comanda> <target> [argumente]");
        return;
    }

    if(equali(cmdName, "list")) {
        ShowDynamicList(id, TYPE_CMD);
        return;
    }

    if(!IsValidCommand(cmdName, TYPE_CMD)) {
        client_print_color(id, print_team_default, "^4[SISTEM]^1 Comanda ^3%s^1 nu este in lista CMD! Scrie ^3cmd list^1.", cmdName);
        return;
    }

    if(!HasPermission(id, cmdName)) {
        client_print_color(id, print_team_default, "^4[SISTEM]^1 Nu ai flag-ul necesar pentru comanda ^3%s^1!", cmdName);
        return;
    }

    static target[32], extraArgs[128];
    ParseTargetAndArgs(targetRaw, target, charsmax(target), extraArgs, charsmax(extraArgs));

    if(!target[0]) {
        static attemptedTarget[32];
        argbreak(targetRaw, attemptedTarget, charsmax(attemptedTarget), "", 0);
        client_print_color(id, print_team_default, "^4[CMD]^1 Jucatorul ^3%s^1 nu a fost gasit!", attemptedTarget[0] ? attemptedTarget : "specificat");
        ShowHint(id, cmdName);
        return;
    }

    if(!extraArgs[0] && RequiresArgs(cmdName)) {
        ShowHint(id, cmdName);
        return;
    }

    if(target[0] == '@') {
        ExecuteGroupCommand(id, cmdName, target, extraArgs);
    } else {
        static finalCmd[256];
        if(extraArgs[0]) {
            formatex(finalCmd, charsmax(finalCmd), "amx_%s ^"%s^" %s", cmdName, target, extraArgs);
        } else {
            formatex(finalCmd, charsmax(finalCmd), "amx_%s ^"%s^"", cmdName, target);
        }
        
        server_cmd("%s", finalCmd);
        server_exec();
        
        LogAction(id, "CMD", finalCmd);
        client_print_color(id, print_team_default, "^4[CMD]^1 Executat pe ^3%s^1: ^3amx_%s", target, cmdName);
    }
}

// --- Generare Listă Dinamică (MOTD) ---
ShowDynamicList(id, type) {
    new configsDir[128], path[128];
    get_configsdir(configsDir, charsmax(configsDir));
    formatex(path, charsmax(path), "%s/%s", configsDir, LIST_TEMP_FILE);

    new f = fopen(path, "wt");
    if(!f) return;

    fprintf(f, "<html><head><style>");
    fprintf(f, "body { background:#111; color:#eee; font-family:monospace; padding:20px; }");
    fprintf(f, "h2 { color:#4CAF50; border-bottom:1px solid #333; padding-bottom:10px; }");
    fprintf(f, ".row { display:block; padding:8px; border-bottom:1px solid #222; }");
    fprintf(f, ".cmd { color:#FF9800; font-weight:bold; width:120px; display:inline-block; }");
    fprintf(f, ".args { color:#888; font-style:italic; }");
    fprintf(f, "</style></head><body>");
    
    fprintf(f, "<h2>Lista Comenzi: %s</h2>", (type == TYPE_CMD) ? "CMD (Jucatori)" : "EXEC (Server)");

    static data[HintData];
    new count = 0;
    for(new i = 0; i < ArraySize(g_HintsArray); i++) {
        ArrayGetArray(g_HintsArray, i, data);
        if(data[HintType] == type) {
            fprintf(f, "<div class='row'><span class='cmd'>%s</span> <span class='args'>%s</span></div>", data[HintCmd], data[HintArgs]);
            count++;
        }
    }

    if(count == 0) fprintf(f, "<p>Nicio comanda inregistrata pentru acest tip.</p>");

    fprintf(f, "</body></html>");
    fclose(f);

    show_motd(id, path, (type == TYPE_CMD) ? "Lista CMD" : "Lista EXEC");
}

bool:RequiresArgs(const cmd[]) {
    static data[HintData];
    for(new i = 0; i < ArraySize(g_HintsArray); i++) {
        ArrayGetArray(g_HintsArray, i, data);
        if(equali(cmd, data[HintCmd])) {
            new firstBracket = contain(data[HintArgs], "<");
            if(firstBracket != -1) {
                new secondBracket = contain(data[HintArgs][firstBracket + 1], "<");
                return (secondBracket != -1);
            }
            break;
        }
    }
    return false;
}

ExecuteGroupCommand(id, const cmd[], const target[], const args[]) {
    new players[32], pCount, name[32], team[32];
    get_players(players, pCount);

    new bool:isAll = !!equali(target, "@all");
    new bool:isCT = !!equali(target, "@ct");
    new bool:isT = !!equali(target, "@t");
    new bool:isMe = !!equali(target, "@me");

    new count = 0;
    for(new i = 0; i < pCount; i++) {
        new player = players[i];
        get_user_name(player, name, charsmax(name));
        get_user_team(player, team, charsmax(team));

        new bool:match = false;
        if(isAll) match = true;
        else if(isCT && equali(team, "CT")) match = true;
        else if(isT && equali(team, "TERRORIST")) match = true;
        else if(isMe && player == id) match = true;

        if(match) {
            static final[256];
            if(args[0]) formatex(final, charsmax(final), "amx_%s ^"%s^" %s", cmd, name, args);
            else formatex(final, charsmax(final), "amx_%s ^"%s^"", cmd, name);
            
            server_cmd("%s", final);
            count++;
        }
    }

    server_exec();
    client_print_color(id, print_team_default, "^4[CMD]^1 Comanda ^3amx_%s^1 aplicata pe ^3%d^1 jucatori (%s).", cmd, count, target);
}

bool:IsValidCommand(const cmd[], type) {
    static data[HintData];
    for(new i = 0; i < ArraySize(g_HintsArray); i++) {
        ArrayGetArray(g_HintsArray, i, data);
        if(data[HintType] == type && equali(cmd, data[HintCmd])) return true;
    }
    return false;
}

ParseTargetAndArgs(const input[], target[], tLen, args[], aLen) {
    if(input[0] == '@') {
        argbreak(input, target, tLen, args, aLen);
        return;
    }

    new players[32], pCount, name[32];
    get_players(players, pCount);

    new bestMatchLen = 0;
    static tempTarget[32], tempArgs[128];

    for(new i = 0; i < pCount; i++) {
        get_user_name(players[i], name, charsmax(name));
        new len = strlen(name);

        if(containi(input, name) == 0) {
            if(len > bestMatchLen) {
                bestMatchLen = len;
                copy(tempTarget, charsmax(tempTarget), name);
                copy(tempArgs, charsmax(tempArgs), input[len]);
                trim(tempArgs);
            }
        }
    }

    if(bestMatchLen > 0) {
        copy(target, tLen, tempTarget);
        copy(args, aLen, tempArgs);
    } else {
        target[0] = 0;
    }
}

ShowConfirmationMenu(id, const cmd[]) {
    static menuBody[512];
    formatex(menuBody, charsmax(menuBody), "\y[CONFIRMARE]\w Esti sigur?^n\rComanda: \w%s^n^n1. Da, executa^n2. Nu, anuleaza", cmd);
    show_menu(id, 1023, menuBody, -1, "ConfirmMenu");
}

public HandleConfirmMenu(id, key) {
    if(key == 0) {
        static cmdName[32], cmdArgs[144];
        argbreak(g_PendingCommand[id], cmdName, charsmax(cmdName), cmdArgs, charsmax(cmdArgs));
        ExecuteServerCommand(id, cmdName, cmdArgs);
    } else {
        client_print_color(id, print_team_default, "^4[SISTEM]^1 Comanda a fost ^3anulata^1.");
    }
    g_PendingCommand[id][0] = 0;
    return PLUGIN_HANDLED;
}

ExecuteServerCommand(id, const cmd[], const args[]) {
    static final[256];
    formatex(final, charsmax(final), "amx_%s %s", cmd, args);
    server_cmd("%s", final);
    server_exec();
    LogAction(id, "EXEC", final);
    client_print_color(id, print_team_default, "^4[EXEC]^1 Serverul a rulat: ^3%s", final);
}

bool:IsDangerous(const cmd[]) {
    static const dangerous[][] = { "map", "restart", "quit", "ban", "unban", "rcon", "cfg" };
    for(new i = 0; i < sizeof(dangerous); i++) {
        if(equali(cmd, dangerous[i])) return true;
    }
    return false;
}

bool:HasPermission(id, const cmd[]) {
    new flags = get_user_flags(id);
    if(equali(cmd, "slap") || equali(cmd, "slay")) return !!(flags & ADMIN_SLAY);
    if(equali(cmd, "ban") || equali(cmd, "kick")) return !!(flags & ADMIN_BAN);
    if(equali(cmd, "map")) return !!(flags & ADMIN_MAP);
    if(equali(cmd, "cvar")) return !!(flags & ADMIN_CVAR);
    return !!(flags & ADMIN_CHAT);
}

LogAction(id, const type[], const cmd[]) {
    static name[32], authid[32], logData[512];
    get_user_name(id, name, charsmax(name));
    get_user_authid(id, authid, charsmax(authid));
    formatex(logData, charsmax(logData), "Admin: %s (%s) | Tip: %s | Comanda: %s", name, authid, type, cmd);
    log_to_file(LOG_FILE, logData);
}

CreateHelpFiles() {
    new configsDir[128], path[128];
    get_configsdir(configsDir, charsmax(configsDir));

    formatex(path, charsmax(path), "%s/%s", configsDir, CMD_HELP_FILE);
    if(!file_exists(path)) {
        new f = fopen(path, "wt");
        if(f) {
            fprintf(f, "<html><body bgcolor='#121212' style='color:#e0e0e0; font-family:Verdana; padding:20px;'>");
            fprintf(f, "<h2 style='color:#4CAF50;'>Ajutor: Comanda CMD</h2>");
            fprintf(f, "<p>Foloseste <b>cmd</b> sau <b>!cmd</b> pentru actiuni rapide pe jucatori.</p>");
            fprintf(f, "<p style='color:#FF9800;'><b>Sintaxa:</b> cmd &lt;comanda&gt; &lt;target&gt; [argumente]</p>");
            fprintf(f, "<hr color='#333'><b>Target-uri Speciale:</b><ul>");
            fprintf(f, "<li><b>@all</b> - Toata lumea</li><li><b>@ct</b> - Doar Counter-Terrorists</li>");
            fprintf(f, "<li><b>@t</b> - Doar Terrorists</li><li><b>@me</b> - Tu insuti</li></ul>");
            fprintf(f, "<b>Exemple:</b><br><i>cmd slap David 10</i><br><i>cmd list</i>");
            fprintf(f, "</body></html>");
            fclose(f);
        }
    }

    formatex(path, charsmax(path), "%s/%s", configsDir, EXEC_HELP_FILE);
    if(!file_exists(path)) {
        new f = fopen(path, "wt");
        if(f) {
            fprintf(f, "<html><body bgcolor='#121212' style='color:#e0e0e0; font-family:Verdana; padding:20px;'>");
            fprintf(f, "<h2 style='color:#2196F3;'>Ajutor: Comanda EXEC</h2>");
            fprintf(f, "<p>Foloseste <b>exec</b> sau <b>!exec</b> pentru comenzi de sistem.</p>");
            fprintf(f, "<p style='color:#FF9800;'><b>Sintaxa:</b> exec &lt;comanda&gt; [argumente]</p>");
            fprintf(f, "<hr color='#333'><b>Note:</b><ul>");
            fprintf(f, "<li>Comenzile periculoase cer confirmare.</li>");
            fprintf(f, "<li>Necesita flag-ul <b>L (RCON)</b>.</li></ul>");
            fprintf(f, "<b>Exemple:</b><br><i>exec map de_dust2</i><br><i>exec list</i>");
            fprintf(f, "</body></html>");
            fclose(f);
        }
    }
}

LoadHints() {
    new filePath[128];
    get_configsdir(filePath, charsmax(filePath));
    format(filePath, charsmax(filePath), "%s/%s", filePath, HINT_FILE);

    if(!file_exists(filePath)) {
        new f = fopen(filePath, "wt");
        if(f) {
            fprintf(f, "; ==========================================^n");
            fprintf(f, "; Advanced Chat Command Wrapper - Hint Config^n");
            fprintf(f, "; Format: [type] [command] = [arguments]^n");
            fprintf(f, "; Available tags: @t, @ct, @me, @all^n");
            fprintf(f, "; ==========================================^n^n");
            fprintf(f, "cmd slap = <target> [damage]^ncmd kick = <target> [motiv]^n");
            fprintf(f, "cmd ban = <target> <timp> [motiv]^nexec map = <nume_mapa>^n");
            fprintf(f, "cmd say = <mesaj>^ncmd tsay = <culoare> <mesaj>^n");
            fclose(f);
        }
    }

    new f = fopen(filePath, "rt");
    if(!f) return;

    static line[160], typeStr[16], c[32], a[128], rest[144];
    while(!feof(f)) {
        fgets(f, line, charsmax(line));
        trim(line);
        if(!line[0] || line[0] == ';') continue;
        
        // Parsăm formatul: type command = args
        argbreak(line, typeStr, charsmax(typeStr), rest, charsmax(rest));
        strtok(rest, c, charsmax(c), a, charsmax(a), '=');
        trim(c); trim(a);
        
        static data[HintData];
        data[HintType] = equali(typeStr, "exec") ? TYPE_EXEC : TYPE_CMD;
        copy(data[HintCmd], 31, c);
        copy(data[HintArgs], 127, a);
        ArrayPushArray(g_HintsArray, data);
    }
    fclose(f);
}

ShowHint(id, const cmd[]) {
    static data[HintData];
    for(new i = 0; i < ArraySize(g_HintsArray); i++) {
        ArrayGetArray(g_HintsArray, i, data);
        if(equali(cmd, data[HintCmd])) {
            client_print_color(id, print_team_default, "^4[INFO]^1 Sintaxa corecta: ^3%s %s %s", (data[HintType] == TYPE_CMD) ? "cmd" : "exec", data[HintCmd], data[HintArgs]);
            return;
        }
    }
}

public ShowCmdHelp(id) {
    static path[128];
    get_configsdir(path, charsmax(path));
    format(path, charsmax(path), "%s/%s", path, CMD_HELP_FILE);
    show_motd(id, path, "Ajutor CMD");
    return PLUGIN_HANDLED;
}

public ShowExecHelp(id) {
    static path[128];
    get_configsdir(path, charsmax(path));
    format(path, charsmax(path), "%s/%s", path, EXEC_HELP_FILE);
    show_motd(id, path, "Ajutor EXEC");
    return PLUGIN_HANDLED;
}
