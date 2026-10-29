#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$SHADOWSTRIKE_STATE_DIR/gradle}"
mkdir -p "$SHADOWSTRIKE_ROOT/builds"
SHADOWSTRIKE_EXPORT_TMP="$(mktemp -d "$SHADOWSTRIKE_ROOT/builds/.export.XXXXXX")"
trap 'rm -rf -- "$SHADOWSTRIKE_EXPORT_TMP"' EXIT
# Recreate the generated official template on a fresh source checkout.
SHADOWSTRIKE_TEMPLATE_ARGS=()
if [ ! -f "$SHADOWSTRIKE_ROOT/android/build/build.gradle" ]; then
    SHADOWSTRIKE_TEMPLATE_ARGS+=(--install-android-build-template)
fi
# Preserve the last successful APK if a later export fails.
"$GODOT" --headless --path "$SHADOWSTRIKE_ROOT" "${SHADOWSTRIKE_TEMPLATE_ARGS[@]}" --export-debug Android "$SHADOWSTRIKE_EXPORT_TMP/ShadowStrike-debug.apk"
python3 - "$SHADOWSTRIKE_EXPORT_TMP/ShadowStrike-debug.apk" <<'PY'
from pathlib import Path
from zipfile import ZipFile
import sys
apk = Path(sys.argv[1])
with ZipFile(apk) as archive:
    assert archive.testzip() is None, 'Corrupt APK ZIP'
    assert 'AndroidManifest.xml' in archive.namelist(), 'Missing Android manifest'
    assert any(n.startswith('lib/arm64-v8a/') and n.endswith('.so') for n in archive.namelist()), 'Missing ARM64 runtime'
    assert any(n.startswith('assets/') for n in archive.namelist()), 'Missing game assets'
PY
mv -f -- "$SHADOWSTRIKE_EXPORT_TMP/ShadowStrike-debug.apk" "$SHADOWSTRIKE_ROOT/builds/ShadowStrike-debug.apk"
# A previous stock export may have left a v4 sidecar for a different APK.
rm -f -- "$SHADOWSTRIKE_ROOT/builds/ShadowStrike-debug.apk.idsig"
echo "APK built: $SHADOWSTRIKE_ROOT/builds/ShadowStrike-debug.apk"
(cd "$SHADOWSTRIKE_ROOT/builds" && sha256sum ShadowStrike-debug.apk > ShadowStrike-debug.apk.sha256)
