import XCTest
@testable import Intunix

/// Ported from @intunix/core tests (same inputs and expected outputs as the Android port).
final class CadenceTests: XCTestCase {
    let day = DAY_MS, now: Int64 = 1_700_000_000_000, sid = "sess-1"
    func shown(_ at: Int64? = nil, _ count: Int = 1) -> ShownRecord { ShownRecord(lastShownAt: at ?? now, count: count, sessionId: sid) }
    func cad(_ a: Wait = .days(0), _ d: Wait = .days(0), _ i: Wait = .days(0), mode: String = "cooldown", giveUp: Int? = nil) -> NormalizedCadence {
        NormalizedCadence(mode, a, d, i, giveUp)
    }

    func testNormalize() {
        XCTAssertEqual(normalizeCadence(nil), NormalizedCadence("every_session", .session, .session, .session))
        XCTAssertEqual(normalizeCadence(Cadence(mode: "once")), NormalizedCadence("once", .never, .never, .never))
        XCTAssertEqual(normalizeCadence(Cadence(mode: "always", giveUpAfterShows: 3)), NormalizedCadence("always", .days(0), .days(0), .days(0)))
        XCTAssertEqual(normalizeCadence(Cadence(mode: "cooldown", answered: .days(30))), NormalizedCadence("cooldown", .days(30), .days(0), .days(0)))
    }

    func testWaits() {
        XCTAssertTrue(checkCadence(cad(.never, .never, .never), nil, nil, now: now, sessionId: sid))
        let answeredLongAgo = OutcomeRecord(respondedAt: now - 999 * day, showCount: 1, lastOutcome: "responded", lastOutcomeAt: now - 999 * day)
        XCTAssertFalse(checkCadence(cad(.never), shown(now - 999 * day), answeredLongAgo, now: now, sessionId: sid))
        XCTAssertFalse(checkCadence(cad(.days(0), .days(0), .session), shown(), nil, now: now, sessionId: sid))
        XCTAssertTrue(checkCadence(cad(.days(0), .days(0), .session), shown(), nil, now: now, sessionId: "sess-2"))
        let c = cad(.days(30), .days(7), .days(1))
        func answered(_ at: Int64) -> OutcomeRecord { OutcomeRecord(respondedAt: at, showCount: 1, lastOutcome: "responded", lastOutcomeAt: at) }
        XCTAssertFalse(checkCadence(c, shown(now - 10 * day), answered(now - 10 * day), now: now, sessionId: sid))
        XCTAssertTrue(checkCadence(c, shown(now - 31 * day), answered(now - 31 * day), now: now, sessionId: sid))
        XCTAssertTrue(checkCadence(c, shown(now - 10 * day), OutcomeRecord(showCount: 1, lastOutcome: "dismissed", lastOutcomeAt: now - 10 * day), now: now, sessionId: sid))
    }

    func testGiveUp() {
        let ignored = OutcomeRecord(showCount: 3, lastOutcome: "timeout", lastOutcomeAt: now)
        XCTAssertFalse(checkCadence(cad(giveUp: 3), shown(nil, 3), ignored, now: now, sessionId: sid))
        XCTAssertTrue(checkCadence(cad(giveUp: 3), shown(nil, 2), ignored, now: now, sessionId: sid))
        let answered = OutcomeRecord(respondedAt: now - 99 * day, showCount: 3, lastOutcome: "responded", lastOutcomeAt: now - 99 * day)
        XCTAssertTrue(checkCadence(cad(giveUp: 3), shown(now - 99 * day, 9), answered, now: now, sessionId: sid))
        XCTAssertTrue(checkCadence(cad(mode: "always", giveUp: 1), shown(nil, 50), ignored, now: now, sessionId: sid))
    }
}

final class GatesTests: XCTestCase {
    func exp(_ json: String) -> Experience {
        var base = parseJSON(#"{"id":"f1","type":"modal","content":{"kind":"feedback","steps":[]},"triggers":[]}"#) as! JSONObject
        (parseJSON(json) as! JSONObject).forEach { base[$0.key] = $0.value }
        return parseExperience(base)!
    }
    let user = GateUser(id: "u1", traits: ["plan": "pro", "seats": 12])

    func testPlatform() {
        XCTAssertTrue(checkPlatform(exp("{}")))
        XCTAssertFalse(checkPlatform(exp(#"{"platforms":["web"]}"#)))
        XCTAssertTrue(checkPlatform(exp(#"{"platforms":["web","app"]}"#)))
    }

    func testLegacyTraitEquals() {
        let e = exp(#"{"targeting":{"traitEquals":{"plan":"pro"}}}"#)
        XCTAssertFalse(checkTargeting(e, nil, [:], screen: ""))
        XCTAssertTrue(checkTargeting(e, user, [:], screen: ""))
        XCTAssertFalse(checkTargeting(e, GateUser(id: "u", traits: ["plan": "free"]), [:], screen: ""))
    }

    func testRuleOps() {
        func rule(_ r: String) -> Experience { exp(#"{"targeting":{"rules":["# + r + "]}}") }
        XCTAssertTrue(checkTargeting(rule(#"{"kind":"trait","key":"seats","op":"gt","value":10}"#), user, [:], screen: ""))
        XCTAssertFalse(checkTargeting(rule(#"{"kind":"trait","key":"seats","op":"lt","value":10}"#), user, [:], screen: ""))
        XCTAssertTrue(checkTargeting(rule(#"{"kind":"trait","key":"plan","op":"in","value":["pro","team"]}"#), user, [:], screen: ""))
        XCTAssertFalse(checkTargeting(rule(#"{"kind":"trait","key":"plan","op":"nin","value":"pro"}"#), user, [:], screen: ""))
        XCTAssertTrue(checkTargeting(rule(#"{"kind":"trait","key":"missing","op":"neq","value":"x"}"#), user, [:], screen: ""))
        XCTAssertFalse(checkTargeting(rule(#"{"kind":"trait","key":"missing","op":"eq","value":"x"}"#), user, [:], screen: ""))
        XCTAssertTrue(checkTargeting(rule(#"{"kind":"context","key":"page","op":"exists"}"#), user, ["page": "home"], screen: ""))
        XCTAssertFalse(checkTargeting(rule(#"{"kind":"context","key":"page","op":"exists"}"#), user, [:], screen: ""))
        XCTAssertTrue(checkTargeting(rule(#"{"kind":"url","op":"contains","value":"Checkout"}"#), user, [:], screen: "CheckoutScreen"))
        XCTAssertTrue(checkTargeting(rule(#"{"kind":"context","key":"n","op":"eq","value":3}"#), user, ["n": 3.0], screen: ""))
        XCTAssertFalse(checkTargeting(rule(#"{"kind":"context","key":"flag","op":"eq","value":1}"#), user, ["flag": true], screen: ""))
    }

    func testEligibility() {
        let p = ProfileData(firstSeenAt: 0, sessionCount: 2, lastSeenAt: 0)
        XCTAssertFalse(checkEligibility(exp(#"{"eligibility":{"minSessions":3}}"#), p, now: 10))
        XCTAssertTrue(checkEligibility(exp(#"{"eligibility":{"minDaysSinceFirstSeen":1}}"#), p, now: DAY_MS + 1))
        let at = parseIsoMillis("2026-01-01T00:00:00Z")!
        XCTAssertEqual(at, 1_767_225_600_000)
        XCTAssertEqual(parseIsoMillis("2026-01-01T00:00:00.000Z"), at)
        XCTAssertEqual(parseIsoMillis("2026-01-01"), at)
        XCTAssertNil(parseIsoMillis("2026-13-45"))
        XCTAssertFalse(checkEligibility(exp(#"{"eligibility":{"startAt":"2026-01-01T00:00:00Z"}}"#), p, now: at - 1))
        XCTAssertTrue(checkEligibility(exp(#"{"eligibility":{"startAt":"2026-01-01T00:00:00Z"}}"#), p, now: at))
        XCTAssertFalse(checkEligibility(exp(#"{"eligibility":{"endAt":"not a date"}}"#), p, now: at))
    }

    func testIdentityKey() {
        let e = exp(#"{"targeting":{"rules":[{"kind":"trait","key":"plan","op":"exists"},{"kind":"context","key":"page","op":"exists"}]},"frequencyScope":"form_context"}"#)
        XCTAssertEqual(identityKey(e, uid: "u1", traits: user.traits, context: ["page": "home", "other": 1]), #"u1|plan=pro|ctx={"page":"home"}"#)
        XCTAssertEqual(identityKey(exp("{}"), uid: "anon", traits: user.traits, context: [:]), "anon")
    }

    func testStoresAndSession() {
        let store = MemoryStore()
        let profile = ProfileStore(store) { 1000 }
        profile.recordOutcome("f1", "anon-1|role=tutor", "responded")
        profile.mergeIdentity(from: "anon-1", to: "user-9")
        XCTAssertNotNil(profile.outcomes("f1", "user-9|role=tutor")?.respondedAt)
        XCTAssertNil(profile.outcomes("f1", "anon-1|role=tutor"))
        let shown = ShownStore(store)
        shown.markShown("f1", "anon-1", now: 5, sessionId: "s")
        shown.markShown("f1", "anon-1", now: 6, sessionId: "s")
        shown.mergeIdentity(from: "anon-1", to: "user-9")
        XCTAssertEqual(shown.get("f1", "user-9")?.count, 2)

        var now: Int64 = 0
        let s = SessionManager(MemoryStore()) { now }
        var seen: [String] = []
        s.onNewSession { seen.append($0) }
        let a = s.id(); _ = s.id()
        now += SessionManager.ttlMs + 1
        let b = s.id()
        XCTAssertEqual(seen, [a, b])
    }
}

final class FeedbackTests: XCTestCase {
    func content(_ steps: String, _ extra: String = "") -> FeedbackContent {
        parseFeedbackContent(parseJSON(#"{"kind":"feedback","brand":{"color":"2F9461"},"steps":["# + steps + "]" + extra + "}") as! JSONObject)!
    }
    func num(_ id: String, _ kind: String, _ v: Int) -> Answer { Answer(id, kind, .num(v)) }
    func text(_ id: String, _ type: String, _ t: String) -> Answer { Answer(id, "followup", .text(type: type, text: t)) }
    let pageOne = #"{"id":"a","kind":"nps","title":"Recommend?","page":1},{"id":"b","kind":"star","title":"Rate","page":1},{"id":"c","kind":"thumbs","title":"Helpful?"}"#

    func testParse() {
        let c = content(pageOne + #",{"id":"x","kind":"hologram","title":"?"},{"id":"s","kind":"smileys","title":"Mood","icons":"mood"}"#)
        XCTAssertEqual(c.steps.map(\.id), ["a", "b", "c", "s"])
        XCTAssertEqual(c.steps.last?.icons, "mood")
        XCTAssertEqual(groupPages(content(pageOne).steps).map { $0.map(\.id) }, [["a", "b"], ["c"]])
    }

    func testPages() {
        let r = FeedbackRunner(content(pageOne), review: nil)
        XCTAssertEqual(r.state().pageSteps.map(\.id), ["a", "b"])
        r.record(num("a", "nps", 9))
        XCTAssertFalse(isPageValid(r.state().pageSteps, r.state().answers))
        r.record(num("b", "star", 4))
        XCTAssertTrue(isPageValid(r.state().pageSteps, r.state().answers))
        r.submitPage()
        XCTAssertEqual(r.state().pageSteps.map(\.id), ["c"])
        XCTAssertTrue(r.state().paged)
    }

    func testConditionalOnSamePage() {
        let r = FeedbackRunner(content(#"{"id":"a","kind":"thumbs","title":"Helpful?","page":1},{"id":"why","kind":"followup","title":"Why not?","page":1,"showIf":{"stepId":"a","op":"eq","value":"down"},"input":{"type":"free"}}"#), review: nil)
        XCTAssertEqual(r.state().pageSteps.map(\.id), ["a"])
        r.record(Answer("a", "thumbs", .choice("down")))
        XCTAssertEqual(r.state().pageSteps.map(\.id), ["a", "why"])
        r.record(text("why", "free", "slow"))
        r.record(Answer("a", "thumbs", .choice("up")))
        XCTAssertEqual(r.state().pageSteps.map(\.id), ["a"])
        XCTAssertEqual(r.state().answers.count, 1)
    }

    func testDismissAndEmpty() {
        let e = FeedbackRunner(content(#"{"id":"e","kind":"followup","title":"Email","input":{"type":"email"}}"#), review: nil)
        e.record(text("e", "email", "half@"))
        XCTAssertTrue(e.dismiss().answers.isEmpty)
        let f = FeedbackRunner(content(#"{"id":"f","kind":"followup","title":"More","input":{"type":"free"}}"#), review: nil)
        f.record(text("f", "free", "hi"))
        f.record(text("f", "free", "  "))
        XCTAssertTrue(f.state().answers.isEmpty)
    }

    func testEndPhases() {
        let t = FeedbackRunner(content(#"{"id":"t","kind":"thumbs","title":"?"}"#), review: nil)
        t.answer(Answer("t", "thumbs", .choice("up")))
        XCTAssertEqual(t.state().phase, .thanks)
        let off = FeedbackRunner(content(#"{"id":"t","kind":"thumbs","title":"?"}"#, #","thanks":{"enabled":false}"#), review: nil)
        off.answer(Answer("t", "thumbs", .choice("up")))
        XCTAssertEqual(off.state().phase, .done)
        let review = ReviewRequestConfig(enabled: true, platform: "google", reviewUrl: "https://g.page/r/x/review", rule: "nps", threshold: 9)
        let r = FeedbackRunner(content(#"{"id":"n","kind":"nps","title":"?"}"#), review: review)
        r.answer(num("n", "nps", 10))
        XCTAssertEqual(r.state().phase, .review)
    }

    func testValidation() {
        let star = Step(id: "s", kind: "star", title: "R", max: 10)
        XCTAssertTrue(isAnswerValid(star, num("s", "star", 10)))
        XCTAssertFalse(isAnswerValid(star, num("s", "star", 11)))
        XCTAssertFalse(isAnswerValid(star, nil))
        let optional = Step(id: "f", kind: "followup", title: "x", input: FollowUpInput(type: "free", maxLength: 3))
        XCTAssertTrue(isAnswerValid(optional, nil))
        XCTAssertFalse(isAnswerValid(optional, text("f", "free", "toolong")))
        let many = Step(id: "m", kind: "followup", title: "x", required: true,
                        input: FollowUpInput(type: "selectMultiple", options: [ChoiceOption(value: "a", label: "A", emoji: nil), ChoiceOption(value: "b", label: "B", emoji: nil)], maxPick: 1))
        XCTAssertFalse(isAnswerValid(many, Answer("m", "followup", .many(["a", "b"]))))
        XCTAssertTrue(isAnswerValid(many, Answer("m", "followup", .many(["a"]))))
        XCTAssertTrue(isEmail("a@b.co"))
        XCTAssertFalse(isEmail("half@"))
    }

    func testShowIf() {
        let a = [num("n", "nps", 7)]
        XCTAssertTrue(evaluateShowIf(ShowIf(stepId: "n", op: "lte", value: 8, values: []), a))
        XCTAssertFalse(evaluateShowIf(ShowIf(stepId: "n", op: "gt", value: 8, values: []), a))
        XCTAssertTrue(evaluateShowIf(ShowIf(stepId: "n", op: "in", value: nil, values: [6, 7.0]), a))
        XCTAssertTrue(evaluateShowIf(ShowIf(stepId: "n", op: "eq", value: 7.0, values: []), a))
        XCTAssertFalse(evaluateShowIf(ShowIf(stepId: "x", op: "any", value: nil, values: []), a))
    }

    func testReview() {
        XCTAssertNil(safeReviewUrl("javascript:alert(1)"))
        XCTAssertNil(safeReviewUrl("example.com"))
        XCTAssertNil(safeReviewUrl("https://x.com/" + String(repeating: "a", count: 3000)))
        XCTAssertEqual(safeReviewUrl(" https://g.page/r/abc/review "), "https://g.page/r/abc/review")
        let cfg = ReviewRequestConfig(enabled: true, platform: "google", reviewUrl: "https://g.page/r/x", rule: "star", threshold: 4)
        XCTAssertTrue(reviewQualifies(cfg, [num("s", "star", 4)]))
        XCTAssertFalse(reviewQualifies(cfg, [num("m", "smileys", 5)]))
        var future = cfg; future.rule = "ai_sentiment"
        XCTAssertFalse(reviewQualifies(future, [num("s", "star", 5)]))
        var always = cfg; always.rule = "always"; always.threshold = nil
        XCTAssertTrue(reviewQualifies(always, []))

        var events: [String] = []
        var done = 0
        let p = ReviewPresenter.create(always, formId: "f", clientResponseId: "r", brandColor: "#000",
                                       emit: { events.append($0.name) }, openUrl: { _ in true }, onDone: { done += 1 })!
        p.onClick(); p.onClick(); p.onSkip()
        XCTAssertEqual(events, ["$review_request_clicked", "$review_request_redirected"])
        XCTAssertEqual(done, 1)
        var bad = always; bad.reviewUrl = "data:x"
        XCTAssertNil(ReviewPresenter.create(bad, formId: "f", clientResponseId: "r", brandColor: nil, emit: { _ in }, openUrl: { _ in true }, onDone: {}))
    }

    func testWire() {
        XCTAssertEqual(jsonString(AnswerValue.many(["a"]).wire), #"{"selected":["a"],"type":"selectMultiple"}"#)
        XCTAssertEqual(jsonString([num("n", "nps", 9).value.wire]), "[9]")
        XCTAssertEqual(starTone(3, 10), "low")
        XCTAssertEqual(starTone(7, 10), "high")
    }

    func testSvgPaths() {
        let star = parseSvgPath(IconPaths.star)
        XCTAssertEqual(star.first, .move(12, 2.5))
        XCTAssertEqual(star.count, 11)
        XCTAssertEqual(star.last, .close)
        let thumb = parseSvgPath(IconPaths.thumb)
        XCTAssertEqual(thumb[0], .move(7, 10))
        XCTAssertEqual(thumb[1], .line(7, 22))
        XCTAssertEqual(thumb[2], .move(15, 5.88))
        XCTAssertEqual(thumb[3], .line(14, 10)) // implicit lineto after M
        // r=2 over a 3.2 chord turns >90°, so the arc is two cubics (indexes 5 and 6).
        if case .cubic(_, _, _, _, let x, let y) = thumb[6] { XCTAssertEqual(x, 21.75, accuracy: 0.001); XCTAssertEqual(y, 12.56, accuracy: 0.001) }
        else { XCTFail("arc should become a cubic") }
        XCTAssertEqual(parseSvgPath(IconPaths.mouths[2]), [.move(16, 32), .line(32, 32)])
        XCTAssertEqual(parseSvgPath(IconPaths.mouths[0]), [.move(15, 35), .quad(24, 26, 33, 35)])
        let heart = parseSvgPath(IconPaths.heart)
        XCTAssertEqual(heart.filter { if case .cubic = $0 { return true }; return false }.count, 6)
    }
}
