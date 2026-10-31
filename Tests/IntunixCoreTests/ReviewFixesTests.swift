import XCTest
@testable import IntunixCore

/// Regressions from the 1.5.1 review.
final class ReviewFixesTests: XCTestCase {
    func testNonJSONValuesNoLongerBlankTheWholePayload() {
        let s = jsonString(["at": Date(timeIntervalSince1970: 0), "nan": Double.nan, "ok": 1, "nested": ["inf": Double.infinity]] as JSONObject)
        XCTAssertEqual(s, #"{"at":"1970-01-01T00:00:00Z","nan":null,"nested":{"inf":null},"ok":1}"#)
    }

    func testOfflineStoreSurvivesBadValuesAndRemovesUploaded() {
        let store = MemoryStore()
        let off = OfflineStore(store) { 0 }
        off.save([["name": "a", "timestamp": 0], ["name": "b", "timestamp": 0, "at": Date()]])
        XCTAssertEqual(off.readAll().count, 2)
        off.remove([["name": "a", "timestamp": 0]])
        XCTAssertEqual(off.readAll().compactMap { $0.str("name") }, ["b"])
    }

    func testReviewUrlWithSpacesIsAccepted() {
        XCTAssertNotNil(safeReviewUrl("https://example.com/review us"))
        XCTAssertNil(safeReviewUrl("javascript:alert(1)"))
    }

    func testInvalidScalesDoNotTrap() {
        var ces = Step(id: "c", kind: "ces", title: "x")
        ces.scale = 0
        XCTAssertFalse(isAnswerValid(ces, Answer("c", "ces", .num(1))))
        let star = Step(id: "s", kind: "star", title: "x", max: 0)
        XCTAssertFalse(isAnswerValid(star, Answer("s", "star", .num(1))))
    }

    func testMaxLengthCountsUtf16LikeJavaScript() {
        let step = Step(id: "f", kind: "followup", title: "x", input: FollowUpInput(type: "free", maxLength: 2))
        XCTAssertTrue(isAnswerValid(step, Answer("f", "followup", .text(type: "free", text: "😀"))))
        XCTAssertFalse(isAnswerValid(step, Answer("f", "followup", .text(type: "free", text: "😀a"))))
    }

    func testDictionaryContextKeysAreStable() {
        let e = parseExperience(parseJSON(#"{"id":"f","content":{},"triggers":[],"frequencyScope":"form_context"}"#) as! JSONObject)!
        let k = identityKey(e, uid: "u", traits: [:], context: ["p": ["b": 1, "a": 2]])
        XCTAssertEqual(k, #"u|ctx={"p":{"a":2,"b":1}}"#)
    }
}
