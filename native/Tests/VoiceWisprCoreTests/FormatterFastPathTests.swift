import XCTest
import Foundation
@testable import VoiceWisprCore

final class FormatterFastPathTests: XCTestCase {
    func testInternalAllCapsFunctionWordsDoNotBypassOptimization() {
        XCTAssertTrue(LocalFormatter.needsModel("Der Text wurde MIT dem Team abgestimmt.", style: .cleaned))
        XCTAssertTrue(LocalFormatter.needsModel("Das ist wichtig, weil ES den Ablauf vereinfacht.", style: .cleaned))
        XCTAssertTrue(LocalFormatter.needsModel("Das kannst DU direkt installieren.", style: .chat))
        XCTAssertTrue(LocalFormatter.needsModel("Ich glaube, DASS die App heute startet.", style: .cleaned))
    }
    func testInstitutionAcronymAndUnrelatedAllCapsKeepFastPath() {
        XCTAssertFalse(LocalFormatter.needsModel("Wir arbeiten mit der NASA und dem MIT.", style: .cleaned))
        XCTAssertFalse(LocalFormatter.needsModel("Forschung am MIT hilft dem Team.", style: .cleaned))
        XCTAssertFalse(LocalFormatter.needsModel("This uses the CPU and API.", style: .chat))
        XCTAssertFalse(LocalFormatter.needsModel("Die Antwort lautet „MIT“.", style: .cleaned))
    }
    func testOriginalAllCapsRemainUntouched() {
        XCTAssertFalse(LocalFormatter.needsModel("Der Text wurde MIT dem Team abgestimmt.", style: .original))
        XCTAssertFalse(LocalFormatter.needsModel("Das kannst DU direkt installieren.", style: .original))
    }
    func testUnexpectedInternalFunctionWordCapitalsRequireOptimization() {
        XCTAssertTrue(LocalFormatter.needsModel("Ich habe festgestellt, dass Einige Worte im Text, insbesondere kurze Worte, groß geschrieben werden statt Klein.", style: .cleaned))
        XCTAssertTrue(LocalFormatter.needsModel("In diesem Beispiel hier, Das ich angesprochen habe, siehst Du, Dass einige und Klein großgeschrieben wurden, fälschlicherweise.", style: .cleaned))
        XCTAssertTrue(LocalFormatter.needsModel("Ich spreche Mit dem Team.", style: .chat))
    }
    func testSentenceStartsAndNormalGermanNounsKeepFastPath() {
        XCTAssertFalse(LocalFormatter.needsModel("Einige Worte bleiben erhalten.", style: .cleaned))
        XCTAssertFalse(LocalFormatter.needsModel("Mit Reto arbeitet Frau Klein am MIT mit OpenAI.", style: .cleaned))
    }
    func testPauseInducedFragmentGetsOptimizationWithoutCasingErrors() {
        XCTAssertTrue(LocalFormatter.needsModel("Natürlich gibt es auch jede Menge. Open Source Apps, die du direkt installieren kannst.", style: .cleaned))
        XCTAssertTrue(LocalFormatter.needsModel("Natürlich gibt Es auch jede Menge. Open Source Apps, die Du Direkt installieren kannst.", style: .cleaned))
    }
    func testSeveralApparentSentencesAreNotAssumedGrammaticallyComplete() {
        XCTAssertTrue(LocalFormatter.needsModel("Das passt. Einige Worte bleiben erhalten.", style: .cleaned))
        XCTAssertTrue(LocalFormatter.needsModel("Natürlich gibt es jede Menge Apps. Du kannst sie direkt installieren.", style: .chat))
    }
    func testGermanAdverbsAndVerbsUseContextSensitiveOptimization() {
        XCTAssertTrue(LocalFormatter.needsModel("Diese Apps kannst du Direkt installieren.", style: .cleaned))
        XCTAssertTrue(LocalFormatter.needsModel("Diese Apps kannst du Einfach installieren.", style: .chat))
        XCTAssertTrue(LocalFormatter.needsModel("Die App Startet automatisch.", style: .cleaned))
        XCTAssertTrue(LocalFormatter.needsModel("Das kannst du Schnell erledigen.", style: .cleaned))
    }
    func testCorrectNounsAndForeignNamesStillKeepFastPath() {
        XCTAssertFalse(LocalFormatter.needsModel("Natürlich gibt es auch jede Menge Open Source Apps, die du direkt installieren kannst.", style: .cleaned))
        XCTAssertFalse(LocalFormatter.needsModel("Ich treffe Reto am Freitag in Berlin.", style: .chat))
        XCTAssertFalse(LocalFormatter.needsModel("Das Installieren funktioniert im Hintergrund.", style: .cleaned))
    }
    func testOriginalKeepsReportedTextIncludingPunctuation() {
        XCTAssertFalse(LocalFormatter.needsModel("Natürlich gibt Es auch jede Menge. Open Source Apps, die Du Direkt installieren kannst.", style: .original))
    }
    func testColonAndQuotationStartsAreNotTreatedAsCaseErrors() {
        XCTAssertFalse(LocalFormatter.needsModel("Mein Hinweis: Das passt.", style: .cleaned))
        XCTAssertFalse(LocalFormatter.needsModel("Er sagt: „Das passt.“", style: .cleaned))
    }
    func testShortCompleteSentenceSkipsModel() {
        XCTAssertFalse(LocalFormatter.needsModel("Dies ist ein kurzer Test der Spracherkennung.", style: .cleaned))
        XCTAssertFalse(LocalFormatter.needsModel("Can you send me the file by 5 pm?", style: .chat))
    }
    func testFillersStructureAndEmailKeepModel() {
        XCTAssertTrue(LocalFormatter.needsModel("Also äh ich komme morgen.", style: .cleaned))
        XCTAssertTrue(LocalFormatter.needsModel("dies ist klein geschrieben.", style: .cleaned))
        XCTAssertTrue(LocalFormatter.needsModel("Ohne Satzzeichen am Ende", style: .cleaned))
        XCTAssertTrue(LocalFormatter.needsModel("Erste Zeile.\nZweite Zeile.", style: .cleaned))
        XCTAssertTrue(LocalFormatter.needsModel("Danke für die Unterlagen.", style: .email))
        XCTAssertTrue(LocalFormatter.needsModel(String(repeating: "Wort ", count: 30) + "Ende.", style: .cleaned))
        XCTAssertFalse(LocalFormatter.needsModel("Bleibt so.", style: .original))
    }
    func testSkippedTextPassesTheSameValidation() throws {
        let text = "Bitte prüfe die Zahlen bis Freitag nicht vorher."
        XCTAssertEqual(try LocalFormatter.validate(text, original: text, vocabulary: []), text)
    }
}
