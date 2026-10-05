import SwiftUI
import AppKit
import TimeItCore

@main struct TimeItApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Window("Time It", id: "main") {
            MainView(model: AppModel.shared)
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
