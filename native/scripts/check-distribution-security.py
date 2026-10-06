#!/usr/bin/env python3
"""Regression checks for Apple release admission; no credentials or key writes."""
import importlib.util
import contextlib
import io
from pathlib import Path
import plistlib
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import distribution_security as security

ROOT = Path(__file__).resolve().parents[1]
GOOD = ('Authority=Developer ID Application: Synthetic Fixture (ABCDE12345)\n'
        'TeamIdentifier=ABCDE12345\n'
        'CodeDirectory v=20500 flags=0x10000(runtime) hashes=1+1\n'
        'Timestamp=Oct 6, 2026\n')


class DistributionSecurityTests(unittest.TestCase):
    def testEntitlementsExplicitlyUseXML(self):
        def codesign(command):
            if '--entitlements' in command:
                self.assertIn('--xml', command)
                return subprocess.CompletedProcess(command, 0, plistlib.dumps({}), b'')
            return subprocess.CompletedProcess(command, 0, b'', GOOD.encode())
        with patch.object(security, 'run', side_effect=codesign):
            self.assertEqual(security.verify_code(Path('/synthetic.app')), 'ABCDE12345')

    def testActualCodesignXMLReadsLibraryValidationException(self):
        app = Path('/Applications/AInauten Voice.app')
        if not app.exists():
            self.skipTest('existing installed bundle unavailable')
        payload = security.run(['codesign', '-d', '--entitlements', '-', '--xml', app]).stdout
        entitlements = plistlib.loads(payload)
        self.assertIsInstance(entitlements, dict)
        if entitlements.get('com.apple.security.cs.disable-library-validation'):
            with self.assertRaises(ValueError):
                security.validate_metadata(GOOD, entitlements)

    def testBetaModeRejectsDebugAdhocAndNotaryCombinations(self):
        for extra in ['--development', '--debug', '--adhoc', '--notary-profile=x']:
            process = subprocess.run(['python3', str(ROOT/'scripts/package.py'), '--local-beta', extra], capture_output=True, text=True, timeout=10)
            self.assertNotEqual(process.returncode, 0)
            self.assertIn('--local-beta cannot be combined', process.stderr)

    def testLocalBetaCannotAcceptUnmarkedExistingApp(self):
        with tempfile.TemporaryDirectory(prefix='voice-unmarked-fixture-') as temp:
            app = Path(temp)/'AInauten Voice.app'; (app/'Contents').mkdir(parents=True)
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.mediapublishing.VoiceWispr'}))
            with self.assertRaisesRegex(ValueError, 'explicit local-beta marker'):
                security.verify_local_beta_app(app)

    def testBetaAllowsOnlyExistingMainLibraryException(self):
        with tempfile.TemporaryDirectory(prefix='voice-beta-fixture-') as temp:
            app = Path(temp)/'AInauten Voice.app'
            (app/'Contents/MacOS').mkdir(parents=True)
            (app/'Contents/Frameworks').mkdir()
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.mediapublishing.VoiceWispr', 'CFBundleExecutable':'VoiceWispr', 'AInautenDistributionMode':'local-beta'}))
            main = app/'Contents/MacOS/VoiceWispr'; main.write_bytes(b'\xcf\xfa\xed\xfe')
            nested = app/'Contents/Frameworks/test.dylib'; nested.write_bytes(b'\xcf\xfa\xed\xfe')
            def probe(command):
                entitlements = {'com.apple.security.cs.disable-library-validation': True} if Path(command[-1]) in [app, main] else {}
                if '--entitlements' in command:
                    return subprocess.CompletedProcess(command, 0, plistlib.dumps(entitlements), b'')
                return subprocess.CompletedProcess(command, 0, b'', b'TeamIdentifier=not set\nCodeDirectory v=20500 flags=0x10000(runtime)\n')
            with patch.object(security, 'run', side_effect=probe):
                result = security.verify_local_beta_app(app)
                self.assertFalse(result['notarized'])
                self.assertEqual(result['codeObjects'], 2)
            def malicious(command):
                if '--entitlements' in command:
                    return subprocess.CompletedProcess(command, 0, plistlib.dumps({'com.apple.security.get-task-allow':True}), b'')
                return probe(command)
            with patch.object(security, 'run', side_effect=malicious), self.assertRaisesRegex(ValueError, 'code-injection exception'):
                security.verify_local_beta_app(app)
            def nested_exception(command):
                if '--entitlements' in command and Path(command[-1]) == nested:
                    return subprocess.CompletedProcess(command, 0, plistlib.dumps({'com.apple.security.cs.disable-library-validation':True}), b'')
                return probe(command)
            with patch.object(security, 'run', side_effect=nested_exception), self.assertRaisesRegex(ValueError, 'nested beta code'):
                security.verify_local_beta_app(app)

    def testStrictMetadataAndExplicitFalseExceptions(self):
        self.assertEqual(security.validate_metadata(GOOD, {}), 'ABCDE12345')
        self.assertEqual(security.validate_metadata(GOOD, {k: False for k in security.FORBIDDEN}), 'ABCDE12345')

    def testEveryInjectionExceptionIsRejected(self):
        for key in security.FORBIDDEN:
            with self.subTest(key=key), self.assertRaises(ValueError):
                security.validate_metadata(GOOD, {key: True})

    def testMissingTeamRuntimeTimestampAndWrongAuthorityRejected(self):
        for line in GOOD.splitlines():
            with self.subTest(line=line), self.assertRaises(ValueError):
                security.validate_metadata(GOOD.replace(line + '\n', ''), {})
        for value in ['Apple Development:', 'Voice Wispr Local Signing:']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                security.validate_metadata(GOOD.replace('Developer ID Application:', value), {})

    def testWrongNestedTeamRejected(self):
        with self.assertRaises(ValueError):
            security.validate_metadata(GOOD, {}, 'OTHER12345')

    def testGatekeeperFailureNotSwallowed(self):
        with patch.object(security, 'run', side_effect=subprocess.CalledProcessError(1, ['stapler'])):
            with self.assertRaises(subprocess.CalledProcessError):
                security.verify_ticket(Path('/synthetic.app'))

    def testActualInstalledLocalBundleRejected(self):
        app = Path('/Applications/AInauten Voice.app')
        if not app.exists():
            self.skipTest('existing installed bundle unavailable')
        metadata = security.run(['codesign', '-dv', '--verbose=4', app]).stderr.decode()
        if 'TeamIdentifier=not set' not in metadata:
            self.skipTest('installed local-signing negative fixture no longer available')
        # Real codesign evaluation, read-only. No app launch or permission changes.
        with self.assertRaises((ValueError, subprocess.CalledProcessError)):
            security.verify_distribution_app(app)

    def testPublicPackagerRejectsLocalIdentityBeforeBuild(self):
        fingerprint = (ROOT/'Resources/release-signing-fingerprint.txt').read_text().strip()
        def identities(command, **kwargs):
            self.assertEqual(command[0], 'security')
            return '0 valid identities found' if '-v' in command else fingerprint + ' "Local Signing"'
        stderr = io.StringIO()
        with patch('sys.argv', ['package.py', '--sign-identity', fingerprint,
                               '--notary-profile', 'synthetic-no-auth']), \
             patch('subprocess.check_output', side_effect=identities), \
             patch('subprocess.run') as process, contextlib.redirect_stderr(stderr):
            with self.assertRaises(SystemExit) as exit:
                runpy.run_path(str(ROOT/'scripts/package.py'), run_name='__main__')
            self.assertEqual(exit.exception.code, 2)
            process.assert_not_called()
        self.assertIn('existing valid Developer ID Application identity required', stderr.getvalue())

    def testAdhocCannotBeImplicitDistribution(self):
        run = subprocess.run(['python3', str(ROOT/'scripts/package.py'), '--adhoc'],
                             capture_output=True, text=True, timeout=10)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn('--adhoc requires --development', run.stderr)

    def testUpdatePackagerRejectsBeforeArchiveAndKeyLookup(self):
        spec = importlib.util.spec_from_file_location('package_update', ROOT/'scripts/package-update.py')
        updater = importlib.util.module_from_spec(spec); spec.loader.exec_module(updater)
        with patch('sys.argv', ['package-update.py', '/Applications/AInauten Voice.app',
                               '--output', '/synthetic-must-not-be-created', '--bootstrap',
                               '--release-notes', '/synthetic-no-read.md']), \
             patch.object(security, 'verify_distribution_app', side_effect=ValueError('invalid signature')) as gate:
            with self.assertRaises(ValueError):
                updater.main()
            gate.assert_called_once_with(Path('/Applications/AInauten Voice.app'))
        self.assertFalse(Path('/synthetic-must-not-be-created').exists())

    def testActualNestedCodeEnumerationAndTicketAreMandatory(self):
        with tempfile.TemporaryDirectory(prefix='voice-distribution-fixture-') as temp:
            app = Path(temp)/'AInauten Voice.app'; (app/'Contents/Frameworks').mkdir(parents=True)
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.mediapublishing.VoiceWispr'}))
            code = app/'Contents/Frameworks/fixture.dylib'; code.write_bytes(b'\xcf\xfa\xed\xfe')
            with patch.object(security, 'run'), \
                 patch.object(security, 'verify_code', return_value='ABCDE12345') as verify, \
                 patch.object(security, 'verify_ticket') as ticket:
                result = security.verify_distribution_app(app)
                self.assertEqual(verify.call_args_list[0].args, (app,))
                self.assertEqual(verify.call_args_list[1].args, (code, 'ABCDE12345'))
                ticket.assert_called_once_with(app)
                self.assertEqual(result['codeObjects'], 1)
                self.assertTrue(result['notarized'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
