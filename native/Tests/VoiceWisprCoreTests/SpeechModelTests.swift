import XCTest
import Foundation
@testable import VoiceWisprCore

final class SpeechModelTests: XCTestCase {
    func testUnconfiguredProfilesUseUltraAndExplicitModelChoicesSurviveReload() throws {
        var settings = Settings()
        XCTAssertEqual(settings.selectedSpeechModel, .parakeetUltra)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        json.removeValue(forKey: "speechModel")
        let legacy = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.selectedSpeechModel, .parakeetUltra)
        settings.speechModel = .parakeetV3
        let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.selectedSpeechModel, .parakeetV3)
        XCTAssertEqual(restored.languages, ["de", "en"])
        json["speechModel"] = "unknown-model"
        XCTAssertThrowsError(try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: json)))
    }
    func testRuntimeConfigurationUsesTheSelectedModelAndAnIndependentDirectory() {
        let v3 = SpeechRuntimeConfiguration()
        let ultra = SpeechRuntimeConfiguration(model: .parakeetUltra)
        XCTAssertEqual(v3.model, .parakeetV3)
        XCTAssertEqual(v3.modelDirectory, ModelPaths.speech)
        XCTAssertEqual(ultra.model, .parakeetUltra)
        XCTAssertEqual(ultra.modelDirectory.lastPathComponent, "parakeet-ultra")
        XCTAssertTrue(ultra.modelDirectory != v3.modelDirectory)
        XCTAssertTrue(ultra.model.asrVersion == .ultra)
        XCTAssertEqual(SpeechRuntime(configuration: ultra).model, .parakeetUltra)
        let custom = URL(fileURLWithPath: "/tmp/explicit-ultra-fixture")
        XCTAssertEqual(SpeechRuntimeConfiguration(modelDirectory: custom, model: .parakeetUltra).modelDirectory, custom)
        XCTAssertFalse(ultra.dualDecodeArbitration)
    }
    func testPinnedUltraFilesNeverOverwriteV3OrEnterItsDownloadGroup() throws {
        let manifest = try ModelManifest.bundled()
        let ultra = manifest.files.filter { $0.group == SpeechModel.parakeetUltra.group }
        let v3 = manifest.files.filter { $0.group == SpeechModel.parakeetV3.group }
        XCTAssertEqual(ultra.count, 18)
        XCTAssertEqual(ultra.reduce(Int64(0)) { $0 + $1.size }, 632_162_964)
        XCTAssertTrue(ultra.allSatisfy { $0.path.hasPrefix("parakeet-ultra/") && $0.sha256.count == 64 && $0.url.scheme == "https"
            && $0.url.host == "huggingface.co" && $0.url.path.contains("/95eaa59a39d4394f047a4dc5cce480388a60d1b6/") })
        XCTAssertTrue(Set(ultra.map(\.path)).isDisjoint(with: Set(v3.map(\.path))))
        XCTAssertEqual(SpeechModel.parakeetV3.downloadGroups, ["parakeet", "vad", "qwen"])
        XCTAssertEqual(SpeechModel.parakeetUltra.downloadGroups, ["parakeet-ultra", "vad", "qwen"])
    }
}
