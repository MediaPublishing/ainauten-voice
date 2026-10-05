import XCTest
@testable import VoiceWisprCore

final class UpdatePolicyTests: XCTestCase {
    private var valid: [String: Any] { [
        "CFBundleIdentifier": "com.mediapublishing.VoiceWispr",
        "SUFeedURL": UpdatePolicy.feedURL,
        "SUPublicEDKey": Data(repeating: 42, count: 32).base64EncodedString(),
        "SUVerifyUpdateBeforeExtraction": true, "SURequireSignedFeed": true,
        "SUSignedFeedFailureExpirationInterval": 0
    ] }
    func testPublishingIdentityAndSignedChannelRequired() {
        XCTAssertTrue(UpdatePolicy.configured(valid))
        for field in ["SUPublicEDKey", "SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction", "SUSignedFeedFailureExpirationInterval"] {
            var info = valid; info.removeValue(forKey: field)
            XCTAssertFalse(UpdatePolicy.configured(info), field)
        }
    }
    func testUntrustedFeedsAndMalformedKeysCannotStartUpdater() {
        for feed in ["http://voice.ainauten.com/updates/appcast.xml", "https://evil.example/appcast.xml", "https://voice.ainauten.com@evil.example/updates/appcast.xml", UpdatePolicy.feedURL + "?token=secret"] {
            var info = valid; info["SUFeedURL"] = feed; XCTAssertFalse(UpdatePolicy.configured(info))
        }
        for key in ["", "garbage", Data(repeating: 1, count: 31).base64EncodedString(), Data(repeating: 0, count: 32).base64EncodedString()] {
            var info = valid; info["SUPublicEDKey"] = key; XCTAssertFalse(UpdatePolicy.configured(info))
        }
    }
    func testFailClosedDoesNotExpireAndForeignBundleRejected() {
        var info = valid; info["SUSignedFeedFailureExpirationInterval"] = 1728000
        XCTAssertFalse(UpdatePolicy.configured(info))
        info = valid; info["CFBundleIdentifier"] = "com.other.App"; XCTAssertFalse(UpdatePolicy.configured(info))
    }
    func testRecordingProcessingOrSetupDefersUpdate() {
        XCTAssertFalse(UpdatePolicy.busy(recording: false, processing: false, setup: false))
        XCTAssertTrue(UpdatePolicy.busy(recording: true, processing: false, setup: false))
        XCTAssertTrue(UpdatePolicy.busy(recording: false, processing: true, setup: false))
        XCTAssertTrue(UpdatePolicy.busy(recording: false, processing: false, setup: true))
    }
}
