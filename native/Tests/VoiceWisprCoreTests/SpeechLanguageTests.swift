import XCTest
@testable import VoiceWisprCore

final class SpeechLanguageTests: XCTestCase {
    func testGermanSelectionRejectsEnglishAndUnselectedScripts() {
        let policy = SpeechLanguagePolicy(["de-DE"])
        XCTAssertTrue(policy.needsRecovery("Please do not send the report to the customer today. We are waiting for approval next Monday before making any changes."))
        XCTAssertTrue(policy.needsRecovery("Это текст на русском языке."))
        XCTAssertTrue(policy.needsRecovery("Цей текст українською мовою."))
        XCTAssertFalse(policy.needsRecovery("Diesen Bericht bitte heute noch nicht an den Kunden schicken. Wir warten auf die Freigabe."))
    }
    func testNamesShortTermsAndGermanWithEnglishVocabularyRemainAllowed() {
        let policy = SpeechLanguagePolicy(["de"])
        for text in ["AInauten", "Open Source", "Kevin Kashikar", "Okay.", "123,45", "https://voice.ainauten.com/download", "Schreibe den Pull Request für die Open Source App und prüfe das User Interface."] {
            XCTAssertFalse(policy.needsRecovery(text))
        }
    }
    func testExplicitMultipleLanguagesAndRegionalCodes() {
        XCTAssertFalse(SpeechLanguagePolicy(["de", "en-US"]).needsRecovery("Please do not send the report to the customer today."))
        XCTAssertFalse(SpeechLanguagePolicy(["de", "ru"]).needsRecovery("Это текст на русском языке."))
        XCTAssertTrue(SpeechLanguagePolicy(["de", "en"]).needsRecovery("Это текст на русском языке."))
        XCTAssertFalse(SpeechLanguagePolicy([]).needsRecovery("Это текст на русском языке."))
        XCTAssertEqual(SpeechLanguagePolicy(["de-DE", "de", "en"]).languages, ["de", "en"])
    }
    func testFallbackReadbackPreservesWordsTimesAndSession() throws {
        let id = UUID()
        let json = Data(#"{"text":" Hallo AInauten.","words":[{"text":"Hallo","start":0.2,"end":0.6},{"text":"AInauten.","start":0.6,"end":1.2}]}"#.utf8)
        let result = try WhisperLanguageFallback.decode(json, sessionID: id, index: 3, offset: 14, duration: 2)
        XCTAssertEqual(result.sessionID, id); XCTAssertEqual(result.index, 3)
        XCTAssertEqual(result.text, "Hallo AInauten.")
        XCTAssertEqual(result.words.first?.start, 14.2); XCTAssertEqual(result.words.last?.end, 15.2)
    }
    func testFallbackInvalidWordsOrTimingsCannotBecomeInsertableText() {
        for json in [#"{"text":"Hallo","words":[]}"#, #"{"text":"Hallo","words":[{"text":"Goodbye","start":0,"end":1}]}"#, #"{"text":"Hallo","words":[{"text":"Hallo","start":0,"end":30}]}"#] {
            XCTAssertThrowsError(try WhisperLanguageFallback.decode(Data(json.utf8), sessionID: UUID(), index: 0, offset: 0, duration: 2))
        }
    }
    func testPipelineFreezesSelectedLanguagesPerSession() async throws {
        let speech = LanguageSpy()
        let pipeline = ProcessingPipeline(speech: speech, formatter: IdentityFormatter())
        let id = UUID()
        try await pipeline.start(sessionID: id, style: .original, languages: ["de"])
        let captured = await speech.configuration
        XCTAssertEqual(captured?.0, id); XCTAssertEqual(captured?.1, ["de"])
        await pipeline.cancel()
        let second = UUID()
        try await pipeline.start(sessionID: second, style: .original, languages: ["en"])
        let changed = await speech.configuration
        XCTAssertEqual(changed?.0, second); XCTAssertEqual(changed?.1, ["en"])
        await pipeline.cancel()
    }
    func testWrongLanguageUsesAudioRecoveryAndNeverTranslatesCandidateText() async throws {
        let id = UUID(), policy = SpeechLanguagePolicy(["de"])
        let english = TranscriptSegment(sessionID: id, index: 2, text: "Please do not send the report to the customer today.")
        let recovery = LanguageRecoverySpy(id: id)
        let result = try await policy.resolve(english) { language in await recovery.recover(language) }
        XCTAssertEqual(result.text, "Bitte den Bericht heute nicht versenden.")
        let language = await recovery.language
        XCTAssertEqual(language, "de")
        do {
            _ = try await policy.resolve(english) { _ in english }
            XCTFail("Wrong language must not become a successful dictation")
        } catch { XCTAssertTrue(error is SpeechLanguageError) }
    }
    func testAllowedTextDoesNotStartAnotherModelAndStaleRecoveryIsRejected() async throws {
        let id = UUID(), policy = SpeechLanguagePolicy(["de"])
        let german = TranscriptSegment(sessionID: id, index: 0, text: "Bitte den Bericht heute nicht versenden.")
        let result = try await policy.resolve(german) { _ in XCTFail("Recovery must not run"); return german }
        XCTAssertEqual(result.text, german.text)
        let english = TranscriptSegment(sessionID: id, index: 0, text: "Please do not send the report to the customer today.")
        do {
            _ = try await policy.resolve(english) { _ in .init(sessionID: UUID(), index: 0, text: german.text) }
            XCTFail("A different recording must not be inserted")
        } catch { XCTAssertTrue(error is SpeechLanguageError) }
    }
    func testGermanEnglishSelectionVerifiesEnglishAcousticallyButStillAllowsEnglish() async throws {
        let policy = SpeechLanguagePolicy(["de", "en"])
        let english = TranscriptSegment(sessionID: UUID(), index: 0, text: "Please do not send the report to the customer today.")
        XCTAssertTrue(policy.needsVerification(english.text))
        XCTAssertFalse(policy.needsRecovery(english.text))
        let result = try await policy.resolve(english) { language in
            XCTAssertEqual(language, "auto")
            return english
        }
        XCTAssertEqual(result.text, english.text)
        XCTAssertFalse(SpeechLanguagePolicy(["en"]).needsVerification(english.text))
    }
}
private actor LanguageRecoverySpy {
    let id: UUID
    var language: String?
    init(id: UUID) { self.id = id }
    func recover(_ language: String) -> TranscriptSegment {
        self.language = language
        return .init(sessionID: id, index: 2, text: "Bitte den Bericht heute nicht versenden.")
    }
}
private actor LanguageSpy: SpeechTranscribing, SpeechLanguageConfiguring {
    var configuration: (UUID, [String])?
    func configureLanguages(_ languages: [String], sessionID: UUID) { configuration = (sessionID, languages) }
    func prepare() async throws {}
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment { .init(sessionID: sessionID, index: index, text: "") }
}
private struct IdentityFormatter: TextFormatting {
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String { text }
}
