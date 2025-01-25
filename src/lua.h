//
// Created by Pedro Tôrres on 2024-11-23.
//

#ifndef _MOONES_LUA_H
#define _MOONES_LUA_H

#include <stdbool.h>
#include <stddef.h>

#include <EndpointSecurity/EndpointSecurity.h>

struct me_lua;

struct me_lua *me_lua_new(const char *filename);

void me_lua_delete(struct me_lua *lua);

bool me_lua_events(struct me_lua *lua, es_event_type_t **events, uint32_t *event_count);

bool me_lua_handler(struct me_lua *lua, const es_message_t *message, uint32_t *result);

#endif	// _MOONES_LUA_H
