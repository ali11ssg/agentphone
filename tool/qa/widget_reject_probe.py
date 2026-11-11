#!/usr/bin/env python3
"""Probe a real scratch OC1/OC2 Reject against its authoritative status API.

Uses the public opencode/big-pickle model; does not read or copy provider auth.
Pass an existing standalone binary. Never installs packages or touches an app.
Only sanitized evidence is written to --output. Private logs stay in a mode-700
scratch directory outside the user's home; the server is stopped by exact PID.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import tempfile
import time
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--flavor', choices=['oc1', 'oc2'], required=True)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--model', default='big-pickle')
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    with socket.socket() as check:
        check.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        check.bind(('127.0.0.1', args.port))
    scratch = Path(tempfile.mkdtemp(prefix='widget-reject-probe-', dir='/tmp'))
    scratch.chmod(0o700)
    env = os.environ.copy()
    for key in list(env):
        if any(part in key for part in (
            'API_KEY', 'TOKEN', 'OPENCODE', 'ANTHROPIC', 'OPENAI',
        )):
            env.pop(key)
    for key, name in (
        ('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'),
        ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'state'),
    ):
        (scratch / name).mkdir()
        env[key] = str(scratch / name)
    project = scratch / 'project'
    project.mkdir()
    password = secrets.token_urlsafe(32) if args.flavor == 'oc1' else None
    if password:
        env['OPENCODE_SERVER_PASSWORD'] = password
    log_path = scratch / 'private-server.log'
    log = log_path.open('w')
    log_path.chmod(0o600)
    server = subprocess.Popen(
        [str(binary), 'serve', '--port', str(args.port), '--hostname', '127.0.0.1'],
        cwd=project, env=env, stdout=log, stderr=log, start_new_session=True,
    )

    def api(path, body=None, method=None):
        auth = base64.b64encode(('opencode:' + password).encode()).decode()
        request = urllib.request.Request(
            f'http://127.0.0.1:{args.port}{path}',
            data=None if body is None else json.dumps(body).encode(),
            headers={'Authorization': 'Basic ' + auth,
                     'Content-Type': 'application/json'}, method=method,
        )
        with urllib.request.urlopen(request, timeout=45) as response:
            raw = response.read()
            return json.loads(raw) if raw else None

    try:
        for _ in range(150):
            if server.poll() is not None:
                raise RuntimeError('Scratch server exited during startup')
            if args.flavor == 'oc2' and password is None:
                match = re.search(r'server password[: ]+([^\s]+)',
                                  log_path.read_text(), re.IGNORECASE)
                if match:
                    password = match.group(1)
            if password:
                try:
                    info = api('/api/info' if args.flavor == 'oc2' else '/global/health')
                    break
                except (OSError, ValueError):
                    pass
            time.sleep(.2)
        else:
            raise RuntimeError('Scratch server did not become ready')
        oc2 = args.flavor == 'oc2'
        model = {'providerID': 'opencode', 'id' if oc2 else 'modelID': args.model}
        if oc2:
            session = api('/api/session', {'title': 'Widget reject scratch', 'model': model})['data']['id']
            api('/api/session/' + session, {'permissions': [
                {'action': '*', 'resource': '*', 'effect': 'ask'},
            ]}, 'PATCH')
            api('/api/session/' + session + '/prompt', {'text':
                'Use the shell tool to run exactly: sleep 50.'})
        else:
            session = api('/session', {'title': 'Widget reject scratch', 'permission': [
                {'permission': '*', 'pattern': '*', 'action': 'ask'},
            ]})['id']
            api('/session/' + session + '/prompt_async', {'model': model, 'parts': [
                {'type': 'text', 'text': 'Use the bash tool to run exactly: sleep 50.'},
            ]})
        status_path = '/api/session/active' if oc2 else '/session/status'
        permission_path = '/api/permission/request' if oc2 else '/permission'
        start = time.monotonic()
        rejected = None
        seen_running = False
        rows = []
        for _ in range(400):
            active = api(status_path)
            if oc2:
                active = active['data']
            status = active.get(session, {'type': 'idle'})
            requests = api(permission_path)
            if oc2:
                requests = requests['data']
            pending = [request for request in requests if request.get('sessionID') == session]
            rows.append({'seconds': round(time.monotonic() - start, 3),
                         'status': status, 'pending_count': len(pending)})
            seen_running |= status['type'] in ('busy', 'running')
            if pending and rejected is None:
                request_id = pending[0]['id']
                if oc2:
                    api(f'/api/session/{session}/permission/{request_id}/reply', {'decision': 'reject'})
                else:
                    api(f'/permission/{request_id}/reply', {'reply': 'reject'})
                rejected = time.monotonic() - start
            if status['type'] == 'idle' and seen_running:
                break
            time.sleep(.25)
        result = {'server_version': info.get('version'), 'flavor': args.flavor,
                  'server_status_endpoint': 'GET ' + status_path,
                  'model': 'opencode/' + args.model, 'rows': rows,
                  'rejected_seconds': rejected,
                  'idle_semantics': 'Idle status or absent from the complete status map',
                  'probe_completed': rejected is not None and rows[-1]['status']['type'] == 'idle'}
        if result['probe_completed']:
            result['post_reject_first_idle_seconds'] = round(rows[-1]['seconds'] - rejected, 3)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps({key: value for key, value in result.items() if key != 'rows'}))
        if not result['probe_completed']:
            raise RuntimeError('No completed real permission rejection; evidence is inconclusive')
    finally:
        server.terminate()
        try:
            server.wait(timeout=15)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait(timeout=5)
        log.close()


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Do not print arbitrary server error bodies or credentials.
        raise SystemExit('Probe failed: ' + type(error).__name__) from None
