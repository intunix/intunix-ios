import XCTest
@testable import Intunix

private final class Source {
    var reads = 0
    var remembered: [String] = []
    let developer: String?
    init(developer: String? = nil) { self.developer = developer }
    var source: LocaleSource {
        LocaleSource(developer: { self.reads += 1; return self.developer }, remembered: { self.reads += 1; return nil }, remember: { self.remembered.append($0) })
    }
}

@MainActor private final class Rig {
    var results: [ExperienceResult] = []
    var reviews: [String] = []
    let host: FormController
    init(_ raw: JSONObject, _ src: Source = Source(), device: [String] = ["en"], conversation: ConversationConfig? = nil, wire: Fake? = nil) {
        let handle = conversation.map { ConversationHandle(config: $0, transport: wire!.transport, conversationId: "conv-1") }
        var sink: ((ExperienceResult) -> Void)?
        var reviewSink: ((String) -> Void)?
        let cb = RenderCallbacks(onImpression: {}, onResponse: { _ in }, onDismiss: {}, clientResponseId: "r",
                                 onReviewEvent: { reviewSink?($0.name) }, locale: src.source, conversation: handle)
        host = FormController(exp: parseExperience(raw)!, callbacks: cb, openUrl: { _ in true }, device: device) { sink?($0) }
        sink = { [unowned self] in results.append($0) }
        reviewSink = { [unowned self] in reviews.append($0) }
    }
}

private let langs = #""defaultLanguage":"en","languages":["en","bn","ar"],"translations":{"bn":{"steps":{"nps":{"title":"bn nps"},"csat":{"title":"bn csat"}},"thanks":{"title":"bn thanks"}},"ar":{"steps":{"nps":{"title":"ar nps"},"csat":{"title":"ar csat"}},"thanks":{"title":"ar thanks"}}}"#

private func form(multi: Bool, ai: Bool = false, top: String = "", thanks: String = #"{"title":"Thanks"}"#) -> JSONObject {
    jobj("""
    {"id":"f","type":"popup","triggers":[]\(top),"content":{"kind":"feedback","brand":{"color":"#2F9461"},"thanks":\(thanks),
    \(multi ? langs + "," : "")"steps":[
    {"id":"nps","kind":"nps","title":"en nps","required":true,"page":1\(ai ? ",\"aiFollowUp\":true" : "")},
    {"id":"csat","kind":"csat","title":"en csat","required":true,"page":2}]}}
    """)
}

private let probeJson = #"{"id":"probe:nps:1","kind":"followup","title":"Why?","input":{"type":"free"},"required":false}"#
private func csat(_ v: Int) -> Answer { Answer("csat", "csat", .num(v)) }

final class FormControllerTests: XCTestCase {
    func testPlainFormReadsNoStorageAndSendsNoLanguage() async {
        await onMain {
            let src = Source(developer: "bn")
            let r = Rig(form(multi: false), src, device: ["bn"])
            XCTAssertEqual(src.reads, 0)
            XCTAssertFalse(r.host.language.decorated)
            r.host.finish()
            XCTAssertNil(r.results.first?.response?.language)
        }
    }

    func testSwitchKeepsPageAndAnswers() async {
        await onMain {
            let src = Source()
            let h = Rig(form(multi: true), src).host
            h.onAnswer("nps", num("nps", 9)); h.submitPage()
            XCTAssertEqual(h.state().pageIndex, 1)
            h.switchLanguage("bn")
            XCTAssertEqual(h.state().pageIndex, 1)
            XCTAssertEqual(h.state().answers, [num("nps", 9)])
            XCTAssertEqual(h.state().pageSteps.first?.title, "bn csat")
            XCTAssertEqual(src.remembered, ["bn"])
        }
    }

    func testSwitchResultCarriesTheLanguage() async {
        await onMain {
            let r = Rig(form(multi: true))
            r.host.switchLanguage("bn")
            r.host.finish()
            XCTAssertEqual(r.results.first?.response?.language, "bn")
        }
    }

    func testSwitchKeepsInsertedProbe() async {
        await onMain {
            let h = Rig(form(multi: true, ai: true), conversation: ConversationConfig(mode: "enhanced"), wire: Fake(reply(1, input: probeJson))).host
            h.onAnswer("nps", num("nps", 3)); h.submitPage()
            XCTAssertTrue(h.probing)
            await settle()
            XCTAssertFalse(h.probing)
            XCTAssertEqual(h.state().pageSteps.map(\.id), ["probe:nps:1"])
            h.switchLanguage("ar")
            XCTAssertEqual(h.state().pageSteps.map(\.id), ["probe:nps:1"])
            XCTAssertEqual(h.state().pageSteps.first?.title, "Why?")
        }
    }

    func testProbeKeepsTheLanguageItWasAskedIn() async {
        await onMain {
            let gate = Gate()
            let wire = Fake(gate)
            let h = Rig(form(multi: true, ai: true), device: ["ar"], conversation: ConversationConfig(mode: "enhanced"), wire: wire).host
            h.onAnswer("nps", num("nps", 3)); h.submitPage()
            await settle()
            h.switchLanguage("bn")
            gate.complete(reply(1))
            await settle()
            XCTAssertEqual(wire.sent.map(\.locale), ["ar"])
        }
    }

    func testReviewShownOnceAcrossSwitch() async {
        await onMain {
            let review = #","reviewRequest":{"enabled":true,"platform":"custom","reviewUrl":"https://example.com/r","trigger":{"rule":"always"}}"#
            let r = Rig(form(multi: true, top: review))
            let h = r.host
            h.onAnswer("nps", num("nps", 9)); h.submitPage()
            h.onAnswer("csat", csat(5)); h.submitPage()
            XCTAssertEqual(h.state().phase, .review)
            h.review!.onShown()
            h.switchLanguage("bn")
            XCTAssertEqual(h.state().phase, .review)
            XCTAssertEqual(r.reviews.filter { $0 == "$review_request_shown" }.count, 1)
        }
    }

    func testProbeLocaleOnlyForMulti() async {
        await onMain {
            let single = Fake(reply(1))
            let a = Rig(form(multi: false, ai: true), conversation: ConversationConfig(mode: "enhanced"), wire: single).host
            a.onAnswer("nps", num("nps", 3)); a.submitPage()
            await settle()
            XCTAssertNil(single.sent.first?.locale)
            let multi = Fake(reply(1))
            let b = Rig(form(multi: true, ai: true), device: ["ar"], conversation: ConversationConfig(mode: "enhanced"), wire: multi).host
            b.onAnswer("nps", num("nps", 3)); b.submitPage()
            await settle()
            XCTAssertEqual(multi.sent.first?.locale, "ar")
        }
    }

    func testChatResultCarriesConversationIdAndLanguage() async {
        await onMain {
            let wire = Fake(reply(1, "hi", input: stepJson("nps")), reply(2, done: true))
            let r = Rig(form(multi: true, thanks: #"{"title":"T","autoCloseMs":30}"#), device: ["ar"], conversation: ConversationConfig(mode: "conversational"), wire: wire)
            r.host.impression()
            await settle()
            r.host.sendChat(num("nps", 9))
            await settle(120)
            XCTAssertTrue(r.host.chatState().done)
            XCTAssertEqual(r.results.count, 1)
            XCTAssertEqual(r.results[0].outcome, "responded")
            XCTAssertEqual(r.results[0].response?.conversationId, "conv-1")
            XCTAssertEqual(r.results[0].response?.language, "ar")
        }
    }

    func testChatEndWhilePendingDismisses() async {
        await onMain {
            let gate = Gate()
            let wire = Fake(gate, reply(2, done: true))
            let r = Rig(form(multi: true), conversation: ConversationConfig(mode: "conversational"), wire: wire)
            r.host.impression()
            await settle()
            XCTAssertTrue(r.host.chatState().pending)
            r.host.close()
            XCTAssertEqual(r.results.first?.outcome, "dismissed")
            gate.complete(reply(1))
            await settle()
            XCTAssertEqual(wire.sent.last?.action, "end")
        }
    }

    func testChatDoneStartsOneThanksTimerAndFinishesOnce() async {
        await onMain {
            let wire = Fake(reply(1, "hi", input: stepJson("nps")), reply(2, done: true))
            let r = Rig(form(multi: false, thanks: #"{"title":"T","autoCloseMs":20}"#), conversation: ConversationConfig(mode: "conversational"), wire: wire)
            r.host.impression(); r.host.impression()
            await settle()
            XCTAssertEqual(wire.sent.count, 1)
            r.host.sendChat(num("nps", 9))
            await settle(120)
            XCTAssertEqual(r.results.count, 1)
            XCTAssertNil(r.results[0].response?.language)
        }
    }

    func testPageLabelUsesBuiltinTextsOrEnglish() {
        XCTAssertEqual(pageLabel(nil, ending: false, paged: true, index: 1, count: 3), "Page 2 of 3")
        XCTAssertEqual(pageLabel(nil, ending: false, paged: false, index: 0, count: 2), "Question 1 of 2")
        XCTAssertEqual(pageLabel(nil, ending: true, paged: true, index: 0, count: 2), "Done")
        let bn = builtinTexts("bn")
        XCTAssertEqual(pageLabel(bn, ending: false, paged: true, index: 1, count: 2), "পৃষ্ঠা 2 / 2")
        XCTAssertEqual(pageLabel(bn, ending: true, paged: true, index: 1, count: 2), "সম্পন্ন")
    }

    func testClosingAChatMidAnswerEndsWithTheFreshTurn() async {
        await onMain {
            let gate = Gate()
            let wire = Fake(reply(1, input: stepJson("nps")), gate, reply(3))
            let rig = Rig(form(multi: true, ai: true), conversation: ConversationConfig(mode: "conversational"), wire: wire)
            let h = rig.host
            h.impression(); await settle()
            h.sendChat(num("nps", 9)); await settle()
            h.close()
            gate.complete(reply(2, input: stepJson("csat")))
            await settle()
            XCTAssertEqual(wire.sent.map(\.action), ["resume", "answer", "end"])
            XCTAssertEqual(wire.sent.last?.turn, 2)
            withExtendedLifetime(rig) {}
        }
    }
}
