#!/usr/bin/env bash
# Source from repository helpers. Keep editor caches and preferences writable in cloud tasks.
SHADOWSTRIKE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHADOWSTRIKE_STATE_DIR="${SHADOWSTRIKE_STATE_DIR:-$(dirname -- "$SHADOWSTRIKE_ROOT")/.shadowstrike-runtime}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$SHADOWSTRIKE_STATE_DIR/data}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$SHADOWSTRIKE_STATE_DIR/config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$SHADOWSTRIKE_STATE_DIR/cache}"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
GODOT="${GODOT:-godot}"
export GODOT
