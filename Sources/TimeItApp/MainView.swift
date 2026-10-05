import SwiftUI
import TimeItCore
import ServiceManagement

private let accent = Color(red: 0.91, green: 0.68, blue: 0.34)

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var editor: EntryEditorItem?
    @State private var search = ""
    @State private var filter = "all"
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: "timer").font(.title).foregroundStyle(accent)
                    Text("Time It").font(.title2.weight(.semibold))
                }.padding(.top, 20)
                VStack(spacing: 5) {
                    ForEach([("Today", "sun.max"), ("History", "clock.arrow.circlepath"), ("Categories", "square.grid.2x2"), ("Connection", "arrow.triangle.2.circlepath")], id: \.0) { label, symbol in
                        Button { model.page = label } label: {
                            Label(label, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading).padding(11)
                                .background(model.page == label ? accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Label(model.online ? "Saved on this Mac" : "Offline · Saved on this Mac", systemImage: model.online ? "checkmark.shield" : "wifi.slash").font(.caption)
                    Text(model.pending == 0 ? model.syncStatus : "\(model.pending) changes waiting to sync").font(.caption).foregroundStyle(.secondary)
                }
                Link("Mikerosoft", destination: URL(string: "https://mikerosoft.app")!).font(.subheadline).foregroundStyle(.secondary)
            }.padding(20).navigationSplitViewColumnWidth(210)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        Text(model.page).font(.largeTitle.weight(.semibold))
                        Spacer()
                        if model.page == "Today" || model.page == "History" {
                            Button("Add time", systemImage: "plus") { editor = EntryEditorItem(entry: nil) }
                            Button("Export", systemImage: "square.and.arrow.up") { model.exportCSV() }
                        }
                    }
                    if let error = model.error {
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            Text(error).font(.callout).textSelection(.enabled)
                            Spacer()
                            Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                        }.padding(14).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    switch model.page {
                    case "History": history
                    case "Categories": CategoriesView(model: model)
                    case "Connection": ConnectionView(model: model)
                    default: today
                    }
                }.padding(32).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
            }.background(Color(nsColor: .windowBackgroundColor))
        }.tint(accent)
        .sheet(item: $editor) { item in EntryEditor(model: model, entry: item.entry) }
    }
    private var today: some View {
        VStack(alignment: .leading, spacing: 25) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Circle().fill(model.active == nil ? .secondary : accent).frame(width: 8, height: 8)
                    Text(model.active.flatMap { model.store?.category($0.categoryId)?.name } ?? "Ready when you are").font(.headline)
                    Spacer()
                    if model.active != nil { Text("Recording").font(.callout).foregroundStyle(accent) }
                }
                Text(durationText(model.active?.duration(at: model.now) ?? 0))
                    .font(.system(size: 64, weight: .light, design: .monospaced)).monospacedDigit()
                if let active = model.active {
                    if !active.note.isEmpty { Text(active.note).foregroundStyle(.secondary) }
                    HStack {
                        Text("Started \(Date(milliseconds: active.startedAt).formatted(date: .abbreviated, time: .shortened))").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop timer", systemImage: "stop.fill") { model.stop() }.buttonStyle(.borderedProminent).controlSize(.large)
                    }
                } else {
                    HStack {
                        Picker("Category", selection: $model.selectedCategory) {
                            ForEach(model.categories) { Text($0.name).tag($0.id) }
                        }.frame(width: 210)
                        TextField("What are you working on?", text: $model.note).textFieldStyle(.roundedBorder)
                        Button("Start timer", systemImage: "play.fill") { model.startSelected() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.store == nil)
                    }
                }
            }.padding(25).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(accent.opacity(0.22)))
            HStack(spacing: 16) {
                metric("Today", value: model.total(.day))
                metric("This week", value: model.total(.weekOfYear))
                metric("Convex today", value: model.total(.day, category: "convex"))
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Today’s time").font(.title3.weight(.semibold))
                let interval = Calendar.current.dateInterval(of: .day, for: model.now)!
                let entries = model.entries.filter { $0.duration(in: interval, now: model.now) > 0 || interval.contains(Date(milliseconds: $0.startedAt)) }
                if entries.isEmpty { empty("Nothing recorded yet", description: "Start a timer here, in the menu bar, or from your taskbar.") }
                else { ForEach(entries) { entry in entryRow(entry) } }
            }
        }
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                TextField("Search notes or categories", text: $search).textFieldStyle(.roundedBorder)
                Picker("Category", selection: $filter) {
                    Text("All categories").tag("all")
                    ForEach(model.store?.state.categories ?? []) { Text($0.name).tag($0.id) }
                }.frame(width: 240)
            }
            let filtered = model.entries.filter { entry in
                (filter == "all" || filter == entry.categoryId) && (search.isEmpty || entry.note.localizedCaseInsensitiveContains(search) || (model.store?.category(entry.categoryId)?.name ?? "").localizedCaseInsensitiveContains(search))
            }
            if filtered.isEmpty { empty("No matching entries", description: "Your recorded time will appear here.") }
            ForEach(filtered) { entry in entryRow(entry, showDate: true) }
        }
    }
    private func metric(_ title: String, value: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).foregroundStyle(.secondary)
            Text(durationText(value)).font(.system(size: 25, weight: .medium, design: .monospaced))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
    private func entryRow(_ entry: TimeEntry, showDate: Bool = false) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: model.store?.category(entry.categoryId)?.color ?? "#E8AE58")).frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.note.isEmpty ? (model.store?.category(entry.categoryId)?.name ?? "Time entry") : entry.note).font(.headline).lineLimit(2)
                Text("\(model.store?.category(entry.categoryId)?.name ?? "Unknown") · \(Date(milliseconds: entry.startedAt).formatted(date: showDate ? .abbreviated : .omitted, time: .shortened))\(entry.endedAt.map { " to " + Date(milliseconds: $0).formatted(date: .omitted, time: .shortened) } ?? " · Running")").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(durationText(entry.duration(at: model.now))).font(.system(.body, design: .monospaced))
            if model.store?.state.pendingEntries.contains(entry.id) == true { Image(systemName: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary).help("Saved locally, waiting to sync") }
            Button { editor = EntryEditorItem(entry: entry) } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).help("Edit time entry")
        }.padding(15).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
    private func empty(_ title: String, description: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "clock").font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(description).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(35)
    }
}

private struct EntryEditorItem: Identifiable { let id = UUID(); let entry: TimeEntry? }
private struct EntryEditor: View {
    @ObservedObject var model: AppModel
    let entry: TimeEntry?
    @Environment(\.dismiss) var dismiss
    @State private var category = "convex"
    @State private var note = ""
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var end = Date()
    @State private var error: String?
    @State private var confirmDelete = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(entry == nil ? "Add time" : "Edit time").font(.title2.weight(.semibold))
            Picker("Category", selection: $category) {
                ForEach(model.store?.state.categories.filter { !$0.archived || $0.id == category } ?? []) { Text($0.name).tag($0.id) }
            }
            TextField("What were you working on?", text: $note).textFieldStyle(.roundedBorder)
            DatePicker("Start", selection: $start)
            if entry == nil || entry?.endedAt != nil { DatePicker("End", selection: $end) }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                if entry != nil { Button("Delete", role: .destructive) { confirmDelete = true } }
                Spacer(); Button("Cancel") { dismiss() }
                Button("Save") {
                    guard let store = model.store else { return }
                    do {
                        if let entry { try store.updateEntry(id: entry.id, categoryId: category, note: note, start: start, end: entry.endedAt == nil ? nil : end) }
                        else { try store.addManual(categoryId: category, note: note, start: start, end: end) }
                        model.sync(); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 490)
        .onAppear { if let entry { category = entry.categoryId; note = entry.note; start = Date(milliseconds: entry.startedAt); end = Date(milliseconds: entry.endedAt ?? Date().milliseconds) } }
        .confirmationDialog("Delete this time entry?", isPresented: $confirmDelete) {
            Button("Delete entry", role: .destructive) { if let entry { model.perform { try model.store?.deleteEntry(id: entry.id) }; if model.error == nil { dismiss() } } }
        }
    }
}

private struct CategoriesView: View {
    @ObservedObject var model: AppModel
    @State private var name = ""
    @State private var color = Color(hex: "#79B8B0")
    @State private var editing: String?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Convex is always the default when you start from the menu bar or taskbar. Choose another category in the timer window when you need it.").foregroundStyle(.secondary)
            HStack {
                TextField("Category name", text: $name).textFieldStyle(.roundedBorder)
                ColorPicker("Colour", selection: $color, supportsOpacity: false).labelsHidden()
                Button(editing == nil ? "Add category" : "Save category") {
                    do { try model.store?.saveCategory(id: editing, name: name, color: color.hexString); name = ""; editing = nil; error = nil; model.sync() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
                if editing != nil { Button("Cancel") { editing = nil; name = "" } }
            }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(model.store?.state.categories ?? []) { category in
                HStack {
                    Circle().fill(Color(hex: category.color)).frame(width: 12, height: 12)
                    Text(category.name).font(.headline)
                    if category.id == "convex" { Text("Default").font(.caption).foregroundStyle(.secondary) }
                    if category.archived { Text("Archived").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if category.id != "convex" {
                        Button("Rename") { editing = category.id; name = category.name; color = Color(hex: category.color) }
                        Button(category.archived ? "Restore" : "Archive") { model.perform { try model.store?.saveCategory(id: category.id, name: category.name, color: category.color, archived: !category.archived) } }
                    }
                }.padding(16).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

private struct ConnectionView: View {
    @ObservedObject var model: AppModel
    @State private var url = ""
    @State private var key = ""
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label(model.online ? model.syncStatus : "Offline. Your time is saved on this Mac.", systemImage: model.online ? "arrow.triangle.2.circlepath" : "wifi.slash").font(.headline)
            Text("Starting and stopping always saves to this Mac first. When you’re online, Time It sends pending changes to your private Convex project.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Text("Convex HTTP URL").font(.headline)
                TextField("https://your-deployment.convex.site", text: $url).textFieldStyle(.roundedBorder)
                Text("Personal sync key").font(.headline)
                SecureField(model.configured ? "Leave blank to keep the saved key" : "Paste your sync key", text: $key).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save connection") { model.configure(url: url, key: key); if model.error == nil { key = "" } }.buttonStyle(.borderedProminent)
                    Button("Sync now") { model.sync(force: true) }.disabled(model.syncing || !model.configured)
                }
            }
            Divider()
            Toggle("Start Time It when I log in", isOn: $startAtLogin).onChange(of: startAtLogin) { _, value in
                model.perform { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                startAtLogin = SMAppService.mainApp.status == .enabled
            }
            Text("Click the timer icon in the menu bar, then choose Start Convex Timer or Stop Timer. Open Time It brings you back to this window. A running timer continues across app restarts and sleep.").foregroundStyle(.secondary)
            Button("Show data folder") { model.showDataFolder() }
            Text("Make a backup of state.json if you want a separate copy of your local history. Sync credentials are stored in Keychain.").font(.caption).foregroundStyle(.secondary)
        }.onAppear { url = model.endpoint }
    }
}

extension Color {
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xE8AE58
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    var hexString: String {
        guard let color = NSColor(self).usingColorSpace(.deviceRGB) else { return "#E8AE58" }
        return String(format: "#%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
    }
}
