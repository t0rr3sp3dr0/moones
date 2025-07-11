# 🌙 MoonES
Lua-Scriptable Endpoint Security for macOS

## Pronunciation
[/mˈuːnz/](dat/pronunciation.mp3), like the plural of Moon.

## Getting Started
1. Download and install MoonES.
2. Write a Lua script for MoonES.
3. Give Full Disk Access to Terminal.
4. Run `sudo /Applications/MoonES.app/Contents/MacOS/MoonES ./script.lua` in Terminal.

## Scripting
The script provided to MoonES must implement two Lua functions, `moones.events` and `moones.handler`, as specified bellow. An example based on the [Monitoring System Events with Endpoint Security](https://developer.apple.com/documentation/endpointsecurity/monitoring-system-events-with-endpoint-security?language=objc) sample code from Apple is available at [dat/script.lua](dat/example.lua).

### `moones.events`
This function should return an array of events you want to subscribe to. The enumeration constants of [es_event_type_t](https://developer.apple.com/documentation/endpointsecurity/es_event_type_t?language=objc) can be referenced as defined in Objective-C.

```lua
function moones.events ()
    return {
        ES_EVENT_TYPE_NOTIFY_OPEN,
    }
end
```

### `moones.handler`
This function should handle the events you have subscribed to, allowing or denying auth events. The argument value received by the function is a [es_message_t](https://developer.apple.com/documentation/endpointsecurity/es_message_t?language=objc) and its members can be accessed as defined in Objective-C. The return value of the function must be an integer: between `0x00000000` and `0xFFFFFFFF` to be used as `authorized_flags` in [es_respond_flags_result](https://developer.apple.com/documentation/endpointsecurity/es_respond_flags_result(_:_:_:_:)?language=objc) for `ES_EVENT_TYPE_AUTH_OPEN` events, `ES_AUTH_RESULT_ALLOW` or `ES_AUTH_RESULT_DENY` to be used as `result` in [es_respond_auth_result](https://developer.apple.com/documentation/endpointsecurity/es_respond_auth_result(_:_:_:_:)?language=objc) for other auth events, and `0` for notify events.

```lua
function moones.handler (message)
    local path = tostring(message.event.open.file.path)
    print(path)

    return 0
end
```

## Common Errors

### `argc != 2: 1`
You haven't passed the script path as a command-line argument to MoonES.

### `ret[1] is not a number`
You haven't returned an integer in `moones.handler`.

### `ret[1] is not a table`
You haven't returned an array in `moones.events`.

### `ret[1][1] is not a number`
You haven't returned an array of integers in `moones.events`.

### `es_new_client(&client, ^(es_client_t *client, const es_message_t *message) { ... }) failed: 3`
You haven't entitled MoonES with [com.apple.developer.endpoint-security.client](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.endpoint-security.client?language=objc).

### `es_new_client(&client, ^(es_client_t *client, const es_message_t *message) { ... }) failed: 4`
You haven't given Full Disk Access to Terminal or the parent of MoonES.

### `es_new_client(&client, ^(es_client_t *client, const es_message_t *message) { ... }) failed: 5`
You haven't started MoonES as root.

## Developement

### Requirements
1. LuaJIT 2.1 or later.
2. Xcode 11 or later.

### Building
1. Replace [src/embedded.provisionprofile](src/embedded.provisionprofile) with your Provisioning Profile.
2. Optionally, create [.env](.env) and define `DISABLE_NOTARIZATION` to disable notarization or `SIGNING_IDENTITY` to override the signing identity.
3. Run `make`.
