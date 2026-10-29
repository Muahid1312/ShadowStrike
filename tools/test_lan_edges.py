#!/usr/bin/env python3
"""Exercise real capacity refusal, late-join refusal, and abrupt listen-server failure."""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
base = Path(tempfile.mkdtemp(prefix='shadowstrike-edges-'))
all_processes, streams = [], []

def launch(folder, role, case, port):
    location = folder / role
    location.mkdir()
    env = os.environ.copy()
    for name, leaf in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
        target = location / leaf
        target.mkdir()
        env[name] = str(target)
    stream = (location / 'run.log').open('w')
    streams.append(stream)
    process = subprocess.Popen([os.environ.get('GODOT', 'godot'), '--headless', '--max-fps', '60',
        '--path', str(ROOT), 'res://tests/lan_edge.tscn', '--', f'--role={role}', f'--case={case}',
        f'--port={port}', f'--directory={folder}'], env=env, stdout=stream, stderr=subprocess.STDOUT)
    all_processes.append(process)
    return process

def wait_file(path, processes, seconds=14):
    end = time.monotonic() + seconds
    while not path.exists():
        if time.monotonic() > end or any(p.poll() is not None for p in processes):
            raise RuntimeError(f'Missing expected event {path}')
        time.sleep(.05)

try:
    for case in ['capacity', 'late_join']:
        folder = base / case
        folder.mkdir()
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as candidate:
            candidate.bind(('127.0.0.1', 0))
            port = candidate.getsockname()[1]
        host = launch(folder, 'host', case, port)
        wait_file(folder / 'host-hosting', [host])
        participant = launch(folder, 'participant', case, port)
        wait_file(folder / 'host-pair', [host, participant])
        if case == 'late_join':
            (folder / 'release').touch()
            wait_file(folder / 'host-live', [host, participant])
            wait_file(folder / 'participant-live', [host, participant])
        probe = launch(folder, 'probe', case, port)
        probe.wait(timeout=15)
        if probe.returncode:
            raise RuntimeError(f'{case} probe failed')
        if case == 'capacity':
            (folder / 'release').touch()
            wait_file(folder / 'host-live', [host, participant])
            wait_file(folder / 'participant-live', [host, participant])
            (folder / 'stop').touch()
            host.wait(timeout=5)
        else:
            # Intentionally kill a live host with free lobby slots. No shutdown RPC can run.
            host.kill()
            host.wait(timeout=3)
            print('PASS: live host forcibly killed without shutdown RPC')
        participant.wait(timeout=12)
        for role, process in [('host', host), ('participant', participant), ('probe', probe)]:
            log = (folder / role / 'run.log').read_text()
            print(f'--- {case}/{role} ---\n{log}')
            intentionally_killed = case == 'late_join' and role == 'host'
            if ('SCRIPT ERROR' in log or 'ERROR:' in log or 'FAIL:' in log or
                (not intentionally_killed and (process.returncode or 'EDGE RESULT:' not in log))):
                raise RuntimeError(f'{case}/{role} did not pass')
    print('LAN EDGE RESULT: capacity refusal, late-join refusal, graceful exit and abrupt host loss passed')
finally:
    for process in all_processes:
        if process.poll() is None:
            process.terminate()
    for process in all_processes:
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    for stream in streams:
        stream.close()
    print('Edge-case evidence:', base)
