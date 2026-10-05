#!/usr/bin/env python3
"""Check actual ModelDownloader HTTP using tiny public loopback fixtures.
Never loads models or touches app settings, permissions, user model directories,
keychain, clipboard or external providers. All own fixture files are retained.
"""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import socket
import subprocess
import threading
import uuid


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=root / 'artifacts/receipts/download-transport-current.json')
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    out = root / 'artifacts/download-transport-checks'
    out.mkdir(parents=True, exist_ok=True)
    started = datetime.now(timezone.utc).isoformat()
    # Build only the debug Core target; do not replace a running release Probe.
    run = subprocess.run(['swift', 'build', '--build-system', 'native', '--target', 'VoiceWisprCore', '--jobs', '4'],
                         cwd=root, capture_output=True, text=True)
    (out / 'build.log').write_text(run.stdout + run.stderr)
    if run.returncode:
        raise SystemExit(run.returncode)
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
    binary = out / 'DownloadTransportChecks'
    command += [str(root / 'Tests/Native/DownloadTransportChecks.swift'), '-o', str(binary)]
    run = subprocess.run(command, cwd=root, capture_output=True, text=True)
    (out / 'compile.log').write_text(run.stdout + run.stderr)
    if run.returncode:
        print(run.stderr)
        raise SystemExit(run.returncode)
    payload = bytes(i % 251 for i in range(1_048_576))
    digest = hashlib.sha256(payload).hexdigest()
    requests, counts, lock, stop = [], Counter(), threading.Lock(), threading.Event()
    expected = ['success', 'interruptedResume', 'cancelResume', 'wrongRange', 'reset200', 'badHash', 'sameSizeCorruption', 'oversized']

    class Handler(BaseHTTPRequestHandler):
        # One connection per request. Deliberate cancel/range rejection should
        # not produce a harmless keep-alive read traceback on the next read.
        protocol_version = 'HTTP/1.0'

        def log_message(self, *_):
            pass

        def do_GET(self):
            name = self.path.removeprefix('/')
            if name not in expected:
                self.send_error(404)
                return
            raw_range = self.headers.get('Range')
            try:
                offset = int(raw_range.removeprefix('bytes=').removesuffix('-')) if raw_range else 0
                if not 0 <= offset < len(payload):
                    raise ValueError('range')
            except ValueError:
                self.send_error(416)
                return
            with lock:
                counts[name] += 1
                attempt = counts[name]
                record = {'name': name, 'attempt': attempt, 'offset': offset,
                          'rangeProvided': raw_range is not None, 'identityEncoding': self.headers.get('Accept-Encoding') == 'identity'}
                requests.append(record)
            body = payload[offset:]
            status = 206 if raw_range else 200
            if name == 'reset200':
                status, body = 200, payload
            elif name == 'badHash':
                body = bytes([255]) + payload[1:]
            elif name == 'oversized':
                body += bytes(5)
            record['status'] = status
            self.send_response(status)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            if status == 206:
                range_start = offset + (1 if name == 'wrongRange' else 0)
                self.send_header('Content-Range', f'bytes {range_start}-{len(payload)-1}/{len(payload)}')
            self.end_headers()
            try:
                if name == 'interruptedResume' and attempt == 1:
                    self.wfile.write(body[:262_144]); self.wfile.flush()
                    self.connection.shutdown(socket.SHUT_WR)
                    self.close_connection = True
                elif name == 'cancelResume' and attempt == 1:
                    for i in range(0, len(body), 16_384):
                        if stop.is_set():
                            break
                        self.wfile.write(body[i:i+16_384]); self.wfile.flush()
                        stop.wait(0.03)
                else:
                    self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError, OSError):
                self.close_connection = True

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    fixture = out / ('AInauten-Voice-Downloads-' + str(uuid.uuid4()))
    try:
        try:
            run = subprocess.run([str(binary), f'http://127.0.0.1:{server.server_port}', str(fixture), digest, str(len(payload))],
                                 cwd=root, capture_output=True, text=True, timeout=30)
            code, stdout, stderr = run.returncode, run.stdout, run.stderr
        except subprocess.TimeoutExpired as error:
            code = None
            stdout, stderr = (error.stdout or b'').decode(errors='replace'), (error.stderr or b'').decode(errors='replace')
        (out / 'native.stdout').write_text(stdout)
        (out / 'native.stderr').write_text(stderr)
        try:
            native = json.loads(stdout) if code == 0 else {'cases': [], 'allPassed': False}
        except ValueError:
            native = {'cases': [], 'allPassed': False}
    finally:
        stop.set()
        server.shutdown(); server.server_close(); thread.join(timeout=2)
    with lock:
        records = list(requests)
    required_counts = Counter({name: (2 if name in {'interruptedResume', 'cancelResume'} else 1) for name in expected})
    by_name = {name: [r for r in records if r['name'] == name] for name in expected}
    server_passed = Counter(r['name'] for r in records) == required_counts and all(r['identityEncoding'] for r in records)
    for name in ['interruptedResume', 'cancelResume']:
        rows = by_name[name]
        server_passed = server_passed and len(rows) == 2 and rows[0]['offset'] == 0 and rows[1]['offset'] > 0 and rows[1]['status'] == 206
    for name in ['wrongRange', 'reset200']:
        rows = by_name[name]
        server_passed = server_passed and len(rows) == 1 and rows[0]['offset'] == 4096
    report = {'startedAt': started, 'endedAt': datetime.now(timezone.utc).isoformat(),
              'allPassed': native.get('allPassed') is True and server_passed and code == 0,
              'native': native, 'serverPassed': server_passed, 'requests': records,
              'exitCode': code, 'fixtureRoot': str(fixture), 'fixturePayloadSHA256': digest,
              'nativeSourceSHA256': hashlib.sha256((root / 'Tests/Native/DownloadTransportChecks.swift').read_bytes()).hexdigest(),
              'runnerSourceSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'actualModelWeights': False, 'applicationChanged': False, 'externalRecipients': False}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'allPassed': report['allPassed'], 'serverPassed': server_passed,
                      'cases': len(native['cases']), 'passed': sum(c['passed'] for c in native['cases'])}))
    return 0 if report['allPassed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
