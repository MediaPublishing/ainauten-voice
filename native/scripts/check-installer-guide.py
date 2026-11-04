#!/usr/bin/env python3
"""Offline installer guidance must match the actual distribution admission gate."""
import pathlib
import plistlib
import tempfile
import unittest
from unittest.mock import patch

import package_dmg


class InstallerGuideTests(unittest.TestCase):
    def test_legacy_beta_keeps_offline_warning_and_images(self):
        with tempfile.TemporaryDirectory() as directory:
            out = pathlib.Path(directory)
            package_dmg.write_offline_guide(out)
            html = (out / '00 - ZUERST LESEN.html').read_text()
            self.assertIn('Die Beta ist noch nicht Apple-notarisiert.', html)
            self.assertIn('data:image/png;base64,', html)
            self.assertNotIn('src="installation-images/', html)
            self.assertEqual((out / '00 - ZUERST LESEN.txt').read_text(),
                             (package_dmg.GUIDE / 'installation.txt').read_text())

    def test_notarized_guide_has_normal_start_without_bypass_steps(self):
        with tempfile.TemporaryDirectory() as directory:
            out = pathlib.Path(directory)
            package_dmg.write_offline_guide(out, notarized=True)
            html = (out / '00 - ZUERST LESEN.html').read_text()
            text = (out / '00 - ZUERST LESEN.txt').read_text()
            self.assertIn('Von Apple notarisiert', html)
            self.assertIn('Apple notarized', html)
            self.assertIn('VON APPLE NOTARISIERT', text)
            self.assertIn('AUTOMATISCHE UPDATES', text)
            self.assertIn('Datenschutz', html)
            for forbidden in ['Die Beta ist noch nicht Apple-notarisiert',
                              'class="steps"', 'data:image/png', '„Dennoch öffnen“ fehlt?']:
                self.assertNotIn(forbidden, html)
            self.assertNotIn('ersten Start einzeln erlauben', text)
            self.assertNotIn('Klicke in der Warnung', text)

    def test_apple_marker_alone_cannot_create_notarized_installer(self):
        with tempfile.TemporaryDirectory() as directory:
            out = pathlib.Path(directory)
            app = out / 'AInauten Voice.app'
            (app / 'Contents').mkdir(parents=True)
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier': 'com.mediapublishing.VoiceWispr',
                'CFBundleShortVersionString': '0.1.20',
                'AInautenDistributionMode': 'apple-developer-id',
            }))
            with patch('distribution_security.verify_distribution_app',
                       side_effect=ValueError('missing Apple ticket')) as gate, \
                    patch('package_dmg.verify_runtime') as runtime:
                with self.assertRaisesRegex(ValueError, 'missing Apple ticket'):
                    package_dmg.create_dmg(app, out / 'installer')
                gate.assert_called_once_with(app.resolve())
                runtime.assert_not_called()
                self.assertFalse((out / 'installer').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
