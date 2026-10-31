import SwiftUI
import Intunix

// Replace with your client key and a form slug from the Intunix console.
let apiKey = "ck_your_client_key"
let formSlug = "your-form-slug"

@main
struct SampleApp: App {
    init() {
        Intunix.initialize(apiKey: apiKey, options: IntunixOptions(registerAll: true, debug: true))
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Intunix \(Intunix.version)").font(.title2.bold())
                button("Show form as a popup") { Intunix.showForm(formSlug) }
                button("Track \"checkout_completed\"") { Intunix.track("checkout_completed") }
                button("Identify demo user") { Intunix.identify("demo-user", traits: ["plan": "pro"]) }
                button("Reset (log out)") { Intunix.reset() }
                Text("Inline form").font(.headline).padding(.top, 8)
                IntunixForm(form: formSlug)
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            }
            .padding(16)
        }
        .background(Color(white: 0.96).ignoresSafeArea())
        .onAppear { Intunix.screen("Home") }
    }

    private func button(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.18, green: 0.58, blue: 0.38)))
        }
    }
}
