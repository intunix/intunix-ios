import XCTest
@testable import Intunix

func fixture(_ name: String) throws -> Any {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
    return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
}
func canonical(_ v: Any) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .fragmentsAllowed]), encoding: .utf8)!
}
func json(_ s: String) -> JSONObject { try! JSONSerialization.jsonObject(with: Data(s.utf8)) as! JSONObject }

final class LocalizeTests: XCTestCase {
    func testSharedVectors() throws {
        let vectors = try fixture("localize.json") as! [JSONObject]
        XCTAssertEqual(vectors.count, 23)
        for v in vectors {
            let out = localizeContent(v["content"] as! JSONObject, v["lang"] as! String)
            XCTAssertEqual(canonical(out), canonical(v["expected"]!), v["name"] as! String)
        }
    }

    func testBuiltinTableMatchesWeb() throws {
        let web = try fixture("builtin.json") as! [String: JSONObject]
        XCTAssertEqual(Set(web.keys), Set(builtinLanguages))
        XCTAssertEqual(builtinLanguages, ["en", "bn", "hi", "ur", "ar", "es", "fr", "de", "pt", "id", "tr", "zh", "ja"])
        for l in builtinLanguages {
            let t = builtinTexts(l)
            var m: JSONObject = [
                "submit": t.submit, "next": t.next, "back": t.back, "done": t.done, "pageOf": t.pageOf, "questionOf": t.questionOf,
                "thanksTitle": t.thanksTitle, "thanksSubtitle": t.thanksSubtitle, "npsLow": t.npsLow, "npsHigh": t.npsHigh,
                "enpsLow": t.enpsLow, "enpsHigh": t.enpsHigh, "cesLow": t.cesLow, "cesHigh": t.cesHigh,
                "send": t.send, "skip": t.skip, "end": t.end, "typing": t.typing, "log": t.log,
                "answer": t.answer, "language": t.language, "close": t.close,
            ]
            m["csat"] = t.csat; m["pmf"] = t.pmf
            XCTAssertEqual(canonical(m), canonical(web[l]!), l)
        }
    }

    func testFillStepFillsOnlyNonEnglish() {
        let s = json(#"{"id":"probe:s1:1","kind":"followup","title":"Why?","input":{"type":"free"}}"#)
        XCTAssertEqual(canonical(fillStep(s, "en-GB")), canonical(s))
        XCTAssertEqual(fillStep(s, "bn").obj("input")?.str("placeholder"), "আপনার উত্তর লিখুন…")
    }

    func testSelectInputAndPmfShareOptionTranslation() {
        let c = json(#"{"kind":"feedback","languages":["en","bn"],"steps":[{"id":"q","kind":"followup","title":"T","input":{"type":"selectOne","options":[{"value":"a","label":"A"}]}}],"translations":{"bn":{"steps":{"q":{"options":{"a":"ক"}}}}}}"#)
        let o = localizeContent(c, "bn").objects("steps")[0].obj("input")!.objects("options")
        XCTAssertEqual(o[0].str("label"), "ক")
    }
}
