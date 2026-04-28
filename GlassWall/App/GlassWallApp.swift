// MARK: - GlassWall Application Entry Point
// SwiftUI @main that creates the PolicyEngine, wires AppDelegate, and presents
// the main window as a standard titled window (not a Settings-style panel).

import SwiftUI

@main
struct GlassWallApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var engine = PolicyEngine()

    init() {
        // Inject the engine into AppDelegate immediately after @StateObject
        // initialises it.  The adaptor is already created at this point.
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .onAppear {
                    // Forward engine reference to AppDelegate (needed for menu bar).
                    appDelegate.engine = engine
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            // Remove the standard New Window command; GlassWall is single-window.
            CommandGroup(replacing: .newItem) {}
        }
    }
}
