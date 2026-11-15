import XCTest
@testable import Intunix

final class RunnerInsertTests: XCTestCase {
    private func nps(_ id: String, _ title: String? = nil, _ extra: String = "") -> Step {
        parseStep(json(#"{"id":"\#(id)","kind":"nps","title":"\#(title ?? id)"\#(extra)}"#))!
    }
    private func probe(_ id: String = "probe:s1:1") -> Step {
        parseStep(json(#"{"id":"\#(id)","kind":"followup","title":"Why?","input":{"type":"free"},"required":false}"#))!
    }
    private func probeAnswer(_ id: String = "probe:s1:1") -> Answer { Answer(id, "followup", .text(type: "free", text: "because")) }
    private func score(_ id: String, _ v: Int) -> Answer { Answer(id, "nps", .num(v)) }
    private func content(_ steps: [Step]) -> FeedbackContent { FeedbackContent(steps: steps, brand: Brand(color: "#2F9461")) }
    private func ids(_ s: [Step]) -> [String] { s.map(\.id) }
    private func runner(_ steps: Step...) -> FeedbackRunner { FeedbackRunner(content(steps), review: nil) }
    private let p1 = #","page":1"#, p2 = #","page":2"#

    func testInsertsAProbeAsTheNextPageAndAdvancesOntoIt() {
        let r = runner(nps("s1"), nps("s2"))
        r.record(score("s1", 3))
        r.insertAfter("s1", probe())
        XCTAssertEqual(r.submitPage().pageSteps[0].id, "probe:s1:1")
        XCTAssertEqual(r.answer(probeAnswer()).pageSteps[0].id, "s2")
    }

    func testIgnoresAnUnknownAnchorAndADuplicateId() {
        let r = runner(nps("s1"), nps("s2"))
        XCTAssertEqual(ids(r.insertAfter("nope", probe()).visibleSteps), ["s1", "s2"])
        r.insertAfter("s1", probe())
        XCTAssertEqual(ids(r.insertAfter("s2", probe()).visibleSteps), ["s1", "probe:s1:1", "s2"])
    }

    func testKeepsTheProbeAnswerInFinishAnswers() {
        let r = runner(nps("s1"))
        r.record(score("s1", 3))
        r.insertAfter("s1", probe())
        r.submitPage()
        r.answer(probeAnswer())
        XCTAssertEqual(r.finish().answers.map(\.stepId), ["s1", "probe:s1:1"])
    }

    func testInsertsAfterTheLastStepOfAGroupedPageAndKeepsPagedUnchanged() {
        let r = runner(nps("a", nil, p1), nps("b", nil, p1), nps("c", nil, p2))
        let s = r.insertAfter("a", probe("probe:a:1"))
        XCTAssertEqual(ids(s.visibleSteps), ["a", "b", "probe:a:1", "c"])
        XCTAssertTrue(s.paged)
        XCTAssertEqual(ids(s.pageSteps), ["a", "b"])
        XCTAssertFalse(runner(nps("a"), nps("b")).insertAfter("a", probe("probe:a:1")).paged)
    }

    func testWorksWhenTheAnchorIsOnAnEarlierPage() {
        let r = runner(nps("s1"), nps("s2"), nps("s3"))
        r.record(score("s1", 3))
        r.submitPage()
        r.insertAfter("s1", probe())
        XCTAssertEqual(ids(r.state().visibleSteps), ["s1", "probe:s1:1", "s2", "s3"])
        XCTAssertEqual(r.state().pageSteps[0].id, "s2")
    }

    func testDropsTheProbeAndItsAnswerWhenTheAnchorBecomesHidden() {
        let gated = nps("s2", nil, #","showIf":{"stepId":"s1","op":"gte","value":7}"#)
        let r = runner(nps("s1"), gated, nps("s3"))
        r.record(score("s1", 9))
        r.submitPage()
        r.record(score("s2", 5))
        r.insertAfter("s2", probe("probe:s2:1"))
        r.submitPage()
        r.record(probeAnswer("probe:s2:1"))
        r.back(); r.back()
        let s = r.record(score("s1", 2))
        XCTAssertEqual(ids(s.visibleSteps), ["s1", "s3"])
        XCTAssertEqual(s.answers.map(\.stepId), ["s1"])
    }

    func testBackFromAProbeReturnsToTheAnchorAndForwardShowsTheSameProbe() {
        let r = runner(nps("s1"), nps("s2"))
        r.record(score("s1", 3))
        r.insertAfter("s1", probe())
        r.submitPage()
        XCTAssertEqual(r.back().pageSteps[0].id, "s1")
        XCTAssertEqual(r.submitPage().pageSteps[0].id, "probe:s1:1")
    }

    func testPutsASecondProbeAfterTheFirstAlsoOnAGroupedPage() {
        let r = runner(nps("s1"), nps("s2"))
        r.insertAfter("s1", probe("probe:s1:1"))
        XCTAssertEqual(ids(r.insertAfter("s1", probe("probe:s1:2")).visibleSteps), ["s1", "probe:s1:1", "probe:s1:2", "s2"])
        let g = runner(nps("a", nil, p1), nps("b", nil, p1), nps("c", nil, p2))
        g.insertAfter("a", probe("probe:a:1"))
        XCTAssertEqual(ids(g.insertAfter("a", probe("probe:a:2")).visibleSteps), ["a", "b", "probe:a:1", "probe:a:2", "c"])
    }

    func testRemoveInsertedAfterRemovesChainedProbesAndTheirAnswersKeepingThePage() {
        let r = runner(nps("s1"), nps("s2"))
        r.record(score("s1", 3))
        r.insertAfter("s1", probe("probe:s1:1"))
        r.submitPage()
        r.record(probeAnswer("probe:s1:1"))
        r.insertAfter("probe:s1:1", probe("probe:probe:s1:1:1"))
        r.submitPage()
        r.record(probeAnswer("probe:probe:s1:1:1"))
        r.submitPage()
        r.record(score("s2", 4))
        let s = r.removeInsertedAfter("s1")
        XCTAssertEqual(ids(s.visibleSteps), ["s1", "s2"])
        XCTAssertEqual(s.pageSteps[0].id, "s2")
        XCTAssertEqual(r.finish().answers.map(\.stepId), ["s1", "s2"])
        XCTAssertEqual(ids(runner(nps("s1")).removeInsertedAfter("s1").visibleSteps), ["s1"])
    }

    func testAProbeDoesNotComeBackWhenItsAnchorIsHiddenThenShownAgain() {
        let gated = nps("s2", nil, #","showIf":{"stepId":"s1","op":"gte","value":7}"#)
        let r = runner(nps("s1"), gated)
        r.record(score("s1", 9))
        r.submitPage()
        r.insertAfter("s2", probe("probe:s2:1"))
        r.back()
        r.record(score("s1", 2))
        let s = r.record(score("s1", 9))
        XCTAssertEqual(ids(s.visibleSteps), ["s1", "s2"])
    }

    func testInsertAfterIsANoOpOnceTheRunnerLeftTheRunningPhase() {
        let r = runner(nps("s1"))
        r.answer(score("s1", 3))
        XCTAssertNotEqual(r.state().phase, .running)
        XCTAssertEqual(ids(r.insertAfter("s1", probe()).visibleSteps), ["s1"])
    }

    func testReplacesAStaleProbeWhenTheAnchorAnswerChanges() {
        let r = runner(nps("s1"), nps("s2"))
        r.record(score("s1", 3))
        r.insertAfter("s1", probe("probe:s1:1"))
        r.submitPage()
        r.record(probeAnswer("probe:s1:1"))
        r.back()
        r.record(score("s1", 8))
        r.removeInsertedAfter("s1")
        r.insertAfter("s1", probe("probe:s1:2"))
        XCTAssertEqual(ids(r.state().visibleSteps), ["s1", "probe:s1:2", "s2"])
        XCTAssertEqual(r.finish().answers.map(\.stepId), ["s1"])
    }

    // ---- setContent ----
    private var sc: FeedbackContent {
        content([nps("s1", "One"), nps("s2", "Two"),
                 nps("s3", "Three", #","showIf":{"stepId":"s2","op":"lte","value":6}"#), nps("s4", "Four")])
    }
    private func bn(_ t: (String, String)...) -> FeedbackContent { content(t.map { nps($0.0, $0.1) }) }
    private func titles(_ r: FeedbackRunner) -> [String] { r.state().pageSteps.map(\.title) }

    func testSetContentKeepsPageAnswersProbesAndConditionalStepsAndSwapsTheText() {
        let r = FeedbackRunner(sc, review: nil)
        r.answer(score("s1", 9))
        r.record(score("s2", 3))
        r.insertAfter("s2", probe("probe:s2:1"))
        XCTAssertEqual(titles(r), ["Two"])

        let s = r.setContent(bn(("s1", "bOne"), ("s2", "bTwo"), ("s3", "bThree"), ("s4", "bFour")))
        XCTAssertEqual(s.pageIndex, 1)
        XCTAssertEqual(titles(r), ["bTwo"])
        XCTAssertEqual(s.answers.map(\.stepId), ["s1", "s2"])
        XCTAssertEqual(ids(s.visibleSteps), ["s1", "s2", "probe:s2:1", "s3", "s4"])

        r.submitPage()
        XCTAssertEqual(titles(r), ["Why?"]) // the probe keeps its own text
        r.answer(probeAnswer("probe:s2:1"))
        XCTAssertEqual(titles(r), ["bThree"])
        XCTAssertEqual(r.finish().answers.map(\.stepId), ["s1", "s2", "probe:s2:1"])
    }

    func testSetContentReadsThanksFromTheNewContentAndKeepsThePhase() {
        let r = FeedbackRunner(sc, review: nil)
        r.setContent(bn(("s1", "x")))
        XCTAssertTrue(r.thanksEnabled())
        r.answer(score("s1", 9)); r.answer(score("s2", 9)); r.answer(score("s4", 9))
        XCTAssertEqual(r.state().phase, .thanks)
        XCTAssertEqual(r.setContent(sc).phase, .thanks)
    }

    func testSetContentKeepsAStepTheNewContentDoesNotHave() {
        let r = FeedbackRunner(sc, review: nil)
        r.setContent(bn(("s1", "Uno")))
        XCTAssertEqual(r.state().visibleSteps.map(\.title), ["Uno", "Two", "Four"])
    }

    func testSetContentKeepsTheOldStepWhenTheNewOneHasADifferentKind() {
        let r = FeedbackRunner(sc, review: nil)
        let star = parseStep(json(#"{"id":"s1","kind":"star","title":"Stars"}"#))!
        r.setContent(content([star]))
        XCTAssertEqual(r.state().visibleSteps[0].title, "One")
        XCTAssertEqual(r.state().visibleSteps[0].kind, "nps")
    }
}
