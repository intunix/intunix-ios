import XCTest
@testable import Intunix

private final class Counting {
    var remembered: String?, developer: String?
    var reads = 0
    var remembers: [String] = []
    init(_ remembered: String? = nil, _ developer: String? = nil) { self.remembered = remembered; self.developer = developer }
    var source: LocaleSource {
        LocaleSource(developer: { self.reads += 1; return self.developer }, remembered: { self.reads += 1; return self.remembered },
                     remember: { self.remembers.append($0) })
    }
}

final class FormLanguageTests: XCTestCase {
    private func raw(_ extra: String) -> JSONObject {
        json(##"{"kind":"feedback","brand":{"color":"#2F9461"},"steps":[{"id":"s1","kind":"nps","title":"One"}]\##(extra)}"##)
    }
    private var multi: JSONObject {
        raw(#","defaultLanguage":"en","languages":["en","bn","ar"],"translations":{"bn":{"steps":{"s1":{"title":"bOne"}}},"ar":{"steps":{"s1":{"title":"aOne"}}}}"#)
    }

    func testPlainForm() {
        let c = Counting("bn", "bn")
        let f = FormLanguage(raw: raw(#","defaultLanguage":"en""#), source: c.source, device: ["bn"])
        XCTAssertFalse(f.multi); XCTAssertFalse(f.decorated); XCTAssertNil(f.texts)
        XCTAssertEqual(c.reads, 0)
        XCTAssertEqual(f.content.steps.map(\.title), ["One"])
    }

    func testRememberedBeatsDeveloperBeatsDevice() {
        let f = FormLanguage(raw: multi, source: Counting("ar", "bn").source, device: ["bn-BD"])
        XCTAssertEqual(f.lang, "ar"); XCTAssertTrue(f.rtl)
        XCTAssertEqual(FormLanguage(raw: multi, source: Counting(nil, "bn").source, device: ["ar"]).lang, "bn")
        XCTAssertEqual(FormLanguage(raw: multi, source: Counting().source, device: ["bn-BD"]).lang, "bn")
    }

    func testSingleLanguageBengaliIsDecorated() {
        let c = Counting()
        let f = FormLanguage(raw: raw(#","defaultLanguage":"bn""#), source: c.source, device: [])
        XCTAssertTrue(f.decorated); XCTAssertFalse(f.multi)
        XCTAssertEqual(f.texts?.next, "পরবর্তী")
        XCTAssertEqual(c.reads, 0)
    }

    func testSwitchRemembersAndRelocalizes() {
        let c = Counting()
        let f = FormLanguage(raw: multi, source: c.source, device: [])
        XCTAssertEqual(f.content.steps[0].title, "One")
        XCTAssertTrue(f.switchTo("bn"))
        XCTAssertEqual(c.remembers, ["bn"])
        XCTAssertEqual(f.content.steps[0].title, "bOne")
        XCTAssertFalse(f.switchTo("bn"))
        XCTAssertFalse(f.switchTo("fr"))
        XCTAssertEqual(c.remembers.count, 1)
    }

    func testDecorateAddsLanguageOnlyWhenMulti() {
        let r = FeedbackResponse(answers: [], completed: true, durationMs: 5)
        XCTAssertEqual(FormLanguage(raw: multi, source: Counting().source, device: []).decorate(r).language, "en")
        XCTAssertNil(FormLanguage(raw: raw(""), source: nil, device: []).decorate(r).language)
    }
}

private final class NoPresenter: FormPresenter {
    nonisolated init() {}
    func present(_ exp: Experience, _ content: FeedbackContent, _ callbacks: RenderCallbacks) async -> ExperienceResult? { nil }
}

// Linux XCTest cannot discover actor-isolated methods, so each test hops to the main actor itself.
final class LanguageStateTests: XCTestCase {
    private let store = MemoryStore()
    private let presenter = NoPresenter()
    @MainActor private func client() -> IntunixClient {
        IntunixClient(cfg: ClientConfig(apiKey: "k", apiHost: "http://localhost", registerAll: false, register: [], flushIntervalMs: 60_000,
                                        maxQueueSize: 100, screenTriggerDelayMs: 0, disableEventApi: true, sdkVersion: "test", locale: "en"),
                      store: store, presenter: presenter, log: { _ in })
    }

    func testLanguageStoreRoundTripsUnderItsKey() async {
        await MainActor.run {
            let s = LanguageStore(store)
            XCTAssertNil(s.remembered())
            s.remember("bn")
            XCTAssertEqual(s.remembered(), "bn")
            XCTAssertEqual(store.get("intunix:lang"), "bn")
            s.clear()
            XCTAssertNil(s.remembered())
        }
    }

    func testSetLocaleChangesDeveloperAndRemembers() async {
        await MainActor.run {
            let c = client()
            XCTAssertEqual(c.localeSource().developer(), "en")
            c.setLocale("bn")
            let src = c.localeSource()
            XCTAssertEqual(src.developer(), "bn")
            XCTAssertEqual(src.remembered(), "bn")
            XCTAssertEqual(c.localeSource(perForm: "ar").developer(), "ar") // a per-form locale wins
        }
    }

    func testResetClearsRememberedAndRestoresInitLocale() async {
        await MainActor.run {
            let c = client()
            c.setLocale("bn")
            c.localeSource().remember("ar")
            c.reset()
            XCTAssertNil(store.get("intunix:lang"))
            XCTAssertNil(c.localeSource().remembered())
            XCTAssertEqual(c.localeSource().developer(), "en")
        }
    }
}
