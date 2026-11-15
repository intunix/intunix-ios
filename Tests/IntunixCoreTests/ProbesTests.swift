import XCTest
@testable import Intunix

// Linux XCTest cannot discover @MainActor methods, so every test runs its body through onMain.
final class ProbesTests: XCTestCase {
    private func npsStep(_ id: String, ai: Bool = true) -> Step { var s = Step(id: id, kind: "nps", title: id); s.aiFollowUp = ai; return s }
    private func probe(_ id: String, kind: String = "followup", title: String = "Why?") -> String {
        #"{"id":"\#(id)","kind":"\#(kind)","title":"\#(title)","input":{"type":"free"},"required":false}"#
    }
    private func ans(_ id: String, _ v: Int = 3) -> Answer { num(id, v) }
    private let cfg = ConversationConfig(mode: "enhanced")

    @MainActor private func probes(_ t: Fake, locale: String? = "en", timing: ConversationTiming = fastTiming) -> EnhancedProbes {
        EnhancedProbes(handle: ConversationHandle(config: cfg, transport: t.transport, conversationId: "c1"), locale: locale, timing: timing)
    }
    private func ids(_ u: ProbeUpdate) -> [String] { u.insert.map { "\($0.anchor)>\($0.step.id)" } }

    func testRequestsAProbeOnlyForAiFollowUpSteps() async {
        await onMain {
            let t = Fake()
            _ = await self.probes(t).afterPage([self.npsStep("s1", ai: false), self.npsStep("s2")], [self.ans("s1"), self.ans("s2")])
            XCTAssertEqual(t.sent, [TurnRequest("c1", 0, "answer", self.ans("s2"), "en")])
        }
    }

    func testDoesNotRequestForAnAiFollowUpStepWithoutAnAnswer() async {
        await onMain {
            let t = Fake()
            let u = await self.probes(t).afterPage([self.npsStep("s1")], [])
            XCTAssertEqual(u.insert.count, 0)
            XCTAssertEqual(t.sent.count, 0)
        }
    }

    func testReturnsTheProbeStepPairedWithItsAnchor() async {
        await onMain {
            let u = await self.probes(Fake(reply(input: self.probe("probe:s1:1")))).afterPage([self.npsStep("s1")], [self.ans("s1")])
            XCTAssertEqual(self.ids(u), ["s1>probe:s1:1"])
            XCTAssertEqual(u.insert[0].step.title, "Why?")
        }
    }

    func testAsksAgainAfterAProbeIsAnswered() async {
        await onMain {
            let t = Fake()
            _ = await self.probes(t).afterPage([step(self.probe("probe:s2:1"))], [free("probe:s2:1", "x")])
            XCTAssertEqual(t.sent.count, 1)
            XCTAssertEqual(t.sent[0].answer?.stepId, "probe:s2:1")
        }
    }

    func testSendsNextTurnFromThePreviousReply() async {
        await onMain {
            let t = Fake(reply(4))
            let p = self.probes(t)
            _ = await p.afterPage([self.npsStep("s1")], [self.ans("s1")])
            _ = await p.afterPage([self.npsStep("s1")], [self.ans("s1", 5)])
            XCTAssertEqual(t.sent.map(\.turn), [0, 4])
        }
    }

    func testResolvesEmptyWhenTheReplyHasNoInput() async {
        await onMain {
            let u = await self.probes(Fake(reply())).afterPage([self.npsStep("s1")], [self.ans("s1")])
            XCTAssertEqual(u.insert.count, 0)
        }
    }

    func testTimesOutAndDisablesItself() async {
        await onMain {
            let t = Fake(Hang())
            let p = self.probes(t)
            let s = [self.npsStep("s1")]
            let u = await p.afterPage(s, [self.ans("s1")])
            XCTAssertEqual(u.insert.count, 0)
            _ = await p.afterPage(s, [self.ans("s1", 9)])
            XCTAssertEqual(t.sent.count, 1)
        }
    }

    func testABlockingCallThatIgnoresCancellationIsBoundedByTheBudget() async {
        await onMain {
            let gate = Gate()
            let t = Fake(gate)
            let t0 = Date()
            let u = await self.probes(t).afterPage([self.npsStep("s1")], [self.ans("s1")])
            XCTAssertLessThan(Date().timeIntervalSince(t0), 1.5)
            XCTAssertEqual(u.insert.count, 0)
            gate.complete(reply(input: self.probe("probe:s1:1"))) // a late reply is dropped
            await settle()
            XCTAssertEqual(t.sent.count, 1)
        }
    }

    func testARejectionDisablesItWithoutThrowing() async {
        await onMain {
            let t = Fake(Boom())
            let p = self.probes(t)
            let s = [self.npsStep("s1")]
            let u1 = await p.afterPage(s, [self.ans("s1")])
            XCTAssertEqual(u1.insert.count, 0)
            _ = await p.afterPage(s, [self.ans("s1", 9)])
            XCTAssertEqual(t.sent.count, 1)
        }
    }

    func testRetriesABusyReplyOnceUsingTheBusyNextTurn() async {
        await onMain {
            let t = Fake(reply(2, busy: true), reply(3, input: self.probe("probe:s1:1")))
            let u = await self.probes(t).afterPage([self.npsStep("s1")], [self.ans("s1")])
            XCTAssertEqual(self.ids(u), ["s1>probe:s1:1"])
            XCTAssertEqual(t.sent.map(\.turn), [0, 2])
        }
    }

    func testDoesNotRetryASecondBusyReplyAndStaysEnabled() async {
        await onMain {
            let t = Fake(reply(busy: true), reply(busy: true))
            let p = self.probes(t)
            let s = [self.npsStep("s1")]
            let u = await p.afterPage(s, [self.ans("s1")])
            XCTAssertEqual(u.insert.count, 0)
            _ = await p.afterPage(s, [self.ans("s1", 9)])
            XCTAssertEqual(t.sent.count, 3)
        }
    }

    func testAsksSequentiallyOneRequestPerAnsweredStepInPageOrder() async {
        await onMain {
            let t = Fake(reply(1), reply(2))
            _ = await self.probes(t).afterPage([self.npsStep("a"), self.npsStep("b")], [self.ans("b"), self.ans("a")])
            XCTAssertEqual(t.sent.map { "\($0.answer?.stepId ?? "")@\($0.turn)" }, ["a@0", "b@1"])
        }
    }

    func testDoesNotAskTwiceForTheSameAnswerButDoesWhenItChanges() async {
        await onMain {
            let t = Fake()
            let p = self.probes(t)
            let s = [self.npsStep("s1")]
            _ = await p.afterPage(s, [self.ans("s1", 3)])
            _ = await p.afterPage(s, [self.ans("s1", 3)])
            XCTAssertEqual(t.sent.count, 1)
            _ = await p.afterPage(s, [self.ans("s1", 4)])
            XCTAssertEqual(t.sent.count, 2)
        }
    }

    func testIgnoresInputsThatAreNotValidProbesOrAreDuplicates() async {
        await onMain {
            let good = self.probe("probe:s1:1")
            let noInput = #"{"id":"probe:s1:2","kind":"nps","title":"Why?"}"#
            let t = Fake(reply(input: self.probe("other:1")), reply(input: noInput), reply(input: self.probe("probe:s1:3", title: "")), reply(input: good), reply(input: good))
            let p = self.probes(t)
            let s = [self.npsStep("s1")]
            for v in 1...3 { let u = await p.afterPage(s, [self.ans("s1", v)]); XCTAssertEqual(u.insert.count, 0) }
            let u = await p.afterPage(s, [self.ans("s1", 4)])
            XCTAssertEqual(self.ids(u), ["s1>probe:s1:1"])
            let dup = await p.afterPage([self.npsStep("s2")], [self.ans("s2", 5)]) // same id from another step
            XCTAssertEqual(dup.insert.count, 0)
        }
    }

    func testReportsDropWhenAnAnswerChangesAndReAsks() async {
        await onMain {
            let t = Fake()
            let p = self.probes(t)
            let s = [self.npsStep("s1")]
            var u = await p.afterPage(s, [self.ans("s1", 3)]); XCTAssertEqual(u.drop, [])
            u = await p.afterPage(s, [self.ans("s1", 3)]); XCTAssertEqual(u.drop, [])
            XCTAssertEqual(t.sent.count, 1)
            u = await p.afterPage(s, [self.ans("s1", 4)]); XCTAssertEqual(u.drop, ["s1"])
            XCTAssertEqual(t.sent.count, 2)
        }
    }

    func testReportsDropWhenTheAnswerWasRemovedWithoutARequest() async {
        await onMain {
            let t = Fake()
            let p = self.probes(t)
            let s = [self.npsStep("s1")]
            _ = await p.afterPage(s, [self.ans("s1")])
            let u = await p.afterPage(s, [])
            XCTAssertEqual(u.drop, ["s1"]); XCTAssertEqual(u.insert.count, 0)
            XCTAssertEqual(t.sent.count, 1)
        }
    }

    func testAcceptsAReIssuedProbeIdAfterADrop() async {
        await onMain {
            let p1 = self.probe("probe:s1:1")
            let p = self.probes(Fake(reply(input: p1), reply(input: p1)))
            let s = [self.npsStep("s1")]
            _ = await p.afterPage(s, [self.ans("s1", 3)])
            let u = await p.afterPage(s, [self.ans("s1", 4)])
            XCTAssertEqual(u.drop, ["s1"]); XCTAssertEqual(self.ids(u), ["s1>probe:s1:1"])
        }
    }

    func testADisabledHelperStillReportsDrop() async {
        await onMain {
            let p = self.probes(Fake(Boom()))
            let s = [self.npsStep("s1")]
            _ = await p.afterPage(s, [self.ans("s1", 3)])
            let u = await p.afterPage(s, [self.ans("s1", 4)])
            XCTAssertEqual(u.drop, ["s1"]); XCTAssertEqual(u.insert.count, 0)
        }
    }

    func testATransportThatThrowsSynchronouslyDisablesWithoutRejecting() async {
        await onMain {
            var sent = 0
            let p = EnhancedProbes(handle: ConversationHandle(config: self.cfg, transport: { _ in sent += 1; throw Boom() }, conversationId: "c1"),
                                   locale: "en", timing: fastTiming)
            let s = [self.npsStep("s1")]
            let u = await p.afterPage(s, [self.ans("s1")])
            XCTAssertEqual(u.insert.count, 0)
            _ = await p.afterPage(s, [self.ans("s1", 9)])
            XCTAssertEqual(sent, 1)
        }
    }

    func testClearsTheBusyRetryWaitWhenTheBudgetEndsFirst() async {
        await onMain {
            let t = Fake(reply(busy: true), Hang())
            let timing = ConversationTiming(turnTimeoutMs: 200, busyRetryMs: 5, probeTimeoutMs: 100)
            _ = await self.probes(t, timing: timing).afterPage([self.npsStep("s1")], [self.ans("s1")])
            XCTAssertEqual(t.sent.count, 2)
        }
    }

    func testTreatsAnInvalidReplyAsAFailureDisabledNothingInserted() async {
        await onMain {
            let t = Fake(jobj(#"{"messages":[],"done":false,"next_turn":1}"#))
            let p = self.probes(t)
            let u = await p.afterPage([self.npsStep("s1")], [self.ans("s1")])
            XCTAssertEqual(u.insert.count, 0)
            _ = await p.afterPage([self.npsStep("s2")], [self.ans("s2")])
            XCTAssertEqual(t.sent.count, 1)
        }
    }

    func testStopsSendingAfterAReplyWithDoneTrue() async {
        await onMain {
            let t = Fake(reply(done: true))
            let p = self.probes(t)
            _ = await p.afterPage([self.npsStep("s1")], [self.ans("s1")])
            let u = await p.afterPage([self.npsStep("s2")], [self.ans("s2")])
            XCTAssertEqual(u.insert.count, 0)
            XCTAssertEqual(t.sent.count, 1)
        }
    }

    func testDefaultTimingIsTenSeconds() {
        let t = ConversationTiming()
        XCTAssertEqual([t.turnTimeoutMs, t.busyRetryMs, t.probeTimeoutMs], [10_000, 700, 10_000])
    }

    func testSetLocaleLaterRequestsCarryTheNewLocale() async {
        await onMain {
            let t = Fake()
            let p = self.probes(t)
            p.setLocale("ar")
            _ = await p.afterPage([self.npsStep("s1")], [self.ans("s1")])
            XCTAssertEqual(t.sent[0].locale, "ar")
        }
    }

    func testABusyRetryKeepsItsFirstLocaleTheNextRequestUsesTheNewOne() async {
        await onMain {
            let t = Fake(reply(2, busy: true), reply(3), reply(4))
            let p = self.probes(t, timing: ConversationTiming(turnTimeoutMs: 200, busyRetryMs: 60, probeTimeoutMs: 500))
            let out = Task { await p.afterPage([self.npsStep("s1")], [self.ans("s1")]) }
            await settle(20)
            p.setLocale("ar")
            _ = await out.value
            XCTAssertEqual(t.sent.map(\.locale), ["en", "en"])
            _ = await p.afterPage([self.npsStep("s2")], [self.ans("s2")])
            XCTAssertEqual(t.sent[2].locale, "ar")
        }
    }

    func testNoLocaleWhenNil() async {
        await onMain {
            let t = Fake()
            _ = await self.probes(t, locale: nil).afterPage([self.npsStep("s1")], [self.ans("s1")])
            XCTAssertNil(t.sent[0].locale)
            XCTAssertNil(t.sent[0].json["locale"])
        }
    }

    func testAnUnbuildableInputIsSkippedWithoutDisablingAdvancingTheTurnAndHonouringDone() async {
        await onMain {
            let unknownKind = #"{"id":"probe:s1:1","kind":"hologram","title":"?"}"#
            let unknownInput = #"{"id":"probe:s1:2","kind":"followup","title":"?","input":{"type":"hologram"}}"#
            let t = Fake(reply(2, input: unknownKind), reply(3, input: unknownInput), reply(4, input: self.probe("probe:s1:3")))
            let p = self.probes(t)
            let s = [self.npsStep("s1")]
            var u = await p.afterPage(s, [self.ans("s1", 1)]); XCTAssertEqual(u.insert.count, 0)
            u = await p.afterPage(s, [self.ans("s1", 2)]); XCTAssertEqual(u.insert.count, 0)
            u = await p.afterPage(s, [self.ans("s1", 3)]); XCTAssertEqual(self.ids(u), ["s1>probe:s1:3"])
            XCTAssertEqual(t.sent.map(\.turn), [0, 2, 3])
            let d = Fake(reply(2, input: unknownKind, done: true))
            let q = self.probes(d)
            _ = await q.afterPage(s, [self.ans("s1", 1)])
            _ = await q.afterPage([self.npsStep("s2")], [self.ans("s2")])
            XCTAssertEqual(d.sent.count, 1)
        }
    }
}
