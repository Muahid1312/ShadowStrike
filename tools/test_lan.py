#!/usr/bin/env python3
"""Run real separate Godot host/client processes over loopback UDP. No Android claims."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--players', type=int, choices=[2, 4], default=2)
parser.add_argument('--keep-logs', type=Path)
args = parser.parse_args()
state = Path(tempfile.mkdtemp(prefix='shadowstrike-lan-'))
processes = []
streams = []

def start(label, role, port):
    folder = state / label
    folder.mkdir()
    env = os.environ.copy()
    for key, leaf in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
        path = folder / leaf
        path.mkdir()
        env[key] = str(path)
    log = (folder / 'run.log').open('w')
    streams.append(log)
    process = subprocess.Popen([os.environ.get('GODOT', 'godot'), '--headless', '--max-fps', '60',
        '--path', str(ROOT), 'res://tests/lan_peer.tscn', '--', f'--role={role}',
        f'--label={label}', f'--port={port}', f'--players={args.players}', f'--test-dir={state}'],
        env=env, stdout=log, stderr=subprocess.STDOUT)
    processes.append((label, process))
    return process

try:
    # Reserve then release a loopback UDP port for this test only.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as candidate:
        candidate.bind(('127.0.0.1', 0))
        port = candidate.getsockname()[1]
    host = start('Host', 'host', port)
    end = time.monotonic() + 12
    while not (state / 'Host-hosting.json').exists():
        if host.poll() is not None or time.monotonic() > end:
            raise RuntimeError('Host failed before reporting a real lobby')
        time.sleep(.05)
    for number in range(1, args.players):
        start(f'Client{number}', 'client', port)
    end = time.monotonic() + 45
    while any(p.poll() is None for _, p in processes):
        if time.monotonic() > end:
            raise RuntimeError('LAN test timed out')
        time.sleep(.1)
    count = 0
    for label, process in processes:
        log = (state / label / 'run.log').read_text()
        print(f'--- {label} ---\n{log}')
        result_file = state / f'{label}-done.json'
        if process.returncode or not result_file.exists():
            raise RuntimeError(f'{label} did not complete: exit {process.returncode}')
        result = json.loads(result_file.read_text())
        if result['failed'] or 'SCRIPT ERROR' in log or 'ERROR:' in log:
            raise RuntimeError(f'{label} reported errors')
        count += result['checks']
    print(f'LAN TEST RESULT: {args.players} real processes, {count} checks, 0 failures')
finally:
    for _, process in processes:
        if process.poll() is None:
            process.terminate()
    for _, process in processes:
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    for stream in streams:
        stream.close()
    if args.keep_logs:
        import shutil
        args.keep_logs.mkdir(parents=True, exist_ok=True)
        shutil.copytree(state, args.keep_logs / state.name)
    print('Per-process evidence:', state)
