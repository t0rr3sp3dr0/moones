local function onauthexec (message)
    local esid = tostring(message.event.exec.target.signing_id)

    if esid == "com.apple.TextEdit" then
        return ES_AUTH_RESULT_DENY
    end

    return ES_AUTH_RESULT_ALLOW
end

local function onauthopen (message)
    local epath = tostring(message.event.open.file.path)

    if string.sub(epath, 1, 15) == "/usr/local/bin/" then
        return 0xFFFFFFFD -- deny FWRITE
    end

    return 0xFFFFFFFF -- allow *
end

local function onnotifyexec (message)
    local ppath = tostring(message.process.executable.path)
    local ppid = 0 / 0 -- TODO(t0rr3sp3dr0): audit_token_to_pid(message.process.audit_token)
    local epath = tostring(message.event.exec.target.executable.path)

    local s = string.format("%s (pid: %s) | EXEC: New image: %s", ppath, ppid, epath)
    print(s)
end

local function onnotifyexit (message)
    local ppath = tostring(message.process.executable.path)
    local ppid = 0 / 0 -- TODO(t0rr3sp3dr0): audit_token_to_pid(message.process.audit_token)
    local estat = message.event.exit.stat

    local s = string.format("%s (pid: %s) | EXIT: status: %s", ppath, ppid, estat)
    print(s)
end

local function onnotifyfork (message)
    local ppath = tostring(message.process.executable.path)
    local ppid = 0 / 0 -- TODO(t0rr3sp3dr0): audit_token_to_pid(message.process.audit_token)
    local epid = 0 / 0 -- TODO(t0rr3sp3dr0): audit_token_to_pid(message.event.fork.child.audit_token)

    local s = string.format("%s (pid: %s) | FORK: Child pid: %s", ppath, ppid, epid)
    print(s)
end

function moones.handler (message)
    local et = message.event_type

    if et == ES_EVENT_TYPE_AUTH_EXEC then
        return onauthexec(message)
    end

    if et == ES_EVENT_TYPE_AUTH_OPEN then
        return onauthopen(message)
    end

    if et == ES_EVENT_TYPE_NOTIFY_EXEC then
        onnotifyexec(message)
        return 0 -- unused value
    end

    if et == ES_EVENT_TYPE_NOTIFY_EXIT then
        onnotifyexit(message)
        return 0 -- unused value
    end

    if et == ES_EVENT_TYPE_NOTIFY_FORK then
        onnotifyfork(message)
        return 0 -- unused value
    end

    error("unexpected event type " .. tostring(et), 2)
end

function moones.events ()
    return {
        ES_EVENT_TYPE_AUTH_EXEC,
        ES_EVENT_TYPE_AUTH_OPEN,
        ES_EVENT_TYPE_NOTIFY_EXEC,
        ES_EVENT_TYPE_NOTIFY_EXIT,
        ES_EVENT_TYPE_NOTIFY_FORK,
    }
end
