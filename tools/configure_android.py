#!/usr/bin/env python3
"""Set only the two documented Godot Android editor paths; preserve other settings."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sdk', type=Path)
parser.add_argument('--java', type=Path)
args = parser.parse_args()
if not args.sdk and not args.java:
    parser.error('Supply --sdk, --java, or both.')
paths, required_files = [], []
if args.sdk:
    sdk = args.sdk.expanduser().resolve()
    paths.append(('export/android/android_sdk_path', sdk))
    required_files += [sdk / 'platform-tools/adb', sdk / 'build-tools/36.0.0/apksigner', sdk / 'platforms/android-36/android.jar']
if args.java:
    java = args.java.expanduser().resolve()
    paths.append(('export/android/java_sdk_path', java))
    required_files += [java / 'bin/java', java / 'bin/keytool', java / 'bin/javac']
for required in required_files:
    if not required.is_file():
        parser.error(f'Missing required tool: {required}')
version = subprocess.check_output([os.environ.get('GODOT', 'godot'), '--version'], text=True).strip()
minor = '.'.join(version.split('.')[:2])
repo = Path(__file__).resolve().parents[1]
state = Path(os.environ.get('SHADOWSTRIKE_STATE_DIR', str(repo.parent / '.shadowstrike-runtime')))
config = Path(os.environ.get('XDG_CONFIG_HOME', str(state / 'config'))) / 'godot' / f'editor_settings-{minor}.tres'
config.parent.mkdir(parents=True, exist_ok=True)
text = config.read_text() if config.exists() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
if '[resource]' not in text:
    parser.error('Unrecognized editor settings format; configure paths in the Godot editor instead.')
for key, path in paths:
    line = f'{key} = {json.dumps(str(path))}'
    pattern = rf'^{re.escape(key)}\s*=.*$'
    if re.search(pattern, text, flags=re.M):
        text = re.sub(pattern, lambda _: line, text, flags=re.M)
    else:
        text = text.replace('[resource]', '[resource]\n' + line, 1)
config.write_text(text)
print('Configured Godot Android editor paths. No credentials or signing keys stored in the repository.')
