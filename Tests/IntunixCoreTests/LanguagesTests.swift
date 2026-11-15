import XCTest
@testable import Intunix

final class LanguagesTests: XCTestCase {
    func testMapsChineseRegionsToTheScriptTheFormLists() {
        let offered = ["en", "zh-Hans", "zh-Hant"]
        XCTAssertEqual(matchLanguage("zh-TW", offered), "zh-Hant")
        XCTAssertEqual(matchLanguage("zh-HK", offered), "zh-Hant")
        XCTAssertEqual(matchLanguage("zh-CN", offered), "zh-Hans")
        XCTAssertEqual(matchLanguage("zh", offered), "zh-Hans")
        XCTAssertEqual(matchLanguage("zh-TW", ["en", "zh-Hans"]), "zh-Hans")
    }

    func testFallsBackToTheBaseLanguage() {
        XCTAssertEqual(matchLanguage("zh-Hant-TW", ["en", "zh"]), "zh")
        XCTAssertNil(matchLanguage("zh-Hant-TW", ["en", "bn"]))
    }

    func testPrefersTheExactTagAndIgnoresCase() {
        XCTAssertEqual(matchLanguage("EN-gb", ["en", "en-GB"]), "en-GB")
        XCTAssertEqual(matchLanguage("BN", ["bn"]), "bn")
    }

    func testTruncatesSubtagsThenMatchesTheBaseInOfferedOrder() {
        XCTAssertEqual(matchLanguage("zh-Hant-TW", ["en", "zh-Hans", "zh-Hant"]), "zh-Hant")
        XCTAssertEqual(matchLanguage("zh", ["en", "zh-Hans", "zh-Hant"]), "zh-Hans")
        XCTAssertEqual(matchLanguage("pt-AO", ["pt-BR", "pt-PT"]), "pt-BR")
        XCTAssertEqual(matchLanguage("pt_pt", ["pt-BR", "pt-PT"]), "pt-PT")
        XCTAssertEqual(matchLanguage(" en_GB ", ["en-gb"]), "en-gb")
    }

    func testNeverFailsOnBadInput() {
        XCTAssertNil(matchLanguage(nil, ["en"]))
        XCTAssertNil(matchLanguage("", ["en"]))
        XCTAssertEqual(norm(nil), "")
        XCTAssertEqual(norm(7), "")
    }

    func testKnowsDirectionAndOwnNames() {
        XCTAssertTrue(languageInfo("ar").rtl)
        XCTAssertTrue(languageInfo("ur-PK").rtl)
        XCTAssertFalse(languageInfo("en").rtl)
        XCTAssertEqual(languageInfo("bn").name, "বাংলা")
        XCTAssertEqual(languageInfo("en").name, "English")
    }

    func testRtlBases() {
        for c in ["ar", "fa", "he", "ur", "ar-EG"] { XCTAssertTrue(languageInfo(c).rtl, c) }
        for c in ["en", "bn"] { XCTAssertFalse(languageInfo(c).rtl, c) }
    }

    func testEchoesAnUnknownCode() { XCTAssertEqual(languageInfo("xx").name, "xx") }

    func testNamesAreTableDriven() {
        let all = [
            "en": "English", "bn": "বাংলা", "hi": "हिन्दी", "ur": "اردو", "ar": "العربية", "es": "Español", "fr": "Français",
            "de": "Deutsch", "pt": "Português", "id": "Bahasa Indonesia", "tr": "Türkçe", "zh": "中文", "ja": "日本語",
            "pt-BR": "Português (Brasil)", "pt_PT": "Português (Portugal)", "zh-Hans": "简体中文", "zh-Hant": "繁體中文",
            "zh-CN": "简体中文", "zh-TW": "繁體中文", "en-US": "English (US)", "en-GB": "English (UK)",
            "es-419": "Español (Latinoamérica)", "es-ES": "Español (España)", "fr-CA": "Français (Canada)",
        ]
        for (c, n) in all { XCTAssertEqual(languageInfo(c).name, n, c) }
    }

    // ---- resolveLanguage ----
    private func form(_ languages: [String], def: String? = nil) -> JSONObject {
        var f: JSONObject = ["kind": "feedback", "languages": languages]
        if let def { f["defaultLanguage"] = def }
        return f
    }

    func testResolvePrefersRememberedThenDeveloperThenDeviceThenDefault() {
        let f = form(["en", "bn", "ar"])
        XCTAssertEqual(resolveLanguage(f, remembered: "ar", developer: "bn", device: ["bn"]), "ar")
        XCTAssertEqual(resolveLanguage(f, remembered: nil, developer: "bn", device: ["ar"]), "bn")
        XCTAssertEqual(resolveLanguage(f, remembered: nil, developer: nil, device: ["fr", "ar-EG"]), "ar")
        XCTAssertEqual(resolveLanguage(f, remembered: nil, developer: nil, device: ["fr"]), "en")
        XCTAssertEqual(resolveLanguage(form(["bn", "en"], def: "bn"), remembered: nil, developer: nil, device: []), "bn")
    }

    func testResolveFallsThroughALanguageTheFormDoesNotOffer() {
        let f = form(["en", "bn", "ar"])
        XCTAssertEqual(resolveLanguage(f, remembered: "fr", developer: nil, device: ["bn"]), "bn")
        XCTAssertEqual(resolveLanguage(f, remembered: "fr", developer: "de", device: []), "en")
    }

    func testResolveReturnsTheOfferedCodeAndMapsZhHantTwToZh() {
        XCTAssertEqual(resolveLanguage(form(["en", "zh"]), remembered: nil, developer: nil, device: ["zh-Hant-TW"]), "zh")
        XCTAssertEqual(resolveLanguage(form(["en", "bn"]), remembered: nil, developer: nil, device: ["zh-Hant-TW"]), "en")
    }
}
