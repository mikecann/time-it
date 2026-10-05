import AppKit
import Combine
import TimeItCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var updates: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self; button.action = #selector(pressed)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updates = AppModel.shared.$now.sink { [weak self] _ in self?.refresh() }
        refresh()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "time-it" {
            switch url.host {
            case "toggle": AppModel.shared.toggle()
            case "start": if AppModel.shared.active == nil { AppModel.shared.toggle() }
            case "stop": if AppModel.shared.active != nil { AppModel.shared.stop() }
            default: showWindow()
            }
        }
    }
    private func refresh() {
        let model = AppModel.shared
        item?.button?.title = model.active.map { durationText($0.duration(at: model.now)) } ?? ""
        item?.button?.image = NSImage(systemSymbolName: model.active == nil ? "timer" : "stop.circle.fill", accessibilityDescription: model.active == nil ? "Start Convex timer" : "Stop timer")
        item?.button?.imagePosition = .imageLeading
        item?.button?.contentTintColor = model.active == nil ? .labelColor : .systemOrange
        item?.button?.toolTip = model.active == nil ? "Time It: click to start Convex. Right-click for options." : "Time It: click to stop. Right-click for options."
        item?.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    }
    @objc private func pressed() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let model = AppModel.shared
            let toggle = NSMenuItem(title: model.active == nil ? "Start Convex Timer" : "Stop Timer", action: #selector(toggleTimer), keyEquivalent: "")
            toggle.target = self; menu.addItem(toggle)
            menu.addItem(.separator())
            let open = NSMenuItem(title: "Open Time It", action: #selector(showWindow), keyEquivalent: "")
            open.target = self; menu.addItem(open)
            let sync = NSMenuItem(title: "Sync Now", action: #selector(syncNow), keyEquivalent: "")
            sync.target = self; menu.addItem(sync)
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Time It", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = menu; item.button?.performClick(nil); item.menu = nil
        } else { AppModel.shared.toggle() }
    }
    @objc private func toggleTimer() { AppModel.shared.toggle() }
    @objc private func syncNow() { AppModel.shared.sync(force: true) }
    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Time It" }) { window.makeKeyAndOrderFront(nil) }
        else { NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: .init()) }
    }
}
