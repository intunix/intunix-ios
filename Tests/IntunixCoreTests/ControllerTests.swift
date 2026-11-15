import XCTest
@testable import Intunix

private let S1j = nps("s1")
private let S2j = nps("s2", #","showIf":{"stepId":"s1","op":"lte","value":6}"#)
private let S3j = nps("s3")
private let FORM = content([S1j, S2j, S3j])
private let cfgC = ConversationConfig(mode: "conversational")

private func probeJson(_ id: String = "probe:s1:1", title: String = "Q s1") -> String {
    stepJson(id, #","input":{"type":"free"},"required":false"#, kind: "followup", title: title)
}
private func cc(_ done: String) -> ConversationConfig { ConversationConfig(mode: "conversational", completionMessage: done) }

// Linux XCTest cannot discover @MainActor methods, so every test runs its body through onMain.
final class ControllerTests: XCTestCase {
    @MainActor private func make(_ script: Any..., c: FeedbackContent = FORM, config: ConversationConfig = cfgC, locale: String? = "en")
        -> (ctl: ConversationController, t: Fake) {
        let t = Fake()
        t.load(script)
        return (ConversationController(content: c, handle: ConversationHandle(config: config, transport: t.transport, conversationId: "cid-12345"),
                                       locale: locale, timing: fastTiming), t)
    }
    @MainActor private func actions(_ t: Fake) -> [String] { t.sent.map(\.action) }

    func testStartSendsResumeTurn0AndShowsTheServerMessagesAndFirstInput() async {
        await onMain {
            let gate = Gate()
            let m = self.make(gate)
            let p = Task { await m.ctl.start() }
            await settle()
            XCTAssertTrue(m.ctl.state.pending)
            gate.complete(reply(4, "Hi", input: S1j))
            await p.value
            XCTAssertEqual(m.t.sent, [TurnRequest("cid-12345", 0, "resume", nil, "en")])
            let s = m.ctl.state
            XCTAssertEqual(s.messages.bare, [nia("Hi")])
            XCTAssertEqual(s.input?.id, "s1")
            XCTAssertFalse(s.pending); XCTAssertFalse(s.local)
        }
    }

    @MainActor private func transcriptJson(_ ms: [ChatMessage]) -> [JSONObject] { ms.map { ["role": $0.role, "text": $0.text] } }

    func testRestoresTheTranscriptOnResume() async {
        await onMain {
            let transcript = [nia("Hi"), ChatMessage("respondent", "9"), nia("Why?")]
            var r = reply(5, "ignored", input: S3j); r["transcript"] = self.transcriptJson(transcript)
            let m = self.make(r)
            await m.ctl.start()
            XCTAssertEqual(m.ctl.state.messages.bare, transcript)
        }
    }

    func testStartIsANoOpTheSecondTimeAndADoneResumeShowsTheTranscript() async {
        await onMain {
            let transcript = [nia("Hi"), nia("Bye")]
            var r = reply(1, done: true); r["transcript"] = self.transcriptJson(transcript)
            let m = self.make(r)
            await m.ctl.start(); await m.ctl.start()
            XCTAssertEqual(m.t.sent.count, 1)
            XCTAssertTrue(m.ctl.state.done); XCTAssertNil(m.ctl.state.input); XCTAssertEqual(m.ctl.state.messages.bare, transcript)
        }
    }

    func testAnswerAppendsTheRespondentBubbleSendsNextTurnThenShowsTheReply() async {
        await onMain {
            let gate = Gate()
            let m = self.make(reply(4, input: S1j), gate)
            await m.ctl.start()
            let p = Task { await m.ctl.answer(num("s1", 9)) }
            await settle()
            XCTAssertEqual(m.ctl.state.messages.filter { $0.role == "respondent" }.bare, [ChatMessage("respondent", "9")])
            XCTAssertTrue(m.ctl.state.pending)
            gate.complete(reply(5, "Thanks", input: S3j, answered: 1))
            _ = await p.value
            XCTAssertEqual(m.t.sent[1], TurnRequest("cid-12345", 4, "answer", num("s1", 9), "en"))
            let s = m.ctl.state
            XCTAssertEqual(s.messages.map(\.text), ["9", "Thanks"])
            XCTAssertEqual(s.input?.id, "s3")
            XCTAssertEqual(s.answered, 1); XCTAssertEqual(s.total, 3)
        }
    }

    func testIgnoresAnAnswerWhilePending() async {
        await onMain {
            let m = self.make(reply(1, input: S1j), reply(2, input: S3j))
            await m.ctl.start()
            let p1 = Task { await m.ctl.answer(num("s1", 9)) }
            let p2 = Task { await m.ctl.answer(num("s1", 3)) }
            _ = await (p1.value, p2.value)
            XCTAssertEqual(m.t.sent.filter { $0.action == "answer" }.count, 1)
            XCTAssertEqual(m.ctl.state.messages.filter { $0.role == "respondent" }.count, 1)
            XCTAssertEqual(m.ctl.result().answers, [num("s1", 9)])
        }
    }

    func testIgnoresAnAnswerForAStepThatIsNotTheCurrentInput() async {
        await onMain {
            let m = self.make(reply(1, input: S1j))
            await m.ctl.start()
            _ = await m.ctl.answer(num("s3", 5))
            XCTAssertEqual(m.t.sent.count, 1)
            XCTAssertEqual(m.ctl.state.messages, [])
        }
    }

    func testIgnoresAnInvalidAnswer() async {
        await onMain {
            let m = self.make(reply(1, input: followup("f", required: true)))
            await m.ctl.start()
            _ = await m.ctl.answer(free("f", "   "))
            _ = await m.ctl.answer(num("s1", 99))
            XCTAssertEqual(m.t.sent.count, 1)
            XCTAssertEqual(m.ctl.state.messages, [])
            XCTAssertFalse(m.ctl.state.pending)
        }
    }

    func testRetriesABusyReplyWithoutDuplicatingTheBubble() async {
        await onMain {
            let m = self.make(reply(4, input: S1j), reply(6, busy: true), reply(7, input: S3j))
            await m.ctl.start()
            _ = await m.ctl.answer(num("s1", 9))
            XCTAssertEqual(m.t.sent.count, 3)
            XCTAssertEqual(m.t.sent[2], TurnRequest("cid-12345", 6, "answer", num("s1", 9), "en"))
            XCTAssertEqual(m.ctl.state.messages.filter { $0.role == "respondent" }.count, 1)
            XCTAssertFalse(m.ctl.state.pending); XCTAssertFalse(m.ctl.state.local); XCTAssertEqual(m.ctl.state.input?.id, "s3")
        }
    }

    func testGivesUpAfterTwoBusyRetriesAndGoesLocal() async {
        await onMain {
            let m = self.make(reply(1, input: S1j), reply(2, busy: true), reply(3, busy: true), reply(4, busy: true))
            await m.ctl.start()
            _ = await m.ctl.answer(num("s1", 9))
            XCTAssertEqual(m.t.sent.count, 4)
            XCTAssertTrue(m.ctl.state.local); XCTAssertFalse(m.ctl.state.pending)
            XCTAssertEqual(m.ctl.state.input?.id, "s3")
        }
    }

    func testSkipIsRefusedOnARequiredInputAndSentOnAnOptionalOne() async {
        await onMain {
            let m = self.make(reply(1, input: S1j), reply(2, input: followup("f", required: false)), reply(3, input: S3j))
            await m.ctl.start()
            await m.ctl.skip()
            XCTAssertEqual(m.t.sent.count, 1)
            _ = await m.ctl.answer(num("s1", 9))
            await m.ctl.skip()
            XCTAssertEqual(m.t.sent[2].action, "skip"); XCTAssertEqual(m.t.sent[2].turn, 2)
            XCTAssertEqual(m.ctl.state.messages.filter { $0.role == "respondent" }.count, 1)
            XCTAssertEqual(m.ctl.state.input?.id, "s3")
        }
    }

    func testEndMarksDoneAndEndedByRespondentEvenIfTheTransportRejects() async {
        await onMain {
            let m = self.make(reply(1, input: S1j), Boom())
            await m.ctl.start()
            m.ctl.end()
            await settle()
            XCTAssertEqual(m.t.sent[1].action, "end")
            let s = m.ctl.state
            XCTAssertTrue(s.done); XCTAssertTrue(s.endedByRespondent); XCTAssertFalse(s.local)
            XCTAssertFalse(m.ctl.result().completed)
        }
    }

    func testEndWhilePendingIsImmediateAndTheInFlightReplyIsIgnored() async {
        await onMain {
            let gate = Gate()
            let m = self.make(reply(1, input: S1j), gate, reply(1))
            await m.ctl.start()
            let p = Task { await m.ctl.answer(num("s1", 9)) }
            await settle()
            m.ctl.end()
            XCTAssertTrue(m.ctl.state.done); XCTAssertTrue(m.ctl.state.endedByRespondent)
            gate.complete(reply(9, "late", input: S3j))
            _ = await p.value
            await settle()
            XCTAssertEqual(self.actions(m.t), ["resume", "answer", "end"])
            XCTAssertFalse(m.ctl.state.messages.map(\.text).contains("late"))
            XCTAssertTrue(m.ctl.state.done); XCTAssertNil(m.ctl.state.input); XCTAssertFalse(m.ctl.state.pending)
        }
    }

    func testALateProbeReplyAfterTheTimeoutIsCancelled() async {
        await onMain {
            var cancelled = false
            let gate = Gate()
            let r = await bounded(ms: 20) { _ = try await gate.wait(); cancelled = Task.isCancelled; return 1 }
            XCTAssertNil(r)
            gate.complete(reply(1))
            await settle()
            XCTAssertTrue(cancelled)
        }
    }

    func testTransportFailureMidConversationContinuesLocallyWithTheNextVisiblePredefinedStep() async {
        await onMain {
            let m = self.make(reply(1, input: S1j), Boom())
            await m.ctl.start()
            _ = await m.ctl.answer(num("s1", 9))
            let s = m.ctl.state
            XCTAssertTrue(s.local)
            XCTAssertEqual(s.input?.id, "s3") // s2 hidden by showIf
            XCTAssertEqual(s.messages.map(\.text), ["9", "Q s3"])
            XCTAssertEqual(s.answered, 1); XCTAssertEqual(s.total, 2)
            _ = await m.ctl.answer(num("s3", 5))
            m.ctl.end()
            await settle()
            XCTAssertEqual(m.t.sent.count, 2)
        }
    }

    func testGoingLocalAfterASkippedProbeDropsItAndDoesNotRepeatAQuestionAlreadyShown() async {
        await onMain {
            let m = self.make(reply(1, "Q s1", input: probeJson()), Boom())
            await m.ctl.start()
            await m.ctl.skip()
            XCTAssertTrue(m.ctl.state.local); XCTAssertEqual(m.ctl.state.input?.id, "s1")
            XCTAssertEqual(m.ctl.state.messages.bare, [nia("Q s1")])
        }
    }

    func testTransportFailureOnStartRunsTheWholeFormLocallyWelcomeFirst() async {
        await onMain {
            let m = self.make(Boom(), config: ConversationConfig(mode: "conversational", welcomeMessage: "Welcome"))
            await m.ctl.start()
            let s = m.ctl.state
            XCTAssertTrue(s.local); XCTAssertFalse(s.pending); XCTAssertFalse(s.done)
            XCTAssertEqual(s.messages.bare, [nia("Welcome"), nia("Q s1")])
            XCTAssertEqual(s.input?.id, "s1")
            XCTAssertEqual(s.answered, 0); XCTAssertEqual(s.total, 2)
            XCTAssertEqual(m.t.sent.count, 1)
        }
    }

    func testLocalModeFinishesWithTheCompletionMessageAndDone() async {
        await onMain {
            let m = self.make(Boom(), c: content([S1j], thanks: "Cheers"))
            await m.ctl.start()
            _ = await m.ctl.answer(num("s1", 8))
            let s = m.ctl.state
            XCTAssertTrue(s.done); XCTAssertNil(s.input); XCTAssertTrue(s.local)
            XCTAssertEqual(s.messages.last?.bare, nia("Cheers"))
            XCTAssertTrue(m.ctl.result().completed)
            let c = self.make(Boom(), c: content([S1j]), config: cc("All done"))
            await c.ctl.start()
            _ = await c.ctl.answer(num("s1", 8))
            XCTAssertEqual(c.ctl.state.messages.last?.bare, nia("All done"))
        }
    }

    func testLocalSkipMarksTheStepSkippedAndMovesOnRequiredCannotBeSkipped() async {
        await onMain {
            let m = self.make(Boom(), c: content([followup("o", required: false, title: "Opt"), S1j]))
            await m.ctl.start()
            await m.ctl.skip()
            XCTAssertEqual(m.ctl.state.input?.id, "s1")
            await m.ctl.skip()
            XCTAssertEqual(m.ctl.state.input?.id, "s1")
        }
    }

    func testResultCarriesAnswersConversationIdAndCompleted() async {
        await onMain {
            let m = self.make(reply(1, input: S1j), reply(1, input: S3j), reply(1, done: true))
            await m.ctl.start()
            _ = await m.ctl.answer(num("s1", 9))
            _ = await m.ctl.answer(num("s3", 7))
            let r = m.ctl.result()
            XCTAssertEqual(r.answers, [num("s1", 9), num("s3", 7)])
            XCTAssertTrue(r.completed); XCTAssertEqual(r.conversationId, "cid-12345"); XCTAssertGreaterThanOrEqual(r.durationMs, 0)
            let b = self.make(reply(1, input: S1j))
            await b.ctl.start()
            b.ctl.end()
            XCTAssertFalse(b.ctl.result().completed)
        }
    }

    func testAcceptsAnInputStepTheFormDoesNotKnowAndValidatesAgainstIt() async {
        await onMain {
            let extra = stepJson("x1", #","max":7"#, kind: "star", title: "Stars")
            let m = self.make(reply(1, input: extra), reply(1, done: true))
            await m.ctl.start()
            _ = await m.ctl.answer(Answer("x1", "star", .num(8)))
            XCTAssertEqual(m.t.sent.count, 1)
            _ = await m.ctl.answer(Answer("x1", "star", .num(7)))
            XCTAssertEqual(m.t.sent.count, 2)
            XCTAssertEqual(m.ctl.result().answers.count, 1)
        }
    }

    func testStoresAProbeAnswerUnderItsProbeId() async {
        await onMain {
            let m = self.make(reply(1, input: probeJson(title: "Why?")), reply(1, input: S3j))
            await m.ctl.start()
            _ = await m.ctl.answer(free("probe:s1:1", "slow app"))
            XCTAssertEqual(m.t.sent[1].answer, free("probe:s1:1", "slow app"))
            XCTAssertEqual(m.ctl.result().answers, [free("probe:s1:1", "slow app")])
            XCTAssertEqual(m.ctl.state.messages[0].bare, ChatMessage("respondent", "slow app"))
        }
    }

    func testNotifiesSubscribersAndStopsAfterUnsubscribe() async {
        await onMain {
            let m = self.make(reply(1, input: S1j), reply(1, input: S3j))
            var n = 0
            let off = m.ctl.subscribe { n += 1 }
            await m.ctl.start()
            XCTAssertGreaterThan(n, 0)
            off()
            n = 0
            _ = await m.ctl.answer(num("s1", 9))
            XCTAssertEqual(n, 0)
        }
    }

    // hardening

    func testABlankAnswerOnAnOptionalStepIsASkipNoBubbleNoStoredAnswerFalse() async {
        await onMain {
            let m = self.make(reply(1, input: followup("f", required: false)), reply(2, input: S3j))
            await m.ctl.start()
            let ok = await m.ctl.answer(free("f", "  "))
            XCTAssertFalse(ok)
            XCTAssertEqual(m.t.sent[1].action, "skip"); XCTAssertEqual(m.t.sent[1].turn, 1)
            XCTAssertNil(m.t.sent[1].answer)
            XCTAssertEqual(m.ctl.state.messages, [])
            XCTAssertEqual(m.ctl.result().answers, [])
        }
    }

    func testABlankAnswerOnARequiredStepSendsNothing() async {
        await onMain {
            let m = self.make(reply(1, input: followup("f", required: true)))
            await m.ctl.start()
            let ok = await m.ctl.answer(free("f", ""))
            XCTAssertFalse(ok)
            XCTAssertEqual(m.t.sent.count, 1)
        }
    }

    func testCanSkipTracksOptionalRequiredPendingAndDone() async {
        await onMain {
            let gate = Gate()
            let m = self.make(reply(1, input: followup("f", required: false)), gate, reply(3, input: followup("f", required: false)))
            XCTAssertFalse(m.ctl.state.canSkip)
            await m.ctl.start()
            XCTAssertTrue(m.ctl.state.canSkip)
            let p = Task { await m.ctl.skip() }
            await settle()
            XCTAssertFalse(m.ctl.state.canSkip) // pending
            gate.complete(reply(2, input: S1j))
            await p.value
            XCTAssertEqual(m.ctl.state.input?.id, "s1")
            XCTAssertFalse(m.ctl.state.canSkip) // nps, no `required`
            _ = await m.ctl.answer(num("s1", 5))
            m.ctl.end()
            XCTAssertFalse(m.ctl.state.canSkip) // done
        }
    }

    func testAnswerResolvesTrueWhenAcceptedAndFalseForEveryIgnoreReason() async {
        await onMain {
            let m = self.make(reply(1, input: S1j), reply(1, done: true))
            var ok = await m.ctl.answer(num("s1", 9)); XCTAssertFalse(ok) // no input
            await m.ctl.start()
            ok = await m.ctl.answer(num("s3", 9)); XCTAssertFalse(ok) // wrong step
            ok = await m.ctl.answer(num("s1", 99)); XCTAssertFalse(ok) // invalid
            let first = Task { await m.ctl.answer(num("s1", 9)) }
            await settle(1)
            ok = await m.ctl.answer(num("s1", 8)); XCTAssertFalse(ok) // pending
            let accepted = await first.value; XCTAssertTrue(accepted)
            ok = await m.ctl.answer(num("s1", 9)); XCTAssertFalse(ok) // done
        }
    }

    func testASynchronouslyThrowingTransportGoesLocalWithoutRejecting() async {
        await onMain {
            let ctl = ConversationController(content: FORM, handle: ConversationHandle(config: cfgC, transport: { _ in throw Boom() }, conversationId: "cid-12345"),
                                             locale: nil, timing: fastTiming)
            await ctl.start()
            XCTAssertTrue(ctl.state.local); XCTAssertFalse(ctl.state.pending)
            ctl.end()
        }
    }

    func testAMalformedReplyGoesLocal() async {
        await onMain {
            let m = self.make(jobj("{\"input\":\(S1j),\"next_turn\":1}"))
            await m.ctl.start()
            XCTAssertTrue(m.ctl.state.local); XCTAssertFalse(m.ctl.state.pending)
            XCTAssertEqual(m.ctl.state.input?.id, "s1")
        }
    }

    func testATransportThatNeverSettlesGoesLocalAfterTheTurnTimeout() async {
        await onMain {
            let m = self.make(Hang())
            let p = Task { await m.ctl.start() }
            await settle(80)
            XCTAssertFalse(m.ctl.state.local); XCTAssertTrue(m.ctl.state.pending)
            await p.value
            XCTAssertTrue(m.ctl.state.local); XCTAssertFalse(m.ctl.state.pending)
        }
    }

    func testABlockingCallThatIgnoresCancellationIsStillBoundedByTheTimeout() async {
        await onMain {
            let gate = Gate() // never released until the end: a blocked HTTP call
            let m = self.make(gate)
            let t0 = Date()
            await m.ctl.start()
            XCTAssertLessThan(Date().timeIntervalSince(t0), 1.5)
            XCTAssertTrue(m.ctl.state.local)
            gate.complete(reply(1, "late", input: S3j)) // a late reply changes nothing
            await settle()
            XCTAssertEqual(m.ctl.state.input?.id, "s1")
        }
    }

    func testEndDuringAnInFlightRequestIsSentAfterItSettlesWithTheLatestTurn() async {
        await onMain {
            let gate = Gate()
            let m = self.make(reply(1, input: S1j), gate, reply(1))
            await m.ctl.start()
            let p = Task { await m.ctl.answer(num("s1", 9)) }
            await settle()
            m.ctl.end()
            await settle()
            XCTAssertEqual(self.actions(m.t), ["resume", "answer"])
            gate.complete(reply(7))
            _ = await p.value
            await waitUntil { self.actions(m.t).count == 3 }
            XCTAssertEqual(self.actions(m.t), ["resume", "answer", "end"])
            if m.t.sent.count > 2 { XCTAssertEqual(m.t.sent[2].turn, 7) }
        }
    }

    func testAResumeReplySeedsAnswersAndSkippedLocalModeDoesNotAskThemAgain() async {
        await onMain {
            var r = reply(3, input: probeJson(title: "More?"))
            r["answers"] = jobj(#"{"a":[{"stepId":"s1","kind":"nps","value":9},{"stepId":"zz","kind":"nps","value":1},{"stepId":"s3","kind":"nps","value":99}]}"#)["a"]
            r["skipped"] = ["s3"]
            let m = self.make(r, Boom())
            await m.ctl.start()
            XCTAssertEqual(m.ctl.result().answers, [num("s1", 9)])
            await m.ctl.skip() // fails -> local: s1 answered, s2 hidden, s3 skipped
            let s = m.ctl.state
            XCTAssertTrue(s.local); XCTAssertTrue(s.done); XCTAssertNil(s.input)
        }
    }

    func testASecondStepWithTheSameTitleAsASkippedOneStillShowsItsQuestion() async {
        await onMain {
            let m = self.make(Boom(), c: content([followup("o", required: false, title: "Same?"), followup("p", required: false, title: "Same?")]))
            await m.ctl.start()
            await m.ctl.skip()
            XCTAssertEqual(m.ctl.state.input?.id, "p")
            XCTAssertEqual(m.ctl.state.messages.filter { $0.text == "Same?" }.count, 2)
        }
    }

    func testAMalformedSeededAnswerIsDroppedWithoutGoingLocalTheLastEntryPerStepWins() async {
        await onMain {
            var r = reply(2, input: S3j)
            r["answers"] = jobj(#"{"a":[{"stepId":"s1","kind":"nps","value":9},{"stepId":"s2","kind":"followup"},null,{"stepId":"s1","kind":"nps","value":7}]}"#)["a"]
            let m = self.make(r)
            await m.ctl.start()
            XCTAssertFalse(m.ctl.state.local)
            XCTAssertEqual(m.ctl.result().answers, [num("s1", 7)])
        }
    }

    func testAMalformedAnswerFromARendererResolvesFalseAndSendsNothing() async {
        await onMain {
            let m = self.make(reply(1, input: followup("f", required: false)))
            await m.ctl.start()
            let ok = await m.ctl.answer(Answer("f", "followup", .num(1)))
            XCTAssertFalse(ok)
            XCTAssertEqual(m.t.sent.count, 1)
            XCTAssertEqual(m.ctl.state.messages, [])
            XCTAssertFalse(m.ctl.state.pending)
        }
    }

    func testEndResolvesAtOnceWhenTheInFlightRequestHangsAndSendsNoEndAfterTheTimeout() async {
        await onMain {
            let m = self.make(reply(1, input: S1j), Hang())
            await m.ctl.start()
            let p = Task { await m.ctl.answer(num("s1", 9)) }
            await settle()
            m.ctl.end()
            XCTAssertTrue(m.ctl.state.done); XCTAssertTrue(m.ctl.state.endedByRespondent)
            _ = await p.value
            await settle()
            XCTAssertEqual(self.actions(m.t), ["resume", "answer"])
            let s = m.ctl.state
            XCTAssertTrue(s.done); XCTAssertTrue(s.endedByRespondent); XCTAssertFalse(s.local)
        }
    }

    // dispose

    func testDisposeIgnoresAReplyThatArrivesLaterNoStateChangeNoNotificationNoRequest() async {
        await onMain {
            let gate = Gate()
            let m = self.make(reply(1, input: S1j), gate)
            await m.ctl.start()
            let p = Task { await m.ctl.answer(num("s1", 9)) }
            await settle()
            var n = 0
            _ = m.ctl.subscribe { n += 1 }
            let before = m.ctl.state
            m.ctl.dispose()
            gate.complete(reply(5, "late", input: S3j))
            _ = await p.value
            await settle()
            XCTAssertEqual(m.ctl.state.messages, before.messages)
            XCTAssertEqual(m.ctl.state.input?.id, before.input?.id)
            XCTAssertEqual(m.ctl.state.pending, before.pending)
            XCTAssertEqual(n, 0)
            XCTAssertEqual(self.actions(m.t), ["resume", "answer"])
        }
    }

    func testDisposeReleasesABlockedCallAtOnceInsteadOfWaitingForTheTimeout() async {
        await onMain {
            let gate = Gate()
            let m = self.make(reply(1, input: S1j), gate)
            await m.ctl.start()
            let p = Task { await m.ctl.answer(num("s1", 9)) }
            await settle(20)
            let t0 = Date()
            m.ctl.dispose()
            _ = await p.value
            XCTAssertLessThan(Date().timeIntervalSince(t0), 0.1)
            gate.complete(reply(1))
        }
    }

    func testDisposeStopsABusyRetryWaitAndLeavesNoTimers() async {
        await onMain {
            let m = self.make(reply(1, input: S1j), reply(2, busy: true), reply(1, input: S3j))
            let slow = ConversationController(content: FORM, handle: ConversationHandle(config: cfgC, transport: m.t.transport, conversationId: "c"),
                                               locale: nil, timing: ConversationTiming(turnTimeoutMs: 200 * settleScale, busyRetryMs: 150, probeTimeoutMs: 200 * settleScale))
            await slow.start()
            let p = Task { await slow.answer(num("s1", 9)) }
            await settle(40)
            slow.dispose()
            _ = await p.value
            await settle(250)
            XCTAssertEqual(m.t.sent.count, 2)
        }
    }

    func testDisposeSendsNoEndMakesLaterCallsNoOpsKeepsResultAndIsIdempotent() async {
        await onMain {
            let m = self.make(reply(1, input: S1j), reply(2, input: S3j))
            await m.ctl.start()
            _ = await m.ctl.answer(num("s1", 9))
            m.ctl.dispose(); m.ctl.dispose()
            m.ctl.end()
            let ok = await m.ctl.answer(num("s3", 5))
            XCTAssertFalse(ok)
            await m.ctl.skip()
            await m.ctl.start()
            await settle()
            XCTAssertEqual(self.actions(m.t), ["resume", "answer"])
            XCTAssertFalse(m.ctl.state.done); XCTAssertFalse(m.ctl.state.endedByRespondent)
            let r = m.ctl.result()
            XCTAssertEqual(r.answers, [num("s1", 9)]); XCTAssertFalse(r.completed)
        }
    }

    func testAfterEndStillDeliversOneEndRequestAfterTheInFlightTurnWithItsNextTurn() async {
        await onMain {
            let gate = Gate()
            let m = self.make(reply(1, input: S1j), gate, reply(1))
            await m.ctl.start()
            let p = Task { await m.ctl.answer(num("s1", 9)) }
            await settle()
            var n = 0
            _ = m.ctl.subscribe { n += 1 }
            m.ctl.end()
            n = 0
            m.ctl.dispose()
            XCTAssertEqual(self.actions(m.t), ["resume", "answer"])
            gate.complete(reply(8, "late"))
            _ = await p.value
            await settle()
            XCTAssertEqual(self.actions(m.t), ["resume", "answer", "end"])
            XCTAssertEqual(m.t.sent[2].turn, 8)
            XCTAssertEqual(n, 0)
        }
    }

    func testAfterEndSendsTheEndRequestOnceWhenNothingIsInFlight() async {
        await onMain {
            let m = self.make(reply(3, input: S1j), reply(1))
            await m.ctl.start()
            m.ctl.end()
            m.ctl.dispose()
            await settle()
            XCTAssertEqual(self.actions(m.t), ["resume", "end"])
            XCTAssertEqual(m.t.sent[1].turn, 3)
        }
    }

    func testAfterEndSendsNoEndWhenTheInFlightRequestRejects() async {
        await onMain {
            let gate = Gate()
            let m = self.make(reply(1, input: S1j), gate)
            await m.ctl.start()
            let p = Task { await m.ctl.answer(num("s1", 9)) }
            await settle()
            m.ctl.end()
            m.ctl.dispose()
            gate.fail()
            let ok = await p.value
            XCTAssertTrue(ok)
            await settle()
            XCTAssertEqual(self.actions(m.t), ["resume", "answer"])
        }
    }

    func testGoesLocalOnAReplyTheTransportShouldNotHaveSentNoProgress() async {
        await onMain {
            let m = self.make(jobj(#"{"messages":[],"done":false,"next_turn":1}"#))
            await m.ctl.start()
            XCTAssertTrue(m.ctl.state.local)
            XCTAssertEqual(m.ctl.state.input?.id, "s1")
        }
    }

    // setLanguage

    func testSetLanguageLaterRequestsCarryTheNewLocale() async {
        await onMain {
            let m = self.make(reply(1, input: S1j), reply(1, input: S3j))
            await m.ctl.start()
            m.ctl.setLanguage("bn", content: FORM)
            _ = await m.ctl.answer(num("s1", 9))
            XCTAssertEqual(m.t.sent[1].locale, "bn")
        }
    }

    func testSetLanguageLocalModeAsksTheNextQuestionFromTheNewContent() async {
        await onMain {
            let m = self.make(reply(1, input: S1j), Boom())
            await m.ctl.start()
            m.ctl.setLanguage("bn", content: content([S1j, S2j, nps("s3", title: "বাংলা")]))
            _ = await m.ctl.answer(num("s1", 9))
            let s = m.ctl.state
            XCTAssertTrue(s.local); XCTAssertEqual(s.input?.title, "বাংলা"); XCTAssertEqual(s.messages.last?.text, "বাংলা")
        }
    }

    func testSetLanguageLocalModeEndsWithTheCompletionMessageOfTheNewConfig() async {
        await onMain {
            let m = self.make(Boom(), c: content([S1j]), config: cc("All done"))
            await m.ctl.start()
            m.ctl.setLanguage("bn", content: content([S1j]), config: cc("সব শেষ"))
            _ = await m.ctl.answer(num("s1", 8))
            XCTAssertEqual(m.ctl.state.messages.last?.bare, nia("সব শেষ"))
        }
    }

    private static let BN = content([nps("s1", title: "প্রথম"), nps("s3", title: "তৃতীয়")])
    private static let cfgBn = ConversationConfig(mode: "conversational", welcomeMessage: "স্বাগতম", completionMessage: "শেষ")
    private static let cfgEn = ConversationConfig(mode: "conversational", welcomeMessage: "Welcome", completionMessage: "Done")

    func testSetLanguageServerInputWithAPredefinedIdIsSwappedProbesStay() async {
        await onMain {
            let m = self.make(reply(1, input: S1j), reply(2, input: probeJson("probe:1", title: "Why?")))
            await m.ctl.start()
            m.ctl.setLanguage("bn", content: content([nps("s1", title: "নতুন")]))
            XCTAssertEqual(m.ctl.state.input?.title, "নতুন")
            _ = await m.ctl.answer(num("s1", 9))
            let probe = m.ctl.state.input
            m.ctl.setLanguage("en", content: content([S1j]))
            XCTAssertEqual(m.ctl.state.input?.id, probe?.id)
            XCTAssertEqual(m.ctl.state.input?.title, probe?.title)
        }
    }

    func testSetLanguageWelcomeQuestionsAndAnswersReRenderProbesStay() async {
        await onMain {
            let m = self.make(reply(1, "Welcome", "Q s1", input: S1j), reply(2, "Why 9?", input: probeJson("probe:1", title: "Why 9?")),
                              reply(3, "Q s3", input: S3j), c: content([S1j, S3j]), config: ControllerTests.cfgEn)
            await m.ctl.start()
            _ = await m.ctl.answer(num("s1", 9))
            _ = await m.ctl.answer(free("probe:1", "because"))
            m.ctl.setLanguage("bn", content: ControllerTests.BN, config: ControllerTests.cfgBn)
            XCTAssertEqual(m.ctl.state.messages.map(\.text), ["স্বাগতম", "প্রথম", "9", "Why 9?", "because", "তৃতীয়"])
            XCTAssertEqual(m.ctl.state.input?.title, "তৃতীয়")
        }
    }

    func testSetLanguageAChoiceAnswerTakesItsLabelFromTheNewLanguage() async {
        await onMain {
            func csat(_ l: String) -> String { stepJson("s1", ",\"labels\":\(l)", kind: "csat", title: "Q") }
            let en = csat(#"["Bad","Ok","Good","Great","Best"]"#)
            let m = self.make(reply(1, "Q", input: en), reply(2), c: content([en]))
            await m.ctl.start()
            _ = await m.ctl.answer(Answer("s1", "csat", .num(2)))
            XCTAssertEqual(m.ctl.state.messages.last?.text, "Ok")
            m.ctl.setLanguage("bn", content: content([csat(#"["খারাপ","ঠিক","ভালো","দারুণ","সেরা"]"#)]))
            XCTAssertEqual(m.ctl.state.messages.last?.text, "ঠিক")
        }
    }

    func testSetLanguageTheCompletionMessageReRenders() async {
        await onMain {
            let m = self.make(Boom(), c: content([S1j]), config: ControllerTests.cfgEn)
            await m.ctl.start()
            _ = await m.ctl.answer(num("s1", 8))
            XCTAssertEqual(m.ctl.state.messages.last?.text, "Done")
            m.ctl.setLanguage("bn", content: content([S1j]), config: ControllerTests.cfgBn)
            XCTAssertEqual(m.ctl.state.messages.last?.text, "শেষ")
        }
    }

    func testSetLanguageARestoredTranscriptIsTaggedSoItReRendersToo() async {
        await onMain {
            let tr = [nia("Welcome"), nia("Q s1"), ChatMessage("respondent", "9"), nia("Why?")]
            var r = reply(1, input: S3j); r["transcript"] = self.transcriptJson(tr)
            r["answers"] = [jobj(#"{"stepId":"s1","kind":"nps","value":9}"#)]
            let m = self.make(r, c: content([S1j, S3j]), config: ControllerTests.cfgEn)
            await m.ctl.start()
            m.ctl.setLanguage("bn", content: ControllerTests.BN, config: ControllerTests.cfgBn)
            XCTAssertEqual(m.ctl.state.messages.map(\.text), ["স্বাগতম", "প্রথম", "9", "Why?"])
        }
    }

    @MainActor private func localOn(_ c: FeedbackContent) async -> ConversationController {
        let m = make(reply(1, input: S1j), Boom(), c: c)
        await m.ctl.start()
        _ = await m.ctl.answer(num("s1", 9))
        return m.ctl
    }

    func testSetLanguageInLocalModeSwapsTheCurrentPredefinedStepOnce() async {
        await onMain {
            let ctl = await self.localOn(content([S1j, S3j]))
            XCTAssertEqual(ctl.state.input?.id, "s3")
            var n = 0
            _ = ctl.subscribe { n += 1 }
            ctl.setLanguage("bn", content: content([S1j, nps("s3", title: "তৃতীয়")]))
            XCTAssertEqual(ctl.state.input?.title, "তৃতীয়")
            XCTAssertEqual(n, 1)
        }
    }

    func testSetLanguageInLocalModeKeepsTheInputWhenTheNewContentLacksThatStep() async {
        await onMain {
            let ctl = await self.localOn(content([S1j, S3j]))
            var n = 0
            _ = ctl.subscribe { n += 1 }
            ctl.setLanguage("bn", content: content([S1j]))
            XCTAssertEqual(ctl.state.input?.title, "Q s3")
            XCTAssertEqual(n, 0)
        }
    }

    func testSetLanguageCanSkipFollowsTheSwappedInStep() async {
        await onMain {
            let ctl = await self.localOn(content([S1j, nps("s3", #","required":true"#)]))
            XCTAssertFalse(ctl.state.canSkip)
            ctl.setLanguage("bn", content: content([S1j, nps("s3", #","required":false"#)]))
            XCTAssertTrue(ctl.state.canSkip)
        }
    }

    func testSetLanguageNoNotificationAndNoThrowAfterDisposeOrWhenDone() async {
        await onMain {
            let ctl = await self.localOn(content([S1j, S3j]))
            var n = 0
            _ = ctl.subscribe { n += 1 }
            ctl.dispose()
            ctl.setLanguage("bn", content: content([S1j, S3j]))
            XCTAssertEqual(n, 0)
            let done = await self.localOn(content([S1j]))
            XCTAssertTrue(done.state.done)
            var n2 = 0
            _ = done.subscribe { n2 += 1 }
            done.setLanguage("bn", content: content([S1j]))
            XCTAssertEqual(n2, 0)
        }
    }

    // native-only

    func testUnparseableInputGoesLocal() async {
        await onMain {
            let m = self.make(reply(1, "Hi", input: #"{"id":"x","kind":"hologram","title":"?"}"#))
            await m.ctl.start()
            XCTAssertTrue(m.ctl.state.local)
            XCTAssertEqual(m.ctl.state.input?.id, "s1") // first predefined step
            _ = await m.ctl.answer(num("s1", 9))
            XCTAssertEqual(m.t.sent.count, 1) // never called again
        }
    }

    func testLocaleSentOnEveryRequestAndChangesAfterSetLanguage() async {
        await onMain {
            let m = self.make(reply(1, "Hi", input: S1j), reply(2, "Ok", input: S3j), reply(3, done: true), locale: "bn")
            await m.ctl.start()
            XCTAssertEqual(m.t.sent[0].locale, "bn")
            m.ctl.setLanguage("ar", content: FORM)
            _ = await m.ctl.answer(num("s1", 9))
            XCTAssertEqual(m.t.sent[1].locale, "ar")
            XCTAssertEqual(m.ctl.state.messages.map(\.text), ["Hi", "9", "Ok"]) // earlier messages unchanged
        }
    }

    func testRequestOmitsALocaleThatIsNilOrEmpty() async {
        await onMain {
            let m = self.make(reply(1, input: S1j), reply(2, input: S3j), locale: nil)
            await m.ctl.start()
            m.ctl.setLanguage("", content: FORM)
            _ = await m.ctl.answer(num("s1", 9))
            XCTAssertNil(m.t.sent[0].locale); XCTAssertNil(m.t.sent[1].locale)
        }
    }

    func testSetLanguageReplacesTheHandleConfigWhenGiven() async {
        await onMain {
            let m = self.make(Boom(), c: content([S1j]))
            await m.ctl.start()
            m.ctl.setLanguage("bn", content: content([S1j]), config: cc("bn-done"))
            _ = await m.ctl.answer(num("s1", 1))
            XCTAssertEqual(m.ctl.state.messages.last?.text, "bn-done")
        }
    }
}

extension Fake {
    func load(_ script: [Any]) { replace(script) }
}
