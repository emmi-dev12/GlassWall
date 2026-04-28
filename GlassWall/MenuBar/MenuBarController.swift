// MARK: - Menu Bar Controller
// Manages the NSStatusItem (menu bar icon) for GlassWall.
// Provides:
//   • One-click Panic Mode toggle (Digital Clean Room)
//   • Quick access to the main window
//   • Live pending-decision count badge
//   • System extension status

import AppKit
import SwiftUI
import Combine

final class MenuBarController {

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var bag = Set<AnyCancellable>()
    private weak var engine: PolicyEngine?

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Setup
    // ─────────────────────────────────────────────────────────────────────────

    func setup(engine: PolicyEngine) {
        self.engine = engine

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "shield.lefthalf.filled",
                                     accessibilityDescription: "GlassWall")
        item.button?.image?.isTemplate = true  // adapts to light/dark menu bar
        statusItem = item

        buildMenu()
        item.menu = menu

        // Observe state changes.
        engine.$panicMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.updateIcon(panicMode: state.isEnabled) }
            .store(in: &bag)

        engine.$pendingFlows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] flows in self?.updateBadge(count: flows.count) }
            .store(in: &bag)
    }

    func tearDown() {
        statusItem.map { NSStatusBar.system.removeStatusItem($0) }
        statusItem = nil
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Menu Construction
    // ─────────────────────────────────────────────────────────────────────────

    private func buildMenu() {
        let m = NSMenu(title: "GlassWall")

        // Header (non-interactive)
        let titleItem = NSMenuItem(title: "GlassWall", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleItem.attributedTitle = NSAttributedString(
            string: "GlassWall",
            attributes: [.font: titleFont, .foregroundColor: NSColor.labelColor]
        )
        m.addItem(titleItem)
        m.addItem(.separator())

        // Open main window
        m.addItem(withTitle: "Open GlassWall…",
                  action: #selector(openMainWindow),
                  keyEquivalent: "o")
            .target = self

        m.addItem(.separator())

        // Panic Mode toggle
        let panicItem = NSMenuItem(title: "Enable Digital Clean Room",
                                   action: #selector(togglePanicMode),
                                   keyEquivalent: "p")
        panicItem.target = self
        panicItem.tag    = 100  // used to update title later
        m.addItem(panicItem)

        m.addItem(.separator())

        // Status info
        let statusItem = NSMenuItem(title: "Network Extension: Active",
                                    action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        statusItem.tag = 200
        m.addItem(statusItem)

        m.addItem(.separator())

        m.addItem(withTitle: "Quit GlassWall",
                  action: #selector(NSApplication.terminate(_:)),
                  keyEquivalent: "q")

        menu = m
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Actions
    // ─────────────────────────────────────────────────────────────────────────

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.isVisible || !$0.isMiniaturized }?.makeKeyAndOrderFront(nil)
    }

    @objc private func togglePanicMode() {
        guard let engine else { return }
        let newState = !engine.panicMode.isEnabled
        engine.setPanicMode(newState)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Dynamic Updates
    // ─────────────────────────────────────────────────────────────────────────

    private func updateIcon(panicMode: Bool) {
        let symbolName = panicMode ? "lock.shield.fill" : "shield.lefthalf.filled"
        statusItem?.button?.image = NSImage(systemSymbolName: symbolName,
                                             accessibilityDescription: nil)
        statusItem?.button?.image?.isTemplate = !panicMode  // coloured in panic mode

        if panicMode {
            // Tint the icon red in panic mode.
            if let btn = statusItem?.button {
                btn.contentTintColor = NSColor(Color.gwPanic)
            }
        } else {
            statusItem?.button?.contentTintColor = nil
        }

        // Update menu item title.
        if let item = menu?.item(withTag: 100) {
            item.title = panicMode ? "Disable Digital Clean Room" : "Enable Digital Clean Room"
        }
    }

    private func updateBadge(count: Int) {
        guard let btn = statusItem?.button else { return }
        if count > 0 {
            btn.title = " \(count)"
            btn.font  = .systemFont(ofSize: 11, weight: .bold)
        } else {
            btn.title = ""
        }
    }
}
