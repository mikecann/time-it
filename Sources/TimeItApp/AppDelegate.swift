import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
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
    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Time It" }) { window.makeKeyAndOrderFront(nil) }
        else { NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: .init()) }
    }
}
