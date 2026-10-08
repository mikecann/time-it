import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    // SwiftUI drops the window when it closes, so only its own openWindow action can bring it back.
    var openMainWindow: (() -> Void)?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    // With the window closed Time It lives only in the menu bar, so it drops out of the Dock and taskbar.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard (note.object as? NSWindow)?.title == "Time It" else { return }
            MainActor.assumeIsolated { NSApp.setActivationPolicy(.accessory) }
        }
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            guard (note.object as? NSWindow)?.title == "Time It" else { return }
            MainActor.assumeIsolated { if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) } }
        }
    }
    // Cmd+Q closes the window so the timer stays in the menu bar. Choosing Quit from a menu, logging out or shutting down still quits.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let event = NSApp.currentEvent, event.type == .keyDown, event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "q" else { return .terminateNow }
        NSApp.windows.filter { $0.title == "Time It" }.forEach { $0.close() }
        return .terminateCancel
    }
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
    func showWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Time It" }) { window.makeKeyAndOrderFront(nil) }
        else { openMainWindow?() }
    }
}
