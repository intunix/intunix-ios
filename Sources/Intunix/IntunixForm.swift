#if os(iOS)
import SwiftUI
import IntunixCore

@MainActor
final class InlineFormModel: ObservableObject {
    @Published var host: FormHost?
    @Published var done = false
}

/// A form placed in your own layout (the web SDK's inline form). Shows nothing until the
/// form loads, and nothing again once the visitor is done.
public struct IntunixForm: View {
    private let form: String
    private let context: [String: Any]?
    private let onFinished: (() -> Void)?
    // Lives as long as this view's identity, so re-appearing (navigation, tabs) keeps answers.
    @StateObject private var model = InlineFormModel()

    /// - Parameters:
    ///   - form: form id or slug
    ///   - context: values sent with the response, on top of ``Intunix/setContext(_:)``
    ///   - onFinished: called once the visitor submits or closes the form
    public init(form: String, context: [String: Any]? = nil, onFinished: (() -> Void)? = nil) {
        self.form = form; self.context = context; self.onFinished = onFinished
    }

    public var body: some View {
        // The ZStack always exists, so its task runs even while nothing is drawn yet.
        ZStack {
            Color.clear.frame(width: 0, height: 0)
            if let host = model.host, !model.done { FeedbackFormView(host: host) }
        }
        .task(id: form) { await load() }
    }

    @MainActor private func load() async {
        guard model.host == nil, !model.done else { return }
        guard let client = await Intunix.readyClient(), let exp = await client.resolve(form),
              let content = parseFeedbackContent(exp.content) else { return }
        let ctx = client.contextFor(context)
        let responseId = newId()
        let finished = onFinished
        let model = self.model
        model.host = FormHost(exp: exp, content: content, callbacks: client.callbacks(exp, ctx, responseId),
                              openUrl: OverlayPresenter.openUrl) { result in
            client.settle(exp, ctx, result, responseId)
            model.done = true
            finished?()
        }
    }
}
#endif
