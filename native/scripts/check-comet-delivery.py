#!/usr/bin/env python3
"""Check real Core delivery in Comet using an owned synthetic loopback page.
Uses existing AX permission without requesting or changing permissions. Clipboard
bytes stay in RAM. Only boolean/count DOM results cross the loopback connection.
No microphone, speech models, user profiles, submitted messages or cloud calls.
"""
import argparse
from datetime import datetime, timezone
import http.server
import hashlib
import json
from pathlib import Path
import subprocess
import threading
import uuid


def page(marker, editor, mode):
    initial = 'Anfang ERSETZEN Ende'
    insertion = 'Öffentlicher Absatz. 12,5 bleibt unverändert, nicht 20. 👋\n' * 400 if mode.startswith('long') else 'öffentlicher Testtext 👋'
    expected = initial if mode == 'focus' else initial + insertion if mode == 'caret' else initial.replace('ERSETZEN', insertion)
    if mode == 'long-extra': expected += ' Zusatz'
    elif mode == 'long-mismatch': expected = expected[:-1] + 'X'
    elif mode == 'long-truncated': expected = expected[:len(expected)//2]
    field = '<textarea id="target" aria-label="Eigener Testtext"></textarea>' if editor == 'textarea' else '<div id="target" contenteditable="true" role="textbox" aria-label="Eigener Testtext"></div>'
    html = '''<!doctype html><meta charset="utf-8"><title>MARKER</title>
<style>body{font:20px system-ui;padding:30px} #target{display:block;width:80%;min-height:100px;border:1px solid;padding:10px;white-space:pre-wrap}</style>
<h1>Eigene lokale Testseite</h1><form>FIELD<input id="other" aria-label="Anderes eigenes Testfeld"></form>
<script>
const initial=INITIAL, expected=EXPECTED, editor=EDITOR, mode=MODE, target=document.getElementById('target'), other=document.getElementById('other');
let inputs=0,pastes=0,submits=0,sequence=0;
if(editor==='textarea')target.value=initial;else target.textContent=initial;
const text=()=>editor==='textarea'?target.value:target.innerText;
function report(){fetch(location.pathname+'/status',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({sequence:++sequence,expectedMatches:text()===expected,initialMatches:text()===initial,inputEvents:inputs,pasteEvents:pastes,submitEvents:submits,otherEmpty:other.value==='',activeTarget:document.activeElement===target,activeOther:document.activeElement===other})});}
target.addEventListener('input',()=>{inputs++;if(inputs===1&&mode.startsWith('long-')){if(editor==='textarea')target.value=expected;else target.textContent=expected;}report()});target.addEventListener('paste',()=>{pastes++;report()});
document.querySelector('form').addEventListener('submit',e=>{e.preventDefault();submits++;report()});
window.addEventListener('load',()=>{
 target.focus();const start=mode==='caret'?initial.length:initial.indexOf('ERSETZEN'),end=mode==='caret'?start:start+'ERSETZEN'.length;
 if(editor==='textarea')target.setSelectionRange(start,end);else{const r=document.createRange();r.setStart(target.firstChild,start);r.setEnd(target.firstChild,end);getSelection().removeAllRanges();getSelection().addRange(r);}
 report();
 if(mode==='focus')setInterval(async()=>{const c=await(await fetch(location.pathname+'/control')).json();if(c.focusOther&&text()===initial&&other.value===''){other.focus();report();}},50);
});
</script>'''
    for name, value in [('MARKER', marker), ('FIELD', field), ('INITIAL', json.dumps(initial)), ('EXPECTED', json.dumps(expected)), ('EDITOR', json.dumps(editor)), ('MODE', json.dumps(mode))]:
        html = html.replace(name, value)
    return html.encode()


def run_case(binary, out, editor, mode):
    marker = 'AInauten-Voice-Delivery-' + str(uuid.uuid4())
    path = '/' + marker
    body = page(marker, editor, mode)
    state, control = {}, {'focusOther': False}
    lock = threading.Lock()

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def respond(self, status, data, kind='application/json'):
            self.send_response(status)
            self.send_header('Content-Type', kind)
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def do_GET(self):
            if self.path == path:
                self.respond(200, body, 'text/html; charset=utf-8')
            elif self.path in [path + '/status', path + '/control']:
                with lock:
                    data = json.dumps(state if self.path.endswith('/status') else control).encode()
                self.respond(200, data)
            else:
                self.respond(404, b'{}')

        def do_POST(self):
            if self.path == path + '/focus':
                with lock:
                    control['focusOther'] = True
                return self.respond(200, b'{}')
            if self.path != path + '/status':
                return self.respond(404, b'{}')
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length < 1024:
                    raise ValueError('invalid size')
                value = json.loads(self.rfile.read(length))
                counters = ['inputEvents', 'pasteEvents', 'submitEvents', 'sequence']
                flags = ['expectedMatches', 'initialMatches', 'otherEmpty', 'activeTarget', 'activeOther']
                if set(value) != set(counters + flags) or not all(type(value[k]) is bool for k in flags) or not all(type(value[k]) is int and 0 <= value[k] < 100 for k in counters):
                    raise ValueError('metadata only')
            except (ValueError, TypeError, KeyError):
                return self.respond(400, b'{}')
            with lock:
                if value['sequence'] > state.get('sequence', -1):
                    state.update(value)
            self.respond(200, b'{}')

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    started = datetime.now(timezone.utc).isoformat()
    url = 'http://127.0.0.1:' + str(server.server_port) + path
    try:
        try:
            run = subprocess.run([str(binary), url, mode, editor], capture_output=True, text=True, timeout=30)
            code, stdout, stderr = run.returncode, run.stdout, run.stderr
        except subprocess.TimeoutExpired as error:
            code, stdout, stderr = None, (error.stdout or b'').decode(), (error.stderr or b'').decode()
        (out / (editor + '-' + mode + '.stdout')).write_text(stdout)
        (out / (editor + '-' + mode + '.stderr')).write_text(stderr)
        try:
            native = json.loads(stdout) if code == 0 else None
        except ValueError:
            native = None
        with lock:
            renderer = dict(state)
        return {'editor': editor, 'mode': mode, 'startedAt': started, 'endedAt': datetime.now(timezone.utc).isoformat(),
                'ownedFixtureURL': url, 'exitCode': code, 'native': native, 'renderer': renderer}
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--existing-binary', type=Path, help='Use an explicitly frozen native test artifact; receipt records its hash.')
    parser.add_argument('--artifacts-dir', type=Path)
    parser.add_argument('--editor', choices=['textarea', 'contenteditable'])
    parser.add_argument('--mode', choices=['selection', 'caret', 'long', 'focus', 'long-extra', 'long-mismatch', 'long-truncated'])
    parser.add_argument('--include-negatives', action='store_true', help='Also reject receiver-side excess, changed and incomplete long text.')
    parser.add_argument('--output', type=Path, default=root / 'artifacts/receipts/comet-delivery-current.json')
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    out = args.artifacts_dir or root / 'artifacts/comet-delivery-checks'
    out = out.resolve()
    if not out.is_relative_to(root / 'artifacts'):
        parser.error('artifacts-dir must be inside native/artifacts')
    out.mkdir(parents=True, exist_ok=True)
    started = datetime.now(timezone.utc).isoformat()
    if args.existing_binary:
        binary = args.existing_binary.resolve()
        if not binary.is_file():
            parser.error('existing native artifact unavailable')
    else:
        run = subprocess.run(['swift', 'build', '--build-system', 'native', '--target', 'VoiceWisprCore', '--jobs', '4'], cwd=root, capture_output=True, text=True)
        (out / 'build.log').write_text(run.stdout + run.stderr)
        if run.returncode:
            raise SystemExit(run.returncode)
        build = root / '.build/arm64-apple-macosx/debug'
        command = ['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-target', 'arm64-apple-macosx14.0', '-I', str(build / 'Modules'), '-I', str(root / 'Sources/CSQLite'), '-I', str(build / 'FastClusterWrapper.build'), '-I', str(build / 'MachTaskSelfWrapper.build'), '-F', str(build), '-L', str(build)]
        for framework in ['llama', 'Accelerate', 'CoreML', 'AppKit', 'AVFoundation', 'ApplicationServices', 'Security', 'Carbon']:
            command += ['-framework', framework]
        command += ['-lsqlite3', '-lc++', '-Xlinker', '-rpath', '-Xlinker', str(build)]
        for target in ['FastClusterWrapper', 'MachTaskSelfWrapper']:
            include = root / '.build/checkouts/FluidAudio/Sources' / target / 'include'
            command += ['-Xcc', '-fmodule-map-file=' + str(include / 'module.modulemap'), '-Xcc', '-I' + str(include)]
        for target in ['VoiceWisprCore.build', 'FluidAudio.build', 'FastClusterWrapper.build', 'MachTaskSelfWrapper.build']:
            command += [str(p) for p in sorted((build / target).glob('*.o'))]
        binary = out / 'CometDeliveryChecks'
        command += [str(root / 'Tests/Native/CometDeliveryChecks.swift'), '-o', str(binary)]
        run = subprocess.run(command, cwd=root, capture_output=True, text=True)
        (out / 'compile.log').write_text(run.stdout + run.stderr)
        if run.returncode:
            raise SystemExit(run.returncode)
    cases = []
    editors = [args.editor] if args.editor else ['textarea', 'contenteditable']
    modes = [args.mode] if args.mode else ['selection', 'caret', 'long', 'focus'] + (['long-extra', 'long-mismatch', 'long-truncated'] if args.include_negatives else [])
    for editor in editors:
        for mode in modes:
            case = run_case(binary, out, editor, mode)
            cases.append(case)
            (out / (editor + '-' + mode + '.case.json')).write_text(json.dumps(case, ensure_ascii=False, indent=2) + '\n')
            # Do not keep opening tabs after failed or unsafe preparation.
            if not isinstance(case['native'], dict) or not case['native'].get('passed'):
                break
        if not isinstance(cases[-1]['native'], dict) or not cases[-1]['native'].get('passed'):
            break
    report = {'startedAt': started, 'endedAt': datetime.now(timezone.utc).isoformat(),
              'expectedCases': len(editors) * len(modes), 'allPassed': len(cases) == len(editors) * len(modes) and all(isinstance(case['native'], dict) and case['native'].get('passed') for case in cases), 'cases': cases,
              'nativeBinarySHA256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'productionChanged': False, 'clipboardContentsLogged': False, 'microphoneUsed': False, 'modelsLoaded': False,
              'scope': 'Requested real Comet Core delivery cases with independent DOM metadata; no physical hotkey, microphone, ASR, installed-app recovery UI or full OS matrix/p95 acceptance.'}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'allPassed': report['allPassed'], 'cases': len(cases), 'passed': sum(bool(case['native'] and case['native'].get('passed')) for case in cases)}))
    return 0 if report['allPassed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
