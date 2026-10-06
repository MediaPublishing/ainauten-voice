import XCTest
import AppKit
@testable import VoiceWisprCore

/// Real AppKit lazy materialization, always confined to a uniquely named board.
private final class ClipboardLazyProvider: NSObject, NSPasteboardItemDataProvider {
    var requests = 0
    let provide: (NSPasteboard?, NSPasteboardItem, NSPasteboard.PasteboardType) -> Void
    init(provide: @escaping (NSPasteboard?, NSPasteboardItem, NSPasteboard.PasteboardType) -> Void) {
        self.provide = provide
    }
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        requests += 1
        provide(pasteboard, item, type)
    }
}

@MainActor final class ClipboardTests: XCTestCase {
    func testRestorationReadbackRequiresEveryOriginalRepresentationByteForByte() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let original = NSPasteboardItem()
        let text = Data("Grüße 👋".utf8), html = Data("<b>Grüße 👋</b>".utf8)
        original.setData(text, forType: .string); original.setData(html, forType: .html)
        XCTAssertTrue(board.writeObjects([original]))
        let saved = try XCTUnwrap(ClipboardSnapshot.capture(board))
        XCTAssertTrue(saved.verifiesRestoration(board, writtenAt: board.changeCount))

        let missing = NSPasteboardItem(); missing.setData(text, forType: .string)
        board.clearContents(); XCTAssertTrue(board.writeObjects([missing]))
        let missingAt = board.changeCount
        XCTAssertFalse(saved.verifiesRestoration(board, writtenAt: missingAt))
        XCTAssertEqual(board.changeCount, missingAt)

        let changed = NSPasteboardItem()
        changed.setData(text, forType: .string); changed.setData(Data("<i>Grüße 👋</i>".utf8), forType: .html)
        board.clearContents(); XCTAssertTrue(board.writeObjects([changed]))
        let changedAt = board.changeCount
        XCTAssertFalse(saved.verifiesRestoration(board, writtenAt: changedAt))
        XCTAssertEqual(board.changeCount, changedAt)
    }
    func testRestorationReadbackRequiresOriginalItemOrderAndCount() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        func item(_ text: String) -> NSPasteboardItem {
            let value = NSPasteboardItem(); value.setString(text, forType: .string); return value
        }
        XCTAssertTrue(board.writeObjects([item("Erstes"), item("Zweites")]))
        let saved = try XCTUnwrap(ClipboardSnapshot.capture(board))
        for values in [["Zweites", "Erstes"], ["Erstes"], ["Erstes", "Zweites", "Drittes"]] {
            board.clearContents(); XCTAssertTrue(board.writeObjects(values.map(item)))
            let count = board.changeCount
            XCTAssertFalse(saved.verifiesRestoration(board, writtenAt: count))
            XCTAssertEqual(board.changeCount, count)
        }
    }
    func testRestorationReadbackRejectsANewerIdenticalCopy() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("Gleicher Text", forType: .string)
        let saved = try XCTUnwrap(ClipboardSnapshot.capture(board)), originalAt = board.changeCount
        board.clearContents(); board.setString("Gleicher Text", forType: .string)
        let newerAt = board.changeCount
        XCTAssertFalse(saved.verifiesRestoration(board, writtenAt: originalAt))
        XCTAssertEqual(board.changeCount, newerAt)
        XCTAssertEqual(board.string(forType: .string), "Gleicher Text")
    }
    func testRestorationReadbackAllowsAdditionalRepresentationsWithoutDroppingOriginalBytes() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let text = Data("Grüße 👋".utf8)
        let saved = ClipboardSnapshot(items: [[.string: text]], changeCount: board.changeCount)
        let actual = NSPasteboardItem()
        actual.setData(text, forType: .string)
        actual.setData(Data([0, 19, 250]), forType: .init("com.mediapublishing.clipboard-test.additional"))
        XCTAssertTrue(board.writeObjects([actual]))
        XCTAssertTrue(saved.verifiesRestoration(board, writtenAt: board.changeCount))
    }
    func testEmptyRestorationReadbackRequiresAnUnchangedEmptyBoard() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let empty = ClipboardSnapshot(items: [], changeCount: board.changeCount)
        XCTAssertTrue(empty.verifiesRestoration(board, writtenAt: board.changeCount))
        board.setString("Neue Nutzerkopie", forType: .string)
        XCTAssertFalse(empty.verifiesRestoration(board, writtenAt: board.changeCount))
        XCTAssertEqual(board.string(forType: .string), "Neue Nutzerkopie")
    }
    func testRestorationReadbackCannotConfirmAnUnreadablePromisedRepresentation() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("Original", forType: .string)
        let saved = try XCTUnwrap(ClipboardSnapshot.capture(board))
        let type = NSPasteboard.PasteboardType("com.mediapublishing.clipboard-test.unavailable")
        let provider = ClipboardLazyProvider { _, _, _ in }
        let actual = NSPasteboardItem(); actual.setString("Original", forType: .string)
        XCTAssertTrue(actual.setDataProvider(provider, forTypes: [type]))
        board.clearContents(); XCTAssertTrue(board.writeObjects([actual]))
        let count = board.changeCount
        XCTAssertFalse(saved.verifiesRestoration(board, writtenAt: count))
        XCTAssertGreaterThan(provider.requests, 0)
        XCTAssertEqual(board.changeCount, count)
    }
    func testExternalCopyDuringRestorationReadbackRemainsUntouched() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("Original", forType: .string)
        let saved = try XCTUnwrap(ClipboardSnapshot.capture(board))
        let type = NSPasteboard.PasteboardType("com.mediapublishing.clipboard-test.changing")
        var changedAt: Int?
        let provider = ClipboardLazyProvider { _, item, requested in
            item.setData(Data([1, 2, 3]), forType: requested)
            board.clearContents(); board.setString("Neuere Nutzerkopie", forType: .string)
            changedAt = board.changeCount
        }
        let actual = NSPasteboardItem(); actual.setString("Original", forType: .string)
        XCTAssertTrue(actual.setDataProvider(provider, forTypes: [type]))
        board.clearContents(); XCTAssertTrue(board.writeObjects([actual]))
        XCTAssertFalse(saved.verifiesRestoration(board, writtenAt: board.changeCount))
        XCTAssertGreaterThan(provider.requests, 0)
        XCTAssertEqual(board.changeCount, changedAt)
        XCTAssertEqual(board.string(forType: .string), "Neuere Nutzerkopie")
    }
    func testUnreadableLazyRepresentationPreventsCopyWithoutLosingOtherFormats() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let type = NSPasteboard.PasteboardType("com.mediapublishing.clipboard-test.unavailable")
        let provider = ClipboardLazyProvider { _, _, _ in /* Intentionally supplies no promised data. */ }
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setString("Original mit ungelesenem Zusatzformat", forType: .string))
        XCTAssertTrue(item.setDataProvider(provider, forTypes: [type]))
        XCTAssertTrue(board.writeObjects([item]))
        let count = board.changeCount, recovery = ClipboardRecovery(board: board)
        XCTAssertEqual(recovery.copy("Diktat"), .unavailable)
        XCTAssertGreaterThan(provider.requests, 0)
        XCTAssertEqual(board.changeCount, count)
        XCTAssertEqual(board.string(forType: .string), "Original mit ungelesenem Zusatzformat")
        XCTAssertTrue(try XCTUnwrap(board.pasteboardItems?.first).types.contains(type))
        XCTAssertFalse(recovery.canUndo)
    }
    func testNewCopyDuringLazyMaterializationIsPreserved() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let type = NSPasteboard.PasteboardType("com.mediapublishing.clipboard-test.changing")
        var changedAt: Int?
        let provider = ClipboardLazyProvider { _, item, requestedType in
            // Return valid bytes for the old item, but replace the board while
            // capture is in progress. A complete yet stale snapshot is unsafe.
            item.setData(Data([1, 2, 3]), forType: requestedType)
            board.clearContents()
            board.setString("Neuere Nutzerkopie", forType: .string)
            changedAt = board.changeCount
        }
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setDataProvider(provider, forTypes: [type]))
        XCTAssertTrue(board.writeObjects([item]))
        let recovery = ClipboardRecovery(board: board)
        XCTAssertEqual(recovery.copy("Diktat"), .unavailable)
        XCTAssertGreaterThan(provider.requests, 0)
        XCTAssertEqual(board.changeCount, changedAt)
        XCTAssertEqual(board.string(forType: .string), "Neuere Nutzerkopie")
        XCTAssertFalse(recovery.canUndo)
    }
    func testRepeatedCopyOfOwnedTextKeepsOriginalUndoSnapshot() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("Vorheriger Inhalt", forType: .string)
        let recovery = ClipboardRecovery(board: board)
        XCTAssertEqual(recovery.copy("Diktat"), .copied)
        let count = board.changeCount
        XCTAssertEqual(recovery.copy("Diktat"), .copied)
        XCTAssertEqual(recovery.copy("Diktat"), .copied)
        XCTAssertEqual(board.changeCount, count)
        XCTAssertEqual(recovery.undo(), .restored)
        XCTAssertEqual(board.string(forType: .string), "Vorheriger Inhalt")
    }
    func testAutomaticWritesAreTransientForClipboardManagersAndUndoRestoresOriginal() throws {
        XCTAssertEqual(TransientPasteboard.types.map(\.rawValue), ["org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"])
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("Vorheriger Inhalt", forType: .string)
        let recovery = ClipboardRecovery(board: board)
        XCTAssertEqual(recovery.copy("Diktat"), .copied)
        let written = try XCTUnwrap(board.pasteboardItems?.first)
        XCTAssertTrue(Set(TransientPasteboard.types).isSubset(of: Set(written.types)))
        // Capturing our own marked item must still work for a second copy or paste.
        XCTAssertEqual(recovery.copy("Zweites Diktat"), .copied)
        XCTAssertEqual(recovery.undo(), .restored); XCTAssertEqual(board.string(forType: .string), "Diktat")
        let paste = try XCTUnwrap(ClipboardSnapshot.ownedItem("Diktat", nonce: UUID()))
        XCTAssertTrue(Set(TransientPasteboard.types).isSubset(of: Set(paste.types)))
        XCTAssertEqual(paste.string(forType: .string), "Diktat")
        let original = NSPasteboard.withUniqueName(); defer { original.releaseGlobally() }
        original.setString("Nutzerkopie", forType: .string)
        let undo = ClipboardRecovery(board: original); XCTAssertEqual(undo.copy("Diktat"), .copied); XCTAssertEqual(undo.undo(), .restored)
        let restored = try XCTUnwrap(original.pasteboardItems?.first)
        XCTAssertTrue(Set(TransientPasteboard.types).isDisjoint(with: Set(restored.types)))
    }
    func testRecoveryCopyAndUndoRestoreEveryItemAndRepresentation() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let first = NSPasteboardItem(), second = NSPasteboardItem()
        let formats: [NSPasteboard.PasteboardType: Data] = [
            .string: Data("Grüße 👋".utf8), .html: Data("<b>Grüße</b>".utf8),
            .rtf: Data(#"{\rtf1\ansi original}"#.utf8), .png: Data([137, 80, 78, 71, 0, 1]),
            .init("public.custom-test"): Data([0, 19, 250])]
        for (type, data) in formats { first.setData(data, forType: type) }
        let file = Data("file:///tmp/voice-wispr-fixture.txt".utf8); second.setData(file, forType: .fileURL)
        XCTAssertTrue(board.writeObjects([first, second]))
        let recovery = ClipboardRecovery(board: board)
        XCTAssertEqual(recovery.copy("Vielen Dank für die Rückmeldung."), .copied)
        XCTAssertEqual(board.string(forType: .string), "Vielen Dank für die Rückmeldung.")
        XCTAssertTrue(recovery.canUndo)
        XCTAssertEqual(recovery.undo(), .restored)
        let items = try XCTUnwrap(board.pasteboardItems)
        XCTAssertEqual(items.count, 2)
        // macOS may synthesize an additional UTF-16 representation.
        XCTAssertTrue(Set(formats.keys).isSubset(of: Set(items[0].types)))
        XCTAssertNil(items[0].data(forType: ClipboardSnapshot.nonceType))
        for (type, data) in formats { XCTAssertEqual(items[0].data(forType: type), data) }
        XCTAssertEqual(items[1].data(forType: .fileURL), file)
        XCTAssertFalse(recovery.canUndo)
        XCTAssertEqual(recovery.undo(), .changed)
    }
    func testRecoveryUndoNeverOverwritesANewerUserCopyEvenWithIdenticalText() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("vorher", forType: .string)
        let recovery = ClipboardRecovery(board: board)
        XCTAssertEqual(recovery.copy("Diktat"), .copied)
        board.clearContents(); board.setString("Diktat", forType: .string)
        let count = board.changeCount
        XCTAssertFalse(recovery.canUndo)
        XCTAssertEqual(recovery.undo(), .changed)
        XCTAssertEqual(board.changeCount, count)
        XCTAssertEqual(board.string(forType: .string), "Diktat")
    }
    func testRecoveryUndoProtectsUserClearAndCopiedOwnershipMarker() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("vorher", forType: .string)
        let recovery = ClipboardRecovery(board: board)
        XCTAssertEqual(recovery.copy("Diktat"), .copied)
        let nonce = board.string(forType: ClipboardSnapshot.nonceType)!
        board.clearContents(); board.setString("neu", forType: .string); board.setString(nonce, forType: ClipboardSnapshot.nonceType)
        XCTAssertEqual(recovery.undo(), .changed)
        XCTAssertEqual(board.string(forType: .string), "neu")
        XCTAssertEqual(recovery.copy("noch ein Diktat"), .copied)
        let count = board.clearContents()
        XCTAssertEqual(recovery.undo(), .changed)
        XCTAssertEqual(board.changeCount, count)
        XCTAssertTrue((board.types ?? []).isEmpty)
    }
    func testRecoverySecondCopyUndoesOnlyMostRecentWriteAndEmptyBoardRestores() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let recovery = ClipboardRecovery(board: board)
        XCTAssertEqual(recovery.copy("Erstes Diktat"), .copied)
        XCTAssertEqual(recovery.copy("Zweites Diktat"), .copied)
        XCTAssertEqual(recovery.undo(), .restored)
        XCTAssertEqual(board.string(forType: .string), "Erstes Diktat")
        XCTAssertEqual(recovery.undo(), .changed)
        board.clearContents()
        XCTAssertEqual(recovery.copy("Neues Diktat"), .copied)
        XCTAssertEqual(recovery.undo(), .restored)
        XCTAssertTrue((board.types ?? []).isEmpty)
    }
    func testRecoveryCannotBackupLargeClipboardAndNeverWritesEmptyResult() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let original = Data(repeating: 7, count: 64 * 1024 * 1024 + 1)
        board.setData(original, forType: .png)
        let count = board.changeCount, recovery = ClipboardRecovery(board: board)
        XCTAssertEqual(recovery.copy("Diktat"), .unavailable)
        XCTAssertEqual(board.changeCount, count)
        XCTAssertEqual(board.data(forType: .png), original)
        XCTAssertFalse(recovery.canUndo)
        board.clearContents(); board.setString("Nutzertext", forType: .string)
        let emptyCount = board.changeCount
        XCTAssertEqual(recovery.copy(" \n\t"), .unavailable)
        XCTAssertEqual(board.changeCount, emptyCount)
        XCTAssertEqual(board.string(forType: .string), "Nutzertext")
    }
    func testMultipleItemsAndAllRepresentationsRestoreByteForByte() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let first = NSPasteboardItem()
        let text = Data("Grüße 👋".utf8), html = Data("<b>Grüße</b>".utf8), rtf = Data(#"{\rtf1\ansi hello}"#.utf8)
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1kAAAAASUVORK5CYII=")!
        first.setData(text, forType: .string); first.setData(html, forType: .html); first.setData(rtf, forType: .rtf); first.setData(image, forType: .png)
        let second = NSPasteboardItem(); let url = Data("file:///tmp/voice-wispr-fixture.txt".utf8)
        second.setData(url, forType: .fileURL)
        XCTAssertTrue(board.writeObjects([first, second]))
        let saved = try XCTUnwrap(ClipboardSnapshot.capture(board))
        let nonce = UUID(), owned = NSPasteboardItem(); owned.setString("dictation", forType: .string); owned.setString(nonce.uuidString, forType: ClipboardSnapshot.nonceType)
        board.clearContents(); XCTAssertTrue(board.writeObjects([owned]))
        saved.restore(board, ownership: ClipboardOwnership(nonce: nonce, changeCount: board.changeCount))
        let restored = try XCTUnwrap(board.pasteboardItems)
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[0].data(forType: .string), text); XCTAssertEqual(restored[0].data(forType: .html), html)
        XCTAssertEqual(restored[0].data(forType: .rtf), rtf); XCTAssertEqual(restored[0].data(forType: .png), image)
        XCTAssertEqual(restored[1].data(forType: .fileURL), url)
    }
    func testUserCopyWinsOverOldOwnershipOnRealPasteboard() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("before", forType: .string)
        let saved = try XCTUnwrap(ClipboardSnapshot.capture(board)), nonce = UUID()
        board.clearContents(); board.setString("dictation", forType: .string); board.setString(nonce.uuidString, forType: ClipboardSnapshot.nonceType)
        let ownership = ClipboardOwnership(nonce: nonce, changeCount: board.changeCount)
        board.clearContents(); board.setString("user copied", forType: .string)
        saved.restore(board, ownership: ownership)
        XCTAssertEqual(board.string(forType: .string), "user copied")
    }
    func testEmptyClipboardRestoresAndWriteFailureRestoresOnlyOwnedClear() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let empty = try XCTUnwrap(ClipboardSnapshot.capture(board)), nonce = UUID()
        board.setString("dictation", forType: .string); board.setString(nonce.uuidString, forType: ClipboardSnapshot.nonceType)
        empty.restore(board, ownership: ClipboardOwnership(nonce: nonce, changeCount: board.changeCount))
        XCTAssertTrue((board.types ?? []).isEmpty)
        board.setString("original", forType: .string)
        let saved = try XCTUnwrap(ClipboardSnapshot.capture(board))
        let clearedAt = board.clearContents()
        saved.restoreAfterFailedWrite(board, clearedAt: clearedAt, nonce: nonce)
        XCTAssertEqual(board.string(forType: .string), "original")
        let anotherClear = board.clearContents(); board.setString("new copy", forType: .string)
        saved.restoreAfterFailedWrite(board, clearedAt: anotherClear, nonce: nonce)
        XCTAssertEqual(board.string(forType: .string), "new copy")
    }
    func testOversizedClipboardIsUntouched() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let original = Data(repeating: 23, count: 64 * 1024 * 1024 + 1)
        board.setData(original, forType: .png)
        let count = board.changeCount
        XCTAssertNil(ClipboardSnapshot.capture(board))
        XCTAssertEqual(board.changeCount, count)
        XCTAssertEqual(board.data(forType: .png), original)
    }
}
