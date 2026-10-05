import AppKit
import Combine
import Network
import TimeItCore

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    static let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.mikerosoft.time-it")
    @Published var store: TimeStore?
    @Published var now = Date()
    @Published var error: String?
    @Published var importNotice: String?
    @Published var syncStatus = "Saved on this Mac"
    @Published var syncing = false
    @Published var online = true
    @Published var selectedCategory = "convex"
    @Published var note = ""
    @Published var page = "Today"
    @Published var endpoint = UserDefaults.standard.string(forKey: "syncURL") ?? ""
    private var ticks: AnyCancellable?
    private let monitor = NWPathMonitor()
    private var lastAttempt = Date.distantPast
    private var needsDownload = true
    private var syncTask: Task<Void, Never>?

    private init() {
        do {
            store = try TimeStore(fileURL: Self.support.appendingPathComponent("state.json"))
            store?.onChange = { [weak self] in
                self?.objectWillChange.send()
                self?.writeWidget()
            }
        } catch { self.error = "Could not open your time data: \(error.localizedDescription). The existing file has been kept. Use Show Data Folder in Connection settings to make a backup before repairing it." }
        loadConnectionBootstrap()
        ticks = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] date in
            guard let self else { return }; self.now = date
            if date.timeIntervalSince(self.lastAttempt) >= 30 { self.sync() }
        }
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.online = path.status == .satisfied
                if path.status == .satisfied { self?.sync(force: true) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "time-it.network"))
        writeWidget()
    }
    var active: TimeEntry? { store?.activeEntry }
    var categories: [TimeItCore.Category] { store?.categories ?? [] }
    var entries: [TimeEntry] { store?.entries ?? [] }
    var pending: Int { store?.pendingCount ?? 0 }
    var configured: Bool { !endpoint.isEmpty && Keychain.read() != nil }
    func perform(_ action: () throws -> Void) {
        do { try action(); error = nil; sync() }
        catch { self.error = error.localizedDescription }
    }
    func toggle() {
        guard let store else { return }
        perform {
            if store.activeEntry != nil { try store.stop(); selectedCategory = "convex"; note = "" }
            else { try store.start(categoryId: "convex"); selectedCategory = "convex"; note = "" }
        }
    }
    func startSelected() {
        guard let store else { return }
        perform { try store.start(categoryId: selectedCategory, note: note); note = "" }
    }
    func stop() {
        guard let store else { return }
        perform { try store.stop(); selectedCategory = "convex"; note = "" }
    }
    private func loadConnectionBootstrap() {
        let file = Self.support.appendingPathComponent("connection-bootstrap.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        struct Connection: Decodable { let url: String; let key: String }
        do {
            let connection = try JSONDecoder().decode(Connection.self, from: Data(contentsOf: file))
            _ = try SyncClient(baseURL: connection.url, token: connection.key)
            // The installed app writes its own Keychain item so future launches keep the same access identity.
            try Keychain.save(connection.key)
            endpoint = connection.url
            UserDefaults.standard.set(endpoint, forKey: "syncURL")
            try FileManager.default.removeItem(at: file)
        } catch {
            self.error = "Could not save the connection: \(error.localizedDescription). Your time data is unchanged."
        }
    }
    func configure(url: String, key: String) {
        perform {
            let actualKey = key.isEmpty ? (Keychain.read() ?? "") : key.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try SyncClient(baseURL: url, token: actualKey)
            try Keychain.save(actualKey)
            endpoint = url.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(endpoint, forKey: "syncURL")
            needsDownload = true
        }
    }
    func sync(force: Bool = false) {
        if force { needsDownload = true }
        lastAttempt = Date()
        guard !syncing, online, let store, pending > 0 || needsDownload else { return }
        guard let key = Keychain.read(), let client = try? SyncClient(baseURL: endpoint, token: key) else { syncStatus = "Saved on this Mac · Sync not connected"; return }
        let download = needsDownload
        needsDownload = false
        syncing = true; syncStatus = "Syncing…"
        syncTask = Task {
            do {
                try await SyncEngine.run(store: store, download: download) { request in try await client.send(request) }
                syncStatus = pending == 0 ? "Everything synced" : "\(pending) changes waiting to sync"
            } catch {
                needsDownload = needsDownload || download
                syncStatus = "Saved locally · Waiting to sync"
                if case SyncError.unauthorized = error { self.error = error.localizedDescription }
            }
            syncing = false
            writeWidget()
        }
    }
    func total(_ component: Calendar.Component, category: String? = nil) -> TimeInterval {
        guard let interval = Calendar.current.dateInterval(of: component, for: now) else { return 0 }
        return store?.total(in: interval, categoryId: category, now: now) ?? 0
    }
    func exportCSV() {
        guard let store else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "time-it-\(now.formatted(.iso8601.year().month().day().dateSeparator(.dash))).csv"
        if panel.runModal() == .OK, let url = panel.url { perform { try store.csv().write(to: url, atomically: true, encoding: .utf8) } }
    }
    func importClockify() {
        guard let store else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Clockify history"
        panel.message = "Choose the JSON archive created by Time It’s Clockify exporter. Your running timer will continue."
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            let archive = try JSONDecoder().decode(ClockifyArchive.self, from: Data(contentsOf: url))
            let result = try store.importClockify(archive)
            importNotice = "Imported \(result.added.formatted()) Clockify sessions and \(result.categoriesAdded) categories. \(result.existing.formatted()) already imported sessions were left as saved.\(result.skippedRunning > 0 ? " Skipped \(result.skippedRunning) running Clockify timers." : "") A backup is saved in your data folder."
        }
    }
    func showDataFolder() { NSWorkspace.shared.open(Self.support) }
    func writeWidget() {
        guard let store else { return }
        let state: [String: Any] = ["running": store.activeEntry != nil, "startedAt": store.activeEntry?.startedAt ?? 0, "category": store.activeEntry.flatMap { store.category($0.categoryId)?.name } ?? "Convex", "pending": store.pendingCount]
        if let data = try? JSONSerialization.data(withJSONObject: state) {
            try? data.write(to: Self.support.appendingPathComponent("widget.json"), options: .atomic)
        }
        DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.mikerosoft.time-it.changed"), object: nil)
    }
}
