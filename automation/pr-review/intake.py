#!/usr/bin/env python3
"""Read-only GitHub intake and revision-checked local receipts; never runs PR code."""
import argparse
import datetime
import fcntl
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile

POLICY = json.loads(Path(__file__).with_name('policy.json').read_text())
REPO = POLICY['repository']
SHA = re.compile(r'[0-9a-f]{40}\Z')
FINAL = {'no_fix_needed', 'needs_human_review', 'ready_for_approval'}
STATUSES = FINAL | {'waiting_checks', 'retry'}


def api(endpoint):
    # Literal repository, list arguments, GET only. PR content never becomes shell code.
    result = subprocess.run(['gh', 'api', '--method', 'GET',
                             f'repos/{REPO}/{endpoint}'], check=True,
                            text=True, capture_output=True, timeout=45)
    return json.loads(result.stdout)


def pages(endpoint):
    result = []
    for page in range(1, 31):
        data = api(f'{endpoint}{"&" if "?" in endpoint else "?"}per_page=100&page={page}')
        result.extend(data)
        if len(data) < 100:
            return result
    raise ValueError('Pagination limit reached; do not treat partial results as complete.')


def identity(pr):
    head, base = pr['head']['sha'], pr['base']['sha']
    if not SHA.fullmatch(head) or not SHA.fullmatch(base):
        raise ValueError('Invalid commit identity')
    if type(pr['number']) is not int or pr['number'] < 1:
        raise ValueError('Invalid PR number')
    return f"{pr['number']}:{head}:{base}"


def safe_path(path):
    return (isinstance(path, str) and bool(path) and '\\' not in path
            and not any(ord(c) < 32 for c in path)
            and not PurePosixPath(path).is_absolute()
            and '..' not in PurePosixPath(path).parts
            and str(PurePosixPath(path)) == path)


def guarded_path(path):
    lower = path.lower()
    return (not safe_path(path)
            or any(lower.startswith(p.lower()) for p in POLICY['protected_prefixes'])
            or PurePosixPath(path).name.lower() in {p.lower() for p in POLICY['protected_names']}
            or any(term in lower for term in POLICY['protected_terms'])
            or lower.endswith(('.pem', '.key', '.p12', '.mobileprovision')))


def candidate(pr, files):
    key = identity(pr)
    reasons = []
    if pr['base']['ref'] != POLICY['base_branch']:
        reasons.append('non-main base')
    if len(files) != pr['changed_files'] or len(files) > POLICY['max_files']:
        reasons.append('incomplete or oversized file list')
    if sum(len(f.get('patch', '').encode()) for f in files) > POLICY['max_patch_bytes']:
        reasons.append('oversized diff')
    for f in files:
        path = f['filename']
        if guarded_path(path) or (f.get('previous_filename') and guarded_path(f['previous_filename'])):
            reasons.append('protected or unsafe path: ' + path)
        if 'patch' not in f:
            reasons.append('binary, empty or truncated patch: ' + path)
        if f.get('status') == 'renamed':
            reasons.append('rename requires manual inspection: ' + path)
    return {'key': key, 'number': pr['number'],
            'url': f"https://github.com/{REPO}/pull/{pr['number']}",
            'head': pr['head']['sha'], 'base': pr['base']['sha'],
            'draft': pr['draft'], 'title': pr['title'],
            'paths': [f['filename'] for f in files],
            'mode': 'manual' if reasons else 'review', 'reasons': reasons}


def checks(sha):
    if not SHA.fullmatch(sha):
        raise ValueError('Invalid check revision')
    # Verify the fixed workflow identity too; a different workflow using the same
    # job name must not satisfy the gate. Runs are tied to their precise head SHA.
    runs = api(f'actions/workflows/pr-checks.yml/runs?head_sha={sha}&per_page=100')['workflow_runs']
    if not runs:
        return {'passed': False, 'reason': 'No trusted workflow run for this revision'}
    run = max(runs, key=lambda r: r['id'])
    if run['head_sha'] != sha or run['event'] not in ('push', 'pull_request'):
        return {'passed': False, 'reason': 'Unexpected workflow revision or event'}
    jobs = api(f"actions/runs/{run['id']}/jobs?filter=latest&per_page=100")['jobs']
    by_name = {j['name']: j for j in jobs}
    passed = (run['status'] == 'completed' and run['conclusion'] == 'success'
              and all(name in by_name and by_name[name]['status'] == 'completed'
                      and by_name[name]['conclusion'] == 'success'
                      for name in POLICY['required_checks']))
    return {'passed': passed, 'url': run['html_url'], 'run': run['id'],
            'status': run['status'], 'conclusion': run['conclusion']}


def tree_check(sha):
    if not SHA.fullmatch(sha):
        raise ValueError('Invalid tree revision')
    tree = api(f'git/trees/{sha}?recursive=1')
    unsafe = [t['path'] for t in tree['tree']
              if not safe_path(t['path']) or t['mode'] in ('120000', '160000')]
    return {'safe': not tree.get('truncated') and not unsafe,
            'truncated': tree.get('truncated', False), 'unsafe_paths': unsafe}


def scan(state):
    queue = []
    all_prs = pages('pulls?state=open&sort=created&direction=asc')
    for summary in all_prs:
        ref = summary['head']['ref']
        # Only skip our own generated branches in our own repository, not a fork
        # using a matching branch name to evade review.
        own = (summary['head'].get('repo') or {}).get('full_name', '').lower() == REPO.lower()
        if own and (ref.startswith(POLICY['fix_prefix']) or ref == POLICY['setup_branch']):
            continue
        detail = api(f"pulls/{summary['number']}")
        key = identity(detail)
        previous = state.get(key)
        if previous and previous.get('status') in FINAL:
            if previous['status'] != 'ready_for_approval':
                continue
            fix = api(f"pulls/{previous['fix_pr']}")
            if fix['state'] == 'open' and fix['head']['sha'] == previous['fix_head']:
                continue
            previous = dict(previous, status='retry', reason='Prepared fix changed or closed')
        files = pages(f"pulls/{detail['number']}/files")
        item = candidate(detail, files)
        if item['mode'] == 'review':
            if not tree_check(detail['head']['sha'])['safe']:
                item['mode'] = 'manual'
                item['reasons'].append('Unsafe or incomplete repository tree')
        item['previous'] = previous
        queue.append(item)
        if len(queue) >= POLICY['max_prs_per_run']:
            break
    return {'repository': REPO, 'open_prs': len(all_prs), 'candidates': queue}


def record(state, number, head, base, status, fix_pr=None):
    pr = api(f'pulls/{number}')
    expected = f'{number}:{head}:{base}'
    if pr['state'] != 'open' or identity(pr) != expected:
        raise ValueError('PR closed or revision changed; do not save stale review')
    if status not in STATUSES:
        raise ValueError('Unknown review status')
    item = {'status': status, 'recorded_at': now()}
    if fix_pr is not None:
        if fix_pr == number:
            raise ValueError('Fix must be a separate draft PR')
        fix = api(f'pulls/{fix_pr}')
        own = (fix['head'].get('repo') or {}).get('full_name', '').lower() == REPO.lower()
        prefix = f"{POLICY['fix_prefix']}{number}-{head[:12]}"
        if (not own or fix['state'] != 'open' or not fix['draft']
                or not fix['head']['ref'].startswith(prefix)
                or fix['base']['ref'] != POLICY['base_branch']):
            raise ValueError('Fix PR does not meet draft, repository, branch or base gate')
        item.update(fix_pr=fix_pr, fix_head=fix['head']['sha'])
        if status == 'ready_for_approval' and not checks(fix['head']['sha'])['passed']:
            raise ValueError('Fix checks did not pass at the current revision')
    elif status == 'ready_for_approval':
        raise ValueError('A tested separate draft fix PR is required')
    state[expected] = item
    return item


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def write_json(path, data):
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as stream:
        json.dump(data, stream, indent=2, ensure_ascii=False)
        stream.write('\n')
        temporary = stream.name
    os.replace(temporary, path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state-dir', type=Path, required=True)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('scan')
    check = sub.add_parser('checks'); check.add_argument('--sha', required=True)
    tree = sub.add_parser('tree'); tree.add_argument('--sha', required=True)
    save = sub.add_parser('record')
    save.add_argument('--number', type=int, required=True)
    save.add_argument('--head', required=True); save.add_argument('--base', required=True)
    save.add_argument('--status', choices=sorted(STATUSES), required=True)
    save.add_argument('--fix-pr', type=int)
    args = parser.parse_args()
    root = args.state_dir.resolve(); root.mkdir(parents=True, exist_ok=True)
    with (root / 'lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = root / 'state.json'
        state = json.loads(path.read_text()) if path.exists() else {}
        if args.command == 'scan': result = scan(state)
        elif args.command == 'checks': result = checks(args.sha)
        elif args.command == 'tree': result = tree_check(args.sha)
        else:
            result = record(state, args.number, args.head, args.base, args.status, args.fix_pr)
            write_json(path, state)
        receipt = {'at': now(), 'command': args.command, 'result': result}
        write_json(root / 'last-run.json', receipt)
        print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
