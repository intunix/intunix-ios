import XCTest
@testable import Intunix

/// Same cases as ThemeTest.kt and theme.test.ts in @intunix/core.
final class ThemeTests: XCTestCase {
    func testDeveloperBeatsLockBeatsHost() {
        XCTAssertFalse(resolveDark(.light, lock: "dark", hostDark: true))
        XCTAssertTrue(resolveDark(.dark, lock: "light", hostDark: false))
        XCTAssertFalse(resolveDark(.auto, lock: "light", hostDark: true))
        XCTAssertTrue(resolveDark(.auto, lock: "dark", hostDark: false))
        XCTAssertTrue(resolveDark(.auto, lock: nil, hostDark: true))
        XCTAssertFalse(resolveDark(.auto, lock: "auto", hostDark: false))
    }

    func testDefaultDarkIsReadable() {
        let p = darkPalette(nil)
        XCTAssertEqual(p.card, RGB(hex: defaultDarkBackground))
        XCTAssertGreaterThanOrEqual(contrast(p.text, p.card), 7)
        XCTAssertGreaterThanOrEqual(contrast(p.muted, p.card), 4.5)
    }

    func testInvalidBackgroundFallsBack() {
        XCTAssertEqual(darkPalette("red; x").card, RGB(hex: defaultDarkBackground))
        XCTAssertEqual(darkPalette("#0b1220").card, RGB(hex: "#0b1220"))
    }

    func testLightBackgroundStillReadable() {
        let p = darkPalette("#f5f5f5")
        XCTAssertGreaterThanOrEqual(contrast(p.text, p.card), 7)
        XCTAssertGreaterThanOrEqual(contrast(p.muted, p.card), 4.5)
    }

    func testInvisibleBrandIsLightened() {
        let card = darkPalette(nil).card
        let a = accent(RGB(hex: "#18181b")!, on: card)
        XCTAssertNotEqual(a, RGB(hex: "#18181b"))
        XCTAssertGreaterThanOrEqual(contrast(a, card), 3)
        XCTAssertEqual(accent(RGB(hex: "#22c55e")!, on: card), RGB(hex: "#22c55e"))
    }

    func testParsesBrandDark() {
        let c = parseFeedbackContent(parseJSON("{\"kind\":\"feedback\",\"steps\":[],\"brand\":{\"color\":\"#111111\",\"dark\":{\"mode\":\"dark\",\"background\":\"#0b1220\"}}}") as! JSONObject)
        XCTAssertEqual(c?.brand.darkMode, "dark")
        XCTAssertEqual(c?.brand.darkBackground, "#0b1220")
    }
}
