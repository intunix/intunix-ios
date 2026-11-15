import XCTest
@testable import Intunix

func jobj(_ s: String) -> JSONObject { parseJSON(s) as! JSONObject }

struct Boom: Error {}
/// Scripted outcome: sleeps (cancellably) this long, then fails. Used as "never answers in time".
struct Hang { let ms: UInt64 = 60_000 }

/// A reply the test releases by hand. Not cancellable, like a blocking HTTP call.
@MainActor final class Gate {
    private var result: Result<JSONObject, Error>?
    private var waiter: CheckedContinuation<JSONObject, Error>?
    func wait() async throws -> JSONObject {
        if let r = result { return try r.get() }
        return try await withCheckedThrowingContinuation { waiter = $0 }
    }
    func complete(_ o: JSONObject) { settle(.success(o)) }
    func fail(_ e: Error = Boom()) { settle(.failure(e)) }
    private func settle(_ r: Result<JSONObject, Error>) { result = r; waiter?.resume(with: r); waiter = nil }
}

@MainActor final class Fake {
    var sent: [TurnRequest] = []
    private var q: [Any]
    init(_ script: Any...) { q = script }
    func replace(_ script: [Any]) { q = script }
    var transport: ConversationTransport { { [self] req in try await send(req) } }
    private func send(_ req: TurnRequest) async throws -> JSONObject {
        sent.append(req)
        let r: Any = q.isEmpty ? reply() : q.removeFirst()
        switch r {
        case let e as Error: throw e
        case let h as Hang: try await Task.sleep(nanoseconds: h.ms * 1_000_000); throw Boom()
        case let g as Gate: return try await g.wait()
        default: return r as! JSONObject
        }
    }
}

func reply(_ next: Int = 1, _ msgs: String..., input: String? = nil, done: Bool = false, busy: Bool = false, answered: Int = 0, total: Int = 3) -> JSONObject {
    let m = msgs.map { "{\"role\":\"nia\",\"text\":\"\($0)\"}" }.joined(separator: ",")
    return jobj("""
    {"messages":[\(m)],"input":\(input ?? "null"),"progress":{"answered":\(answered),"total":\(total)},"done":\(done),"next_turn":\(next)\(busy ? ",\"busy\":true" : "")}
    """)
}

func stepJson(_ id: String, _ extra: String = "", kind: String = "nps", title: String? = nil) -> String {
    "{\"id\":\"\(id)\",\"kind\":\"\(kind)\",\"title\":\"\(title ?? "Q \(id)")\"\(extra)}"
}
func nps(_ id: String, _ extra: String = "", title: String? = nil) -> String { stepJson(id, extra, title: title) }
func followup(_ id: String, required: Bool, title: String = "Why") -> String {
    stepJson(id, ",\"required\":\(required),\"input\":{\"type\":\"free\"}", kind: "followup", title: title)
}
func content(_ steps: [String], thanks: String? = nil) -> FeedbackContent {
    let t = thanks.map { ",\"thanks\":{\"title\":\"\($0)\"}" } ?? ""
    return parseFeedbackContent(jobj("{\"kind\":\"feedback\",\"brand\":{\"color\":\"#000\"},\"steps\":[\(steps.joined(separator: ","))]\(t)}"))!
}
func step(_ s: String) -> Step { parseStep(jobj(s))! }
func nia(_ t: String) -> ChatMessage { ChatMessage("nia", t) }
func num(_ id: String, _ v: Int) -> Answer { Answer(id, "nps", .num(v)) }
func free(_ id: String, _ t: String) -> Answer { Answer(id, "followup", .text(type: "free", text: t)) }

/// Runs a main-actor async body (Linux XCTest cannot discover @MainActor test methods).
func onMain(_ body: @MainActor @escaping () async -> Void) async { await Task { @MainActor in await body() }.value }
// macOS CI runs this suite ~5x slower than Linux; fixed waits need the same headroom there.
#if os(macOS)
let settleScale: UInt64 = 5
#else
let settleScale: UInt64 = 1
#endif
func settle(_ ms: UInt64 = 40) async { try? await Task.sleep(nanoseconds: ms * settleScale * 1_000_000) }
/// Waits for `ok` (polling every 10ms, up to 2s): CI machines are slower than a fixed settle assumes.
@MainActor func waitUntil(_ ok: () -> Bool) async { for _ in 0..<200 where !ok() { await settle(10) } }

// Scaled with settle(): a held request must not hit the timeout while a test is still waiting on it.
let fastTiming = ConversationTiming(turnTimeoutMs: 200 * settleScale, busyRetryMs: 5, probeTimeoutMs: 200 * settleScale)
extension ChatMessage { var bare: ChatMessage { ChatMessage(role, text) } }
extension Array where Element == ChatMessage { var bare: [ChatMessage] { map(\.bare) } }
