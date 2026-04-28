// MARK: - App Delegate
// Handles:
//   • System Extension installation lifecycle
//   • Content Filter configuration (NEFilterManager)
//   • Menu bar controller setup / teardown
//   • App termination cleanup

import AppKit
import NetworkExtension
import SystemExtensions
import os.log

private let log = OSLog(subsystem: GlassWall.BundleID.app, category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Injected by GlassWallApp
    var engine: PolicyEngine!
    let menuBarController = MenuBarController()

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: NSApplicationDelegate
    // ─────────────────────────────────────────────────────────────────────────

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController.setup(engine: engine)
        engine.start()

        // Kick off system extension installation.
        installSystemExtension()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
        menuBarController.tearDown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // GlassWall lives in the menu bar; closing the window is fine.
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: System Extension Installation
    // ─────────────────────────────────────────────────────────────────────────

    private func installSystemExtension() {
        let req = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: GlassWall.BundleID.networkExtension,
            queue: .main
        )
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
        os_log("System extension activation request submitted", log: log, type: .info)
    }

    private func enableContentFilter() {
        NEFilterManager.shared().loadFromPreferences { [weak self] error in
            if let error {
                os_log("Failed to load filter preferences: %{public}@",
                       log: log, type: .error, error.localizedDescription)
                return
            }

            let mgr = NEFilterManager.shared()

            if mgr.providerConfiguration == nil {
                let cfg = NEFilterProviderConfiguration()
                cfg.filterSockets  = true
                cfg.filterPackets  = false
                mgr.providerConfiguration = cfg
            }

            mgr.isEnabled = true
            mgr.localizedDescription = "GlassWall Network Filter"

            mgr.saveToPreferences { error in
                if let error {
                    os_log("Failed to save filter preferences: %{public}@",
                           log: log, type: .error, error.localizedDescription)
                } else {
                    os_log("Content filter enabled", log: log, type: .info)
                }
            }
        }
    }

    private func disableContentFilter() {
        NEFilterManager.shared().loadFromPreferences { error in
            guard error == nil else { return }
            NEFilterManager.shared().isEnabled = false
            NEFilterManager.shared().saveToPreferences { _ in }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: OSSystemExtensionRequestDelegate
// ─────────────────────────────────────────────────────────────────────────────

extension AppDelegate: OSSystemExtensionRequestDelegate {

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            os_log("System extension installed successfully", log: log, type: .info)
            enableContentFilter()
        case .willCompleteAfterReboot:
            os_log("System extension will complete after reboot", log: log, type: .info)
        @unknown default:
            os_log("System extension unknown result", log: log, type: .error)
        }
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFailWithError error: Error) {
        os_log("System extension installation failed: %{public}@",
               log: log, type: .error, error.localizedDescription)
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        os_log("System extension needs user approval in Security & Privacy settings",
               log: log, type: .info)
        // Show a sheet directing the user to System Settings → Privacy & Security.
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText     = "System Extension Requires Approval"
            alert.informativeText = "Please open System Settings → Privacy & Security and approve the GlassWall Network Extension."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security")!
                )
            }
        }
    }

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace  // Auto-upgrade on new versions.
    }
}
