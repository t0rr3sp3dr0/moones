arg = {...}

ffi = require("ffi")
ffi.cdef(arg[1])

__messages = ffi.cast("const es_message_t **", arg[2])

__tostring = function (obj)
    if ffi.istype("es_string_token_t", obj) then
        return ffi.string(obj.data, obj.length)
    end

    if ffi.istype("char *", obj) then
        return ffi.string(obj)
    end

    return tostring(obj)
end

__bit = {}
setmetatable(__bit, {
    __index = function (_, key)
        return bit[key]
    end,

    __newindex = function (_, key, _)
        error("attempt to set key '" .. key .. "' (`_G.bit` is read-only)", 2)
    end,
})

__coroutine = {}
setmetatable(__coroutine, {
    __index = function (_, key)
        return coroutine[key]
    end,

    __newindex = function (_, key, _)
        error("attempt to set key '" .. key .. "' (`_G.coroutine` is read-only)", 2)
    end,
})

__math = {}
setmetatable(__math, {
    __index = function (_, key)
        return math[key]
    end,

    __newindex = function (_, key, _)
        error("attempt to set key '" .. key .. "' (`_G.math` is read-only)", 2)
    end,
})

__moones = {
    events = -1,
    handler = -1,
}
setmetatable(__moones, {
    __index = function (_, key)
        if key == "__message" then
            return __messages[0]
        end

        return nil
    end,

    __newindex = function (table, key, value)
        if rawget(table, key) ~= -1 then
            error("attempt to set key '" .. key .. "' (`_G.moones` is read-only)", 2)
        end

        rawset(table, key, value)
    end,
})

__os = {
    clock = os.clock,
    date = os.date,
    difftime = os.difftime,
    getenv = os.getenv,
    time = os.time,
}
setmetatable(__os, {
    __newindex = function (_, key, _)
        error("attempt to set key '" .. key .. "' (`_G.os` is read-only)", 2)
    end,
})

__string = {}
setmetatable(__string, {
    __index = function (_, key)
        return string[key]
    end,

    __newindex = function (_, key, _)
        error("attempt to set key '" .. key .. "' (`_G.string` is read-only)", 2)
    end,
})

__table = {}
setmetatable(__table, {
    __index = function (_, key)
        return table[key]
    end,

    __newindex = function (_, key, _)
        error("attempt to set key '" .. key .. "' (`_G.table` is read-only)", 2)
    end,
})

sandbox = {
    bit = __bit,
    coroutine = __coroutine,
    math = __math,
    moones = __moones,
    os = __os,
    table = __table,
    string = __string,

    assert = assert,
    error = error,
    ipairs = ipairs,
    next = next,
    pairs = pairs,
    pcall = pcall,
    print = print,
    select = select,
    tonumber = tonumber,
    tostring = __tostring,
    type = type,
    unpack = unpack,
    xpcall = xpcall,
}
setmetatable(sandbox, {
    __index = function (_, key)
        local c = nil
        if pcall(function () c = ffi.C[key] end) and type(c) == "number" then
            return c
        end

        return nil
    end,

    __newindex = function (table, key, value)
        if key == "_" then
            return
        end

        error("attempt to set global '" .. key .. "' (`_G` is read-only)", 2)
    end,
})

setfenv(0, sandbox)
