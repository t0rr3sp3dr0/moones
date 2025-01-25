//
// Created by Pedro Tôrres on 2024-11-17.
//

#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/fcntl.h>

#include <EndpointSecurity/EndpointSecurity.h>

#include "lua.h"

int main(int argc, const char *argv[]) {
    if (argc != 2) {
        (void) fprintf(stderr, "argc != 2: %d\n", argc);
        return EXIT_FAILURE;
    }
    const char *filename = argv[1];

    struct me_lua *lua = me_lua_new(filename);
    if (!lua) {
        (void) fprintf(stderr, "me_lua_new(filename) failed\n");
        return EXIT_FAILURE;
    }

    es_client_t *client = NULL;
    es_new_client_result_t new_client_result = es_new_client(&client, ^(es_client_t *client, const es_message_t *message) {
        bool is_action_type_auth = message->action_type == ES_ACTION_TYPE_AUTH;
        bool is_result_type_flags = message->event_type == ES_EVENT_TYPE_AUTH_OPEN;

        uint32_t result = !is_action_type_auth ? ES_AUTH_RESULT_DENY : 0;
        bool ok = me_lua_handler(lua, message, &result);
        if (!ok) {
            (void) fprintf(stderr, "me_lua_handler(lua, message, &flags) failed\n");
        }

        if (is_action_type_auth) {
            es_respond_result_t respond_result = ES_RESPOND_RESULT_SUCCESS;

            if (!is_result_type_flags) {
                es_auth_result_t auth_result = (es_auth_result_t) result;
                respond_result = es_respond_auth_result(client, message, auth_result, false);
            } else {
                uint32_t auth_flags = (uint32_t) result;
                respond_result = es_respond_flags_result(client, message, auth_flags, false);
            }

            if (respond_result != ES_RESPOND_RESULT_SUCCESS) {
                (void) fprintf(stderr, "es_respond_*_result(client, message, *, false) failed: %d\n", respond_result);
            }
        }
    });
    if (new_client_result != ES_NEW_CLIENT_RESULT_SUCCESS) {
        (void) fprintf(stderr, "es_new_client(&client, ^(es_client_t *client, const es_message_t *message) { ... }) failed: %d\n", new_client_result);
        return EXIT_FAILURE;
    }

    es_event_type_t *events = NULL;
    uint32_t event_count = 0;
    bool ok = me_lua_events(lua, &events, &event_count);
    if (!ok) {
        (void) fprintf(stderr, "me_lua_events(lua, &events, &event_count) failed\n");
        return EXIT_FAILURE;
    }

    es_return_t return_ = es_subscribe(client, events, event_count);
    if (return_ != ES_RETURN_SUCCESS) {
        (void) fprintf(stderr, "es_subscribe(client, events, event_count) failed: %d\n", return_);
        return EXIT_FAILURE;
    }

    (void) pause();

    (void) es_delete_client(client);
    me_lua_delete(lua);
    return EXIT_SUCCESS;
}
