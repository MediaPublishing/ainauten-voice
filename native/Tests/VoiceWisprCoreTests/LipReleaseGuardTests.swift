import XCTest
import Foundation
@testable import VoiceWisprCore

final class LipReleaseGuardTests: XCTestCase {
    func testReleaseInstallerRejectsBothLanguagesBeforeFilesystemOrProgress() async {
        #if !DEBUG
        XCTAssertFalse(LipReadingRuntime.releaseAvailable)
        let installer = LipReadingInstaller()
        for language in LipReadingLanguage.allCases {
            let absent = FileManager.default.temporaryDirectory.appendingPathComponent("voice-lip-release-absent-" + UUID().uuidString)
            XCTAssertFalse(FileManager.default.fileExists(atPath: absent.path))
            do {
                try await installer.install(language: language, root: absent, resources: absent) { _ in
                    XCTFail("Disabled research installer reported progress")
                }
                XCTFail("Release installer accepted disabled research")
            } catch VoiceError.message(let message) {
                XCTAssertEqual(message, LipReadingRuntime.securityNotice)
            } catch { XCTFail("Installer did not reject at its release gate") }
            XCTAssertFalse(FileManager.default.fileExists(atPath: absent.path))
        }
        #endif
    }
    func testReleaseRuntimeRejectsBothLanguagesBeforePreparing() async {
        #if !DEBUG
        for language in LipReadingLanguage.allCases {
            let absent = FileManager.default.temporaryDirectory.appendingPathComponent("voice-lip-release-absent-" + UUID().uuidString)
            let runtime = LipReadingRuntime(root: absent, resources: absent)
            do {
                try await runtime.prepare(language)
                XCTFail("Release runtime accepted disabled research")
            } catch VoiceError.message(let message) {
                XCTAssertEqual(message, LipReadingRuntime.securityNotice)
            } catch { XCTFail("Runtime did not reject at its release gate") }
            XCTAssertFalse(FileManager.default.fileExists(atPath: absent.path))
        }
        #endif
    }
    func testReleaseRuntimeRejectsInferenceAtItsReleaseGate() async {
        #if !DEBUG
        let absent = FileManager.default.temporaryDirectory.appendingPathComponent("voice-lip-release-absent-" + UUID().uuidString)
        let runtime = LipReadingRuntime(root: absent, resources: absent)
        do {
            _ = try await runtime.transcribe([], session: UUID())
            XCTFail("Release runtime accepted disabled inference")
        } catch VoiceError.message(let message) {
            XCTAssertEqual(message, LipReadingRuntime.securityNotice)
        } catch { XCTFail("Inference did not reject at its release gate") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: absent.path))
        #endif
    }
}
