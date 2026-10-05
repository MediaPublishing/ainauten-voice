# AInauten Voice Agent Notes

Current product: native SwiftUI/AppKit app in native/. The Python/Swift files at repository root are the earlier LocalWhisper prototype; see docs/legacy/LocalWhisper-README.md.

## Compatibility

Keep bundle ID com.mediapublishing.VoiceWispr, module/executable VoiceWispr, Application Support/Voice Wispr and existing Keychain services stable. Visible product name is AInauten Voice. Preserve user settings, dictionary, history and permissions.

## Work

Read native/docs/implementation-status.md. Before commits or installation, pull normally and inspect the working tree. Never stage foreign changes. Tests: python3 native/scripts/portable-checks.py; packaging: python3 native/scripts/package.py. Site: site/, static and self-contained.

## Privacy

Never publish private transcripts, user history, dictionaries, audio, model files, secrets, local signing material, .local/, generated app bundles or receipt dumps in source control. Screenshots use the isolated DEBUG preview with example data, explicitly labelled. Production data access only for in-scope metadata verification with backup. No cloud audio, no unrequested providers, no security bypass.
