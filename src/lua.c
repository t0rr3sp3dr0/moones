//
// Created by Pedro Tôrres on 2024-11-23.
//

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

#include <lauxlib.h>
#include <luajit.h>
#include <lualib.h>

#include "cdef.h"
#include "defer.h"
#include "prelude.h"

#include "lua.h"

#define DO_AND_DEFER_POP(F, L, ...) \
    F((L) __VA_OPT__(,) __VA_ARGS__); DEFER ^{ lua_pop((L), 1); }

#define GET_VALUE_FROM_TABLE(L, I, K) \
    do {                              \
        lua_pushstring((L), (K));     \
        lua_gettable((L), (I) - 1);   \
    } while (false)

#define NONNULL_OR_GOTO_EXIT(E)                      \
    do {                                             \
        if ((E) == NULL) {                           \
            (void) fprintf(stderr, #E " is NULL\n"); \
            goto EXIT;                               \
        }                                            \
    } while (false)

#define OK_OR_GOTO_EXIT(F, L, ...)                                                                                   \
    do {                                                                                                             \
        if ((F)((L) __VA_OPT__(,) __VA_ARGS__) != LUA_OK) {                                                          \
            (void) fprintf(stderr, #F "(" #L __VA_OPT__(", ") #__VA_ARGS__ ") failed: %s\n", lua_tostring((L), -1)); \
            lua_pop((L), 1);                                                                                         \
            goto EXIT;                                                                                               \
        }                                                                                                            \
    } while (false)

#define ONE_OR_GOTO_EXIT(F, L, ...)                                                       \
    do {                                                                                  \
        if ((F)((L) __VA_OPT__(,) __VA_ARGS__) != 1) {                                    \
            (void) fprintf(stderr, #F "(" #L __VA_OPT__(", ") #__VA_ARGS__ ") failed\n"); \
            goto EXIT;                                                                    \
        }                                                                                 \
    } while (false)

#define PROTECTED_CALL_AND_DEFER_POP_OR_GOTO_EXIT(L, A, R, I) \
    OK_OR_GOTO_EXIT(lua_pcall, (L), (A), (R), (I)); DEFER ^{ lua_pop((L), (R)); }

struct me_lua {
    lua_State *state;
    const es_message_t *message;
};

struct me_lua *me_lua_new(const char *filename) {
    __block struct me_lua *ret = NULL;

    goto DO;

EXIT:
    return ret;

DO:
    NONNULL_OR_GOTO_EXIT(filename);

    struct me_lua *lua = malloc(sizeof(struct me_lua));
    if (!lua) {
        perror("malloc(sizeof(struct me_lua)) failed");
        goto EXIT;
    }
    DEFER ^{ if (!ret) me_lua_delete(lua); };

    lua->state = NULL;
    lua->message = NULL;

    lua_State *state = luaL_newstate();
    if (!state) {
        (void) fprintf(stderr, "luaL_newstate() failed\n");
        goto EXIT;
    }
    lua->state = state;

    luaL_openlibs(state);                                                                       // inits _ENV

    ONE_OR_GOTO_EXIT(luaJIT_setmode, state, 0, LUAJIT_MODE_ENGINE | LUAJIT_MODE_OFF);           // disables JIT

    OK_OR_GOTO_EXIT(luaL_loadbufferx, state, prelude_luac, sizeof prelude_luac, NULL, "b");     // loads F
    lua_pushstring(state, cdef_i);                                                              // pushes arg[1]
    lua_pushlightuserdata(state, &lua->message);                                                // pushes arg[2]
    PROTECTED_CALL_AND_DEFER_POP_OR_GOTO_EXIT(state, 2, 0, 0);                                  // calls F with 2 args and 0 rets deferring pop

    OK_OR_GOTO_EXIT(luaL_loadfilex, state, filename, "t");                                      // loads G
    PROTECTED_CALL_AND_DEFER_POP_OR_GOTO_EXIT(state, 0, 0, 0);                                  // calls G with 0 args and 0 rets deferring pop

    DO_AND_DEFER_POP(lua_getglobal, state, "moones");                                           // gets T deferring pop

    DO_AND_DEFER_POP(GET_VALUE_FROM_TABLE, state, -1, "events");                                // gets E deferring pop
    if (!lua_isfunction(state, -1)) {                                                           // checks E
        (void) fprintf(stderr, "moones.events is not a function\n");
        goto EXIT;
    }

    DO_AND_DEFER_POP(GET_VALUE_FROM_TABLE, state, -2, "handler");                               // gets H deferring pop
    if (!lua_isfunction(state, -1)) {                                                           // checks H
        (void) fprintf(stderr, "moones.handler is not a function\n");
        goto EXIT;
    }

    ret = lua;
    goto EXIT;
}

void me_lua_delete(struct me_lua *lua) {
    NONNULL_OR_GOTO_EXIT(lua);

    if (lua->state) {
        lua_close(lua->state);

        lua->state = NULL;
    }

    if (lua->message) {
        lua->message = NULL;
    }

    free(lua);

EXIT:
    (void) NULL;
}

bool me_lua_events(struct me_lua *lua, es_event_type_t **events, uint32_t *event_count) {
    __block bool ok = false;

    goto DO;

EXIT:
    return ok;

DO:
    NONNULL_OR_GOTO_EXIT(lua);
    NONNULL_OR_GOTO_EXIT(events);
    NONNULL_OR_GOTO_EXIT(event_count);

    lua->message = NULL;

    DO_AND_DEFER_POP(lua_getglobal, lua->state, "moones");                                      // gets T deferring pop
    GET_VALUE_FROM_TABLE(lua->state, -1, "events");                                             // gets E
    PROTECTED_CALL_AND_DEFER_POP_OR_GOTO_EXIT(lua->state, 0, 1, 0);                             // calls E with 0 args and 1 rets deferring pop
    if (!lua_istable(lua->state, -1)) {                                                         // checks ret[1]
        (void) fprintf(stderr, "ret[1] is not a table\n");
        goto EXIT;
    }

    size_t len = lua_objlen(lua->state, -1);                                                    // ret[1] length
    if (len > INT_MAX) {
        (void) fprintf(stderr, "length of ret[1] is greater than INT_MAX\n");
        goto EXIT;
    }

    es_event_type_t *buf = malloc(len * sizeof(es_event_type_t));
    if (!buf) {
        perror("malloc(len * sizeof(es_event_type_t)) failed");
        goto EXIT;
    }
    DEFER ^{ if (!ok) free(buf); };

    for (size_t i = 0; i < len; ++i) {
        int n = (int) i + 1;

        int is_n = 0;

        DO_AND_DEFER_POP(lua_rawgeti, lua->state, -1, n);                                       // gets ret[1][n] deferring pop
        lua_Integer ret1n = lua_tointegerx(lua->state, -1, &is_n);                              // reads ret[1][n]

        if (!is_n) {
            (void) fprintf(stderr, "ret[1][%d] is not a number\n", n);
            goto EXIT;
        }
        if (ret1n < INT_MIN) {
            (void) fprintf(stderr, "ret[1][%d] is less than INT_MIN\n", n);
            goto EXIT;
        }
        if (ret1n > INT_MAX) {
            (void) fprintf(stderr, "ret[1][%d] is greater than INT_MAX\n", n);
            goto EXIT;
        }

        buf[i] = (es_event_type_t) ret1n;
    }

    *events = buf;
    *event_count = (uint32_t) len;

    ok = true;
    goto EXIT;
}

bool me_lua_handler(struct me_lua *lua, const es_message_t *message, uint32_t *result) {
    __block bool ok = false;

    goto DO;

EXIT:
    return ok;

DO:
    NONNULL_OR_GOTO_EXIT(lua);
    NONNULL_OR_GOTO_EXIT(message);
    NONNULL_OR_GOTO_EXIT(result);

    lua->message = message;
    DEFER ^{ lua->message = NULL; };

    int is_n = 0;

    DO_AND_DEFER_POP(lua_getglobal, lua->state, "moones");                                      // gets T deferring pop
    GET_VALUE_FROM_TABLE(lua->state, -1, "handler");                                            // gets H
    GET_VALUE_FROM_TABLE(lua->state, -2, "__message");                                          // gets M
    PROTECTED_CALL_AND_DEFER_POP_OR_GOTO_EXIT(lua->state, 1, 1, 0);                             // calls H with 1 args and 1 rets deferring pop
    lua_Integer ret1 = lua_tointegerx(lua->state, -1, &is_n);                                   // reads ret[1]

    if (!is_n) {
        (void) fprintf(stderr, "ret[1] is not a number\n");
        goto EXIT;
    }
    if (ret1 < 0) {
        (void) fprintf(stderr, "ret[1] is less than UINT32_MIN\n");
        goto EXIT;
    }
    if (ret1 > UINT32_MAX) {
        (void) fprintf(stderr, "ret[1] is greater than UINT32_MAX\n");
        goto EXIT;
    }

    *result = (uint32_t) ret1;

    ok = true;
    goto EXIT;
}
