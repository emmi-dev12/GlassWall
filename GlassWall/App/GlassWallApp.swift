// MARK: - GlassWall Application Entry Point

import SwiftUI

@main
struct GlassWallApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var engine = PolicyEngine()

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .onAppear {
                    appDelegate.engine = engine
                    if !hasCompletedOnboarding {
                        // Short delay so the main window renders first.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            showOnboarding = true
                        }
                    }
                }
                .sheet(isPresented: $showOnboarding, onDismiss: {
                    hasCompletedOnboarding = true
                }) {
                    OnboardingView()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("GlassWall") {
                Button("Toggle Clean Room") {
                    engine.setPanicMode(!engine.panicMode.isEnabled)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Divider()

                Button("Show Setup Guide") {
                    showOnboarding = true
                }
            }
        }
    }
}
