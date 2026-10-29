#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
# No test writes to a developer's real saved preferences.
SHADOWSTRIKE_TEST_STATE="$(mktemp -d /tmp/shadowstrike-tests.XXXXXX)"
trap 'rm -rf -- "$SHADOWSTRIKE_TEST_STATE"' EXIT
export XDG_DATA_HOME="$SHADOWSTRIKE_TEST_STATE/data"
export XDG_CONFIG_HOME="$SHADOWSTRIKE_TEST_STATE/config"
export XDG_CACHE_HOME="$SHADOWSTRIKE_TEST_STATE/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
"$GODOT" --headless --path "$SHADOWSTRIKE_ROOT" --editor --import --quit > "$SHADOWSTRIKE_TEST_STATE/import.log" 2>&1
if grep -En 'SCRIPT ERROR|Parse Error|ERROR:' "$SHADOWSTRIKE_TEST_STATE/import.log"; then
    cat "$SHADOWSTRIKE_TEST_STATE/import.log"
    exit 1
fi
# Preserve the engine's exit status and also reject engine errors that can exit zero.
set +e
"$GODOT" --headless --path "$SHADOWSTRIKE_ROOT" res://tests/smoke.tscn > "$SHADOWSTRIKE_TEST_STATE/tests.log" 2>&1
SHADOWSTRIKE_TEST_EXIT=$?
set -e
cat "$SHADOWSTRIKE_TEST_STATE/tests.log"
if [ "$SHADOWSTRIKE_TEST_EXIT" -ne 0 ]; then exit "$SHADOWSTRIKE_TEST_EXIT"; fi
if grep -Eq 'SCRIPT ERROR|ERROR:|WARNING: ObjectDB' "$SHADOWSTRIKE_TEST_STATE/tests.log"; then exit 1; fi
grep -Eq 'SHADOWSTRIKE TEST RESULT: [0-9]+ checks, 0 failures' "$SHADOWSTRIKE_TEST_STATE/tests.log"

"$GODOT" --headless --path "$SHADOWSTRIKE_ROOT" res://tests/network_contract.tscn > "$SHADOWSTRIKE_TEST_STATE/contract.log" 2>&1
cat "$SHADOWSTRIKE_TEST_STATE/contract.log"
if grep -Eq 'SCRIPT ERROR|ERROR:' "$SHADOWSTRIKE_TEST_STATE/contract.log"; then exit 1; fi
grep -Eq 'NETWORK CONTRACT RESULT: [0-9]+ checks, 0 failures' "$SHADOWSTRIKE_TEST_STATE/contract.log"

"$GODOT" --headless --path "$SHADOWSTRIKE_ROOT" res://tests/rules_contract.tscn > "$SHADOWSTRIKE_TEST_STATE/rules.log" 2>&1
cat "$SHADOWSTRIKE_TEST_STATE/rules.log"
if grep -Eq 'SCRIPT ERROR|ERROR:' "$SHADOWSTRIKE_TEST_STATE/rules.log"; then exit 1; fi
grep -Eq 'RULES CONTRACT RESULT: [0-9]+ checks, 0 failures' "$SHADOWSTRIKE_TEST_STATE/rules.log"

"$GODOT" --headless --path "$SHADOWSTRIKE_ROOT" res://tests/release_audit.tscn > "$SHADOWSTRIKE_TEST_STATE/release.log" 2>&1
cat "$SHADOWSTRIKE_TEST_STATE/release.log"
if grep -Eq 'SCRIPT ERROR|ERROR:|FAIL:' "$SHADOWSTRIKE_TEST_STATE/release.log"; then exit 1; fi
grep -Eq 'RELEASE AUDIT RESULT: [0-9]+ checks, 0 failures' "$SHADOWSTRIKE_TEST_STATE/release.log"
