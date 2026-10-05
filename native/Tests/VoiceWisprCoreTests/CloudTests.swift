import XCTest
import Foundation
@testable import VoiceWisprCore

final class CloudTests: XCTestCase {
    final class FixtureProtocol: URLProtocol {
        static var status = 200
        static var body = ""
        static var delay = false
        static var redirect = false
        static var sawRequest: URLRequest?
        static var requestCount = 0
        static var started = false
        static var requestBody = Data()
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.sawRequest = request
            Self.requestCount += 1; Self.started = true
            if let body = request.httpBody { Self.requestBody = body }
            else if let stream = request.httpBodyStream { stream.open(); defer { stream.close() }; var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096); while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }; Self.requestBody = data }
            if Self.delay { Thread.sleep(forTimeInterval: 0.5) }
            if Self.redirect {
                let redirected = URLRequest(url: URL(string: "https://second-recipient.invalid/v1/chat/completions")!)
                let redirectResponse = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": redirected.url!.absoluteString])!
                client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: redirectResponse)
                client?.urlProtocolDidFinishLoading(self); return
            }
            let data = Data(Self.body.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(data.count)"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func formatter(body: String = "") -> CloudFormatter {
        Self.FixtureProtocol.body = body.isEmpty ? #"{"choices":[{"message":{"content":"Hallo, das ist ein Test."}}]}"# : body
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [Self.FixtureProtocol.self]
        return CloudFormatter(endpoint: URL(string: "http://127.0.0.1/v1")!, model: "test", key: "local-test-key", sessionConfiguration: config)
    }

    func testSuccessfulResponseIsTextOnlyAndPreservesMeaning() async throws {
        Self.FixtureProtocol.status = 200; Self.FixtureProtocol.redirect = false; Self.FixtureProtocol.requestCount = 0; Self.FixtureProtocol.started = false
        let value = try await formatter().format("Hallo, das ist ein Test.", style: .cleaned, context: "Kontext", vocabulary: ["AInauten"])
        XCTAssertEqual(value, "Hallo, das ist ein Test.")
        _ = try XCTUnwrap(Self.FixtureProtocol.sawRequest); let body = try XCTUnwrap(try? JSONSerialization.jsonObject(with: Self.FixtureProtocol.requestBody) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "test"); XCTAssertEqual(body["temperature"] as? Double, 0)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]]); XCTAssertEqual(messages.count, 2)
        let user = try XCTUnwrap(messages.last?["content"] as? String); XCTAssertTrue(user.contains("<CURRENT>Hallo, das ist ein Test.</CURRENT>")); XCTAssertFalse(user.localizedCaseInsensitiveContains("audio")); XCTAssertFalse(user.localizedCaseInsensitiveContains("focused-field"))
    }

    func testStatus401And429FailWithoutFallback() async throws {
        for status in [401, 429] {
            Self.FixtureProtocol.status = status
            do { _ = try await formatter().format("Test", style: .chat, context: "", vocabulary: []); XCTFail("expected \(status)") } catch { XCTAssertTrue(String(describing: error).contains("fehlgeschlagen")) }
        }
    }

    func testRedirectIsRefusedAndNeverReachesSecondDestination() async throws {
        Self.FixtureProtocol.status = 200; Self.FixtureProtocol.redirect = true
        Self.FixtureProtocol.requestCount = 0
        do { _ = try await formatter().format("Test", style: .email, context: "", vocabulary: []); XCTFail("expected redirect failure") } catch {}
        XCTAssertEqual(Self.FixtureProtocol.requestCount, 1)
    }

    func testOversizedResponseIsRejected() async throws {
        Self.FixtureProtocol.redirect = false; Self.FixtureProtocol.status = 200
        let oversized = String(repeating: "x", count: 1_048_577)
        do { _ = try await formatter(body: oversized).format("Test", style: .chat, context: "", vocabulary: []); XCTFail("expected size failure") } catch { XCTAssertTrue(String(describing: error).contains("zu groß")) }
    }

    func testCancellationStopsCloudRequest() async throws {
        Self.FixtureProtocol.redirect = false; Self.FixtureProtocol.status = 200; Self.FixtureProtocol.delay = true; Self.FixtureProtocol.started = false
        defer { Self.FixtureProtocol.delay = false }
        let task = Task { try await self.formatter().format("Test", style: .chat, context: "", vocabulary: []) }
        for _ in 0..<50 where !Self.FixtureProtocol.started { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(Self.FixtureProtocol.started); task.cancel()
        do { _ = try await task.value; XCTFail("expected cancellation") } catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
    }

    func testSemanticGuardRejectsAddedFact() async throws {
        Self.FixtureProtocol.redirect = false; Self.FixtureProtocol.status = 200
        let body = #"{"choices":[{"message":{"content":"Hallo, das ist ein Test. Zusätzlich findet morgen ein Meeting statt."}}]}"#
        do { _ = try await formatter(body: body).format("Hallo, das ist ein Test.", style: .cleaned, context: "", vocabulary: []); XCTFail("expected semantic guard") } catch {}
    }
}
