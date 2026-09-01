#!/bin/sh
# Starts Hyprland for the emptty session entry.
#
# This exists for one reason: AQ_LIBINPUT_NO_PLUGINS has to be in the
# environment BEFORE Hyprland starts, and a .desktop file cannot set a
# variable. Hyprland's own `env` directive is too late -- aquamarine has
# already brought up the session and libinput by the time the config's env
# lines are applied.
#
# Why it is needed: Hyprland 0.56 links liblua5.5 for its Lua config support,
# and Void's libinput links liblua5.4 for its own plugin system. Both export
# the same lua_* symbols into one process, so libinput's calls bind to 5.5's
# incompatible ABI and segfault while loading /usr/lib/libinput/plugins/*.lua.
# The crash lands in liblua5.5 under libinput_plugin_system_load_plugins, one
# frame below Aquamarine::CSession::attempt, which makes it look like a session
# or seat problem rather than a symbol clash.
#
# AQ_LIBINPUT_NO_PLUGINS is aquamarine's own escape hatch and skips the plugin
# system entirely. Nothing is lost: those plugins are libinput's shipped
# examples, and the sway session never loaded them either -- wlroots does not
# use the plugin system, which is why sway is unaffected and why this only
# started mattering with Hyprland.
export AQ_LIBINPUT_NO_PLUGINS=1

exec /usr/local/bin/Hyprland "$@"
