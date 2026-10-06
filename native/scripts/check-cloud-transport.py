#!/usr/bin/env python3
"""Real macOS CloudFormatter HTTP checks using only synthetic data on loopback.
No model loading, application settings, keychain access or external recipients.
"""
import argparse
from collections import Counter
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import threading


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=root / 'artifacts/receipts/cloud-transport-current.json')
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    out = root / 'artifacts/cloud-transport-checks'
    out.mkdir(parents=True, exist_ok=True)
    started = datetime.now(timezone.utc).isoformat()
    # Same native object layout as portable-checks.py; never rebuild/replace the
    # release Probe while it may be running a long speech benchmark.
    build_run = subprocess.run(['swift', 'build', '--build-system', 'native', '--target', 'VoiceWisprCore', '--jobs', '4'],
                               cwd=root, capture_output=True, text=True)
    (out / 'build.log').write_text(build_run.stdout + build_run.stderr)
    if build_run.returncode:
        raise SystemExit(build_run.returncode)
    build = root / '.build/arm64-apple-macosx/debug'
    command = ['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-target', 'arm64-apple-macosx14.0',
               '-I', str(build / 'Modules'), '-I', str(root / 'Sources/CSQLite'),
               '-I', str(build / 'FastClusterWrapper.build'), '-I', str(build / 'MachTaskSelfWrapper.build'),
               '-F', str(build), '-L', str(build)]
    for framework in ['llama', 'Accelerate', 'CoreML', 'AppKit', 'AVFoundation', 'ApplicationServices', 'Security', 'Carbon']:
        command += ['-framework', framework]
    command += ['-lsqlite3', '-lc++', '-Xlinker', '-rpath', '-Xlinker', str(build)]
    for target in ['FastClusterWrapper', 'MachTaskSelfWrapper']:
        include = root / '.build/checkouts/FluidAudio/Sources' / target / 'include'
        command += ['-Xcc', '-fmodule-map-file=' + str(include / 'module.modulemap'), '-Xcc', '-I' + str(include)]
    for target in ['VoiceWisprCore.build', 'FluidAudio.build', 'FastClusterWrapper.build', 'MachTaskSelfWrapper.build']:
        command += [str(p) for p in sorted((build / target).glob('*.o'))]
    binary = out / 'CloudTransportChecks'
    command += [str(root / 'Tests/Native/CloudTransportChecks.swift'), '-o', str(binary)]
    compile_run = subprocess.run(command, cwd=root, capture_output=True, text=True)
    (out / 'compile.log').write_text(compile_run.stdout + compile_run.stderr)
    if compile_run.returncode:
        raise SystemExit(compile_run.returncode)

    requests, lock, release = [], threading.Lock(), threading.Event()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            # A 302 could turn the forbidden second request into a GET.
            with lock:
                requests.append({'name': self.path.split('/')[1], 'path': self.path, 'method': 'GET'})
            self.send_error(501)

        def do_POST(self):
            name = self.path.split('/')[1]
            body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            record = {'name': name, 'path': self.path, 'method': 'POST',
                      'textOnlySchema': set(body) == {'model', 'temperature', 'messages'},
                      'syntheticAuthorization': self.headers.get('Authorization') == 'Bearer synthetic-test',
                      'currentTextMatches': body['messages'][-1]['content'] == '<CONTEXT></CONTEXT>\n<CURRENT>Der Bericht wird nicht heute versendet.</CURRENT>'}
            with lock:
                requests.append(record)
            if name in {'timeout', 'cancel'}:
                release.wait(20)
                self.close_connection = True
                return
            status = {'status401': 401, 'status429': 429, 'redirect': 302}.get(name, 200)
            record['status'] = status
            response = json.dumps({'choices': [{'message': {'content': 'Der Bericht wird nicht heute versendet.'}}]}).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(response)))
            if name == 'redirect':
                self.send_header('Location', '/second-recipient/chat/completions')
            self.end_headers()
            self.wfile.write(response)

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        run = subprocess.run([str(binary), f'http://127.0.0.1:{server.server_port}'], cwd=root,
                             capture_output=True, text=True, timeout=35)
        (out / 'native.stdout').write_text(run.stdout)
        (out / 'native.stderr').write_text(run.stderr)
        native = json.loads(run.stdout) if run.returncode == 0 else {'cases': []}
        counts = Counter(record['name'] for record in requests)
        expected = ['success', 'status401', 'status429', 'redirect', 'timeout', 'cancel', 'original']
        native_passed = len(native['cases']) == len(expected) and {x['name'] for x in native['cases']} == set(expected) and all(x['passed'] for x in native['cases'])
        server_passed = counts == Counter({name: 1 for name in expected if name != 'original'}) and all(
            x.get('textOnlySchema', False) and x.get('syntheticAuthorization', False) and x.get('currentTextMatches', False) for x in requests)
        report = {'startedAt': started, 'endedAt': datetime.now(timezone.utc).isoformat(),
                  'allPassed': native_passed and server_passed, 'native': native, 'requestCounts': dict(counts),
                  'requests': requests, 'timeoutPolicySeconds': 10, 'timeoutMeasurementToleranceSeconds': 0.5,
                  'exitCode': run.returncode, 'productionChanged': False, 'externalRecipients': False,
                  'scope': 'Real CLI Foundation transport using production CloudFormatter; no installed-app UI, microphone, ASR, model or full pipeline acceptance.'}
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        print(json.dumps({'allPassed': report['allPassed'], 'cases': len(native['cases']), 'requestCounts': dict(counts)}))
        return 0 if report['allPassed'] else 1
    finally:
        release.set()
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


if __name__ == '__main__':
    raise SystemExit(main())
