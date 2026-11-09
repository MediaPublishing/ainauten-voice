import XCTest
import AppKit
@testable import VoiceWisprCore

@MainActor final class ClipboardConsumptionTests: XCTestCase {
    func testNoReadKeepsThePayloadForFiveSeconds() {
        let consumption = ClipboardConsumption(text: "Testdiktat")
        XCTAssertEqual(consumption.restoreAt(submittedAt: 100), 105)
    }
    func testEarlyAndLateReadersGetAMinimumHoldAndQuietPeriod() {
        let consumption = ClipboardConsumption(text: "Testdiktat")
        consumption.recordRead(at: 100.1)
        XCTAssertEqual(consumption.restoreAt(submittedAt: 100), 101)
        consumption.recordRead(at: 101.8)
        XCTAssertEqual(consumption.restoreAt(submittedAt: 100), 102.3)
        consumption.recordRead(at: 101.2)
        XCTAssertEqual(consumption.restoreAt(submittedAt: 100), 102.3)
        consumption.recordRead(at: 104.9)
        XCTAssertEqual(consumption.restoreAt(submittedAt: 100), 105)
    }
    func testLazyReadPreservesNonceMarkersAndEverySavedRepresentation() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let original = NSPasteboardItem()
        original.setString("Vorher", forType: .string)
        original.setData(Data("<b>Vorher</b>".utf8), forType: .html)
        XCTAssertTrue(board.writeObjects([original]))
        let snapshot = try XCTUnwrap(ClipboardSnapshot.capture(board))
        let nonce = UUID(), consumption = ClipboardConsumption(text: "Testdiktat 👋")
        let item = try XCTUnwrap(ClipboardSnapshot.ownedItem("Testdiktat 👋", nonce: nonce, provider: consumption))
        board.prepareForNewContents(with: .currentHostOnly)
        XCTAssertTrue(board.writeObjects([item]))
        let ownership = ClipboardOwnership(nonce: nonce, changeCount: board.changeCount)
        XCTAssertNil(consumption.lastReadAt)
        XCTAssertEqual(board.string(forType: .string), "Testdiktat 👋")
        XCTAssertTrue(consumption.lastReadAt != nil)
        XCTAssertEqual(board.string(forType: ClipboardSnapshot.nonceType), nonce.uuidString)
        for type in TransientPasteboard.types { XCTAssertTrue(board.types?.contains(type) == true) }
        XCTAssertTrue(snapshot.restore(board, ownership: ownership))
        XCTAssertEqual(board.string(forType: .string), "Vorher")
        XCTAssertEqual(board.data(forType: .html), Data("<b>Vorher</b>".utf8))
    }
    func testANewerCopyWinsEvenWhenItsTextMatchesTheTemporaryDictation() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("Vorher", forType: .string)
        let snapshot = try XCTUnwrap(ClipboardSnapshot.capture(board))
        let nonce = UUID(), consumption = ClipboardConsumption(text: "Testdiktat")
        let item = try XCTUnwrap(ClipboardSnapshot.ownedItem("Testdiktat", nonce: nonce, provider: consumption))
        board.clearContents(); XCTAssertTrue(board.writeObjects([item]))
        let ownership = ClipboardOwnership(nonce: nonce, changeCount: board.changeCount)
        board.clearContents(); board.setString("Testdiktat", forType: .string)
        XCTAssertFalse(snapshot.restore(board, ownership: ownership))
        XCTAssertEqual(board.string(forType: .string), "Testdiktat")
    }
}
