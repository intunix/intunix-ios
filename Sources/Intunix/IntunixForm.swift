#if os(iOS)
import SwiftUI
import IntunixCore

/// A form placed in your own layout (the web SDK's inline form). Shows nothing until the
/// form loads, and nothing again once the visitor is done.
public struct IntunixForm: View {
    private let form: String
    private let context: [String: Any]?
    private let onFinished: (() -> Void)?
    @State private var host: FormHost?
    @State private var done = false

    /// - Parameters:
    ///   - form: form id or slug
    ///   - context: values sent with the response, on top of ``Intunix/setContext(_:)``
    ///   - onFinished: called once the visitor submits or closes the form
    public init(form: String, context: [String: Any]? = nil, onFinished: (() -> Void)? = nil) {
        self.form = form; self.context = context; self.onFinished = onFinished
    }

    public var body: some View {
        Group {
            if let host, !done { FeedbackFormView(host: host) }
        }
        .task(id: form) { await load() }
    }

    @MainActor private func load() async {
            guard let client = Intunix.client, let exp = await client.resolve(form),
                  let content = parseFeedbackContent(exp.content) else { return }
            let ctx = client.contextFor(context)
            let responseId = newId()
            host = FormHost(exp: exp, content: content, callbacks: client.callbacks(exp, ctx, responseId),
                            openUrl: OverlayPresenter.openUrl) { result in
                client.settle(exp, ctx, result, responseId)
                done = true
                onFinished?()
            }
    }
}
#endif
