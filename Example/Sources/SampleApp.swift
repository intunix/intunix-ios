import SwiftUI
import Intunix

// Runs against the local mock API: node Intunix/Frontend/intunix-sdk/examples/languages/server.mjs
let apiKey = "ck_mock"

@main
struct SampleApp: App {
    init() {
        Intunix.initialize(apiKey: apiKey, options: IntunixOptions(apiHost: "http://127.0.0.1:4100", registerAll: true, debug: true))
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
                button("Chat with Nia (popup)") { Intunix.showForm("lang-chat") }
                button("Survey (popup)") { Intunix.showForm("lang-popup") }
                Text("App language").font(.headline).padding(.top, 8)
                HStack(spacing: 8) {
                    ForEach([("English", "en"), ("বাংলা", "bn"), ("العربية", "ar")], id: \.1) { name, tag in
                        button(name) { Intunix.setLocale(tag) }
                    }
                }
                button("Track \"checkout_completed\"") { Intunix.track("checkout_completed") }
                button("Identify demo user") { Intunix.identify("demo-user", traits: ["plan": "pro"]) }
                button("Reset (log out)") { Intunix.reset() }
                Text("Inline form").font(.headline).padding(.top, 8)
                IntunixForm(form: "lang-inline")
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                Text("Inline chat (Arabic)").font(.headline).padding(.top, 8)
                IntunixForm(form: "lang-chat", locale: "ar")
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
