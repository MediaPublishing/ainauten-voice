import copy
import unittest
from unittest.mock import patch
import intake as subject

HEAD = 'a' * 40
BASE = 'b' * 40
FIX = 'c' * 40


def pr(number=10, head=HEAD, base=BASE, ref='fix/example', repo=subject.REPO):
    return {'number': number, 'head': {'sha': head, 'ref': ref, 'repo': {'full_name': repo}},
            'base': {'sha': base, 'ref': 'main'}, 'changed_files': 1,
            'title': 'Example; $(do-not-execute)', 'draft': False, 'state': 'open'}


FILE = {'filename': 'native/Sources/VoiceWispr/Pill.swift', 'patch': '@@ -1 +1 @@\n-old\n+new', 'status': 'modified'}


class IntakeTests(unittest.TestCase):
    def scan(self, details, state=None):
        def api(endpoint):
            if endpoint.startswith('pulls?'):
                return details
            if '/files?' in endpoint:
                return [FILE]
            if endpoint.startswith('git/trees/'):
                return {'truncated': False, 'tree': [{'path': FILE['filename'], 'mode': '100644'}]}
            return next(p for p in details if endpoint == f"pulls/{p['number']}")
        with patch.object(subject, 'api', side_effect=api):
            return subject.scan(state or {})

    def test_new_revision_and_base_are_reviewed_but_completed_revision_is_quiet(self):
        previous = {subject.identity(pr()): {'status': 'no_fix_needed'}}
        self.assertEqual(self.scan([pr()], previous)['candidates'], [])
        self.assertEqual(len(self.scan([pr(head=FIX)], previous)['candidates']), 1)
        self.assertEqual(len(self.scan([pr(base=FIX)], previous)['candidates']), 1)

    def test_pending_checks_are_retried_without_creating_another_fix(self):
        previous = {subject.identity(pr()): {'status': 'waiting_checks', 'fix_pr': 11}}
        item = self.scan([pr()], previous)['candidates'][0]
        self.assertEqual(item['previous']['fix_pr'], 11)

    def test_changed_fix_is_reviewed_again_after_it_was_ready(self):
        previous = {subject.identity(pr()): {'status': 'ready_for_approval', 'fix_pr': 11, 'fix_head': HEAD}}
        result = self.scan([pr(), pr(number=11, head=FIX, ref='automation/pr-fix-10-aaaaaaaaaaaa')], previous)
        self.assertEqual(len(result['candidates']), 1)
        self.assertEqual(result['candidates'][0]['previous']['status'], 'retry')

    def test_own_generated_fix_is_skipped_but_matching_fork_name_cannot_evade_review(self):
        ref = 'automation/pr-fix-10-aaaaaaaaaaaa'
        self.assertFalse(self.scan([pr(ref=ref)])['candidates'])
        self.assertEqual(len(self.scan([pr(ref=ref, repo='external/fork')])['candidates']), 1)

    def test_run_is_bounded_and_drafts_are_not_silently_ignored(self):
        items = [pr(number=n) for n in range(10, 15)]
        items[0]['draft'] = True
        result = self.scan(items)
        self.assertEqual(len(result['candidates']), 3)
        self.assertTrue(result['candidates'][0]['draft'])

    def test_three_pending_prs_do_not_starve_a_new_submission(self):
        items = [pr(number=n) for n in range(10, 14)]
        previous = {subject.identity(p): {'status': 'waiting_checks'} for p in items[:3]}
        result = self.scan(items, previous)
        self.assertEqual(result['candidates'][0]['number'], 13)

    def test_unsafe_and_control_plane_changes_require_a_human(self):
        for path in ('../escape.swift', '/absolute', 'a/../b', 'a\\b', 'a\nb',
                     '.github/workflows/test.yml', 'nested/AGENTS.md', '.gitattributes',
                     'native/Sources/VoiceWisprCore/SettingsStore.swift', 'private.key'):
            with self.subTest(path=path):
                changed = dict(FILE, filename=path)
                self.assertEqual(subject.candidate(pr(), [changed])['mode'], 'manual')

    def test_binary_incomplete_and_oversized_diffs_are_not_auto_fixed(self):
        variants = [dict(FILE, patch='x' * 200001), {'filename': 'picture.png', 'status': 'modified'}]
        for changed in variants:
            self.assertEqual(subject.candidate(pr(), [changed])['mode'], 'manual')
        detail = pr(); detail['changed_files'] = 2
        self.assertEqual(subject.candidate(detail, [FILE])['mode'], 'manual')

    def test_rename_from_protected_path_cannot_hide_a_guarded_change(self):
        changed = dict(FILE, previous_filename='AGENTS.md', status='renamed')
        self.assertEqual(subject.candidate(pr(), [changed])['mode'], 'manual')

    def test_symlinks_submodules_and_truncated_trees_block_checkout(self):
        for tree in ({'truncated': True, 'tree': []},
                     {'tree': [{'path': 'link', 'mode': '120000'}]},
                     {'tree': [{'path': 'module', 'mode': '160000'}]}):
            with patch.object(subject, 'api', return_value=tree):
                self.assertFalse(subject.tree_check(HEAD)['safe'])

    def test_closed_or_changed_revision_does_not_overwrite_receipts(self):
        for live in (pr(head=FIX), dict(pr(), state='closed'), pr(base=FIX)):
            state = {'preserved': {'status': 'no_fix_needed'}}
            before = copy.deepcopy(state)
            with patch.object(subject, 'api', return_value=live), self.assertRaises(ValueError):
                subject.record(state, 10, HEAD, BASE, 'no_fix_needed')
            self.assertEqual(state, before)

    def test_only_a_separate_owned_draft_with_green_current_checks_can_be_ready(self):
        fix = pr(number=11, head=FIX, ref='automation/pr-fix-10-aaaaaaaaaaaa')
        fix['draft'] = True
        with patch.object(subject, 'api', side_effect=[pr(), fix]), patch.object(subject, 'checks', return_value={'passed': True}):
            result = subject.record({}, 10, HEAD, BASE, 'ready_for_approval', 11)
            self.assertEqual(result['fix_head'], FIX)
        for unsafe in (dict(fix, draft=False), pr(number=11), dict(fix, state='closed')):
            with patch.object(subject, 'api', side_effect=[pr(), unsafe]), self.assertRaises(ValueError):
                subject.record({}, 10, HEAD, BASE, 'ready_for_approval', 11)
        with patch.object(subject, 'api', side_effect=[pr(), fix]), patch.object(subject, 'checks', return_value={'passed': False}), self.assertRaises(ValueError):
            subject.record({}, 10, HEAD, BASE, 'ready_for_approval', 11)

    def test_check_gate_rejects_absent_stale_skipped_failed_or_incomplete_runs(self):
        run = {'id': 1, 'head_sha': FIX, 'event': 'push', 'status': 'completed',
               'conclusion': 'success', 'html_url': 'https://github.com/example/run/1'}
        jobs = [{'name': n, 'status': 'completed', 'conclusion': 'success'} for n in subject.POLICY['required_checks']]
        with patch.object(subject, 'api', return_value={'workflow_runs': []}):
            self.assertFalse(subject.checks(FIX)['passed'])
        for bad in (dict(run, head_sha=HEAD), dict(run, event='workflow_dispatch'), dict(run, conclusion='failure')):
            with patch.object(subject, 'api', side_effect=[{'workflow_runs': [bad]}, {'jobs': jobs}]):
                self.assertFalse(subject.checks(FIX)['passed'])
        for broken in ([jobs[0]], [dict(j, conclusion='skipped') for j in jobs],
                       [dict(j, status='in_progress') for j in jobs]):
            with patch.object(subject, 'api', side_effect=[{'workflow_runs': [run]}, {'jobs': broken}]):
                self.assertFalse(subject.checks(FIX)['passed'])
        with patch.object(subject, 'api', side_effect=[{'workflow_runs': [run]}, {'jobs': jobs}]):
            self.assertTrue(subject.checks(FIX)['passed'])

    def test_metadata_stays_data_and_invalid_commit_identity_is_rejected(self):
        self.assertIn('$(do-not-execute)', subject.candidate(pr(), [FILE])['title'])
        with self.assertRaises(ValueError):
            subject.identity(pr(head='--bad-option'))


if __name__ == '__main__':
    unittest.main()
