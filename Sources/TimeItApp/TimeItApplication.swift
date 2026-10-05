import SwiftUI
import AppKit
import TimeItCore

@main struct TimeItApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared
    var body: some Scene {
        // SwiftUI owns the item’s registration and rendering in Control Centre.
        // An AppKit item can report visible on Tahoe even when its icon is unreachable.
        MenuBarExtra {
            Button(model.active == nil ? "Start Convex Timer" : "Stop Timer") { model.toggle() }
            Divider()
            Button("Open Time It") { delegate.showWindow() }
            Button("Sync Now") { model.sync(force: true) }
            Divider()
            Button("Quit Time It") { NSApp.terminate(nil) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: model.active == nil ? "timer" : "stop.circle.fill")
                if let active = model.active {
                    Text(durationText(active.duration(at: model.now))).monospacedDigit()
                }
            }
            .foregroundStyle(model.active == nil ? Color.primary : Color.orange)
            .accessibilityLabel(model.active == nil ? "Time It: start Convex timer" : "Time It: recording")
        }
        .menuBarExtraStyle(.menu)
        Window("Time It", id: "main") {
            MainView(model: model)
                .frame(minWidth: 860, minHeight: 600)
        }.defaultSize(width: 1000, height: 720)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Start / Stop Timer") { AppModel.shared.toggle() }.keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Export CSV…") { AppModel.shared.exportCSV() }
            }
        }
    }
}
