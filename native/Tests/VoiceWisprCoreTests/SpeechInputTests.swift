import XCTest
@testable import VoiceWisprCore

final class SpeechInputTests: XCTestCase {
    func testMinimumAudioBoundaryMatchesPinnedRecognizer() throws {
        for count in [0, 1, 4799] {
            do { try SpeechRuntime.validateInput(count); XCTFail("Short audio must fail") }
            catch SpeechInputError.tooShort {}
        }
        try SpeechRuntime.validateInput(4800)
        try SpeechRuntime.validateInput(4801)
    }
    func testAudioFailureHasGermanActionWithoutRawSDKDetails() {
        let message = SpeechInputError.tooShort.localizedDescription
        XCTAssertTrue(message.contains("Audioabschnitt war zu kurz"))
        XCTAssertTrue(message.contains("Tastenkürzel"))
        XCTAssertFalse(message.contains("16kHz"))
        XCTAssertFalse(message.contains("Invalid audio"))
    }
}
