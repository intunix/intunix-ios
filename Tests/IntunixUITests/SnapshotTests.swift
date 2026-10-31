#if os(iOS)
import XCTest
import SwiftUI
@testable import Intunix
import IntunixCore

/// Renders each question type at phone width (360pt) to PNGs in $SNAPSHOT_DIR, for review.
@MainActor
final class SnapshotTests: XCTestCase {
    private func host(_ steps: String, _ answers: [Answer] = []) -> FormHost {
        let raw = parseJSON(#"{"id":"f","type":"popup","content":{"kind":"feedback","brand":{"color":"2F9461"},"steps":["# + steps + "]},\"triggers\":[]}") as! JSONObject
        let exp = parseExperience(raw)!
        let cb = RenderCallbacks(onImpression: {}, onResponse: { _ in }, onDismiss: {}, clientResponseId: "r", onReviewEvent: { _ in })
        let h = FormHost(exp: exp, content: parseFeedbackContent(exp.content)!, callbacks: cb, openUrl: { _ in true }) { _ in }
        answers.forEach { h.onChange($0.stepId, $0) }
        return h
    }

    private func shot(_ name: String, _ h: FormHost, width: CGFloat = 360) throws {
        guard #available(iOS 16.0, *) else { throw XCTSkip("ImageRenderer needs iOS 16") }
        let view = FeedbackFormView(host: h, fixedWidth: width - 40).padding(20).frame(width: width).background(Color.white)
        let r = ImageRenderer(content: view)
        r.scale = 2
        let png = try XCTUnwrap(r.uiImage?.pngData())
        let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? NSTemporaryDirectory() + "intunix-snapshots"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func n(_ id: String, _ kind: String, _ v: Int) -> Answer { Answer(id, kind, .num(v)) }
    private let extra = #",{"id":"z","kind":"nps","title":"Second question"}"#

    func testNps() throws {
        try shot("nps", host(#"{"id":"a","kind":"nps","title":"How likely are you to recommend us to a friend?","subtitle":"0 = not likely, 10 = very likely"}"# + extra, [n("a", "nps", 9)]))
    }
    func testStarsAndCes() throws {
        try shot("stars-ces", host(#"{"id":"s","kind":"star","title":"Rate out of 10","max":10,"icons":"ramp","page":1},{"id":"c","kind":"ces","title":"How easy was it?","page":1}"# + extra, [n("s", "star", 7), n("c", "ces", 6)]))
    }
    func testSmileys() throws {
        try shot("smileys", host(#"{"id":"m","kind":"smileys","title":"How do you feel?","icons":"mood","page":1},{"id":"e","kind":"smileys","title":"Emoji smileys","page":1},{"id":"l","kind":"smileys","title":"Line smileys","icons":"line","page":1}"# + extra,
                                 [n("m", "smileys", 4), n("e", "smileys", 2), n("l", "smileys", 5)]))
    }
    func testCsat() throws {
        try shot("csat", host(#"{"id":"c","kind":"csat","title":"How satisfied are you?","icons":"pastel"}"# + extra, [n("c", "csat", 4)]))
        try shot("csat-wide", host(#"{"id":"c","kind":"csat","title":"How satisfied are you?"}"# + extra, [n("c", "csat", 4)]), width: 600)
    }
    func testThumbs() throws {
        try shot("thumbs", host(#"{"id":"t","kind":"thumbs","title":"Was this helpful?","icons":"tone","page":1},{"id":"u","kind":"thumbs","title":"Mark set","icons":"mark","page":1},{"id":"v","kind":"thumbs","title":"Emoji","page":1}"# + extra,
                                [Answer("t", "thumbs", .choice("up")), Answer("u", "thumbs", .choice("down")), Answer("v", "thumbs", .choice("up"))]))
    }
    func testChoices() throws {
        try shot("choices", host(#"{"id":"p","kind":"pmf","title":"How would you feel if you could no longer use it?","page":1},{"id":"o","kind":"followup","title":"Pick all that apply","page":1,"input":{"type":"selectMultiple","options":[{"value":"a","label":"Pricing and plans"},{"value":"b","label":"Onboarding experience was confusing for our whole team"},{"value":"c","label":"Speed","emoji":"⚡"}]}},{"id":"f","kind":"followup","title":"Anything else?","page":1,"input":{"type":"free","maxLength":500}}"# + extra,
                                 [Answer("p", "pmf", .choice("somewhat")), Answer("o", "followup", .many(["b", "c"]))]))
    }
    func testThanks() throws {
        try shot("thanks", host(#"{"id":"t","kind":"thumbs","title":"Was this helpful?"}"#, [Answer("t", "thumbs", .choice("up"))]))
    }
}
#endif
