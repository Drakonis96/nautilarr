import SwiftUI
import NautilarrCore
import QBittorrentKit
import SABnzbdKit
import NZBGetKit
import TransmissionKit
import DelugeKit

/// Full management of a single download client: its items with per-item
/// pause/resume/remove, plus client-wide actions (pause/resume all, add a
/// magnet/torrent for torrent clients, set a speed limit for usenet clients).
@MainActor
final class DownloadClientViewModel: ObservableObject {
    struct Item: Identifiable {
        let id: String
        let title: String
        let progress: Double
        let state: String
        let isPaused: Bool
        let isError: Bool
        let size: Double?
        var seedingSeconds: Int? = nil
        var ratio: Double? = nil
        let togglePause: (@MainActor () async -> Void)?
        let remove: (@MainActor (_ deleteData: Bool) async -> Void)?
        var recheck: (@MainActor () async -> Void)? = nil
    }

    @Published var items: [Item] = []
    @Published var isLoading = false
    @Published var status: String?

    let instance: ServiceInstance
    init(instance: ServiceInstance) { self.instance = instance }

    var isTorrentClient: Bool { [.qbittorrent, .transmission, .deluge].contains(instance.type) }
    var supportsAdd: Bool { isTorrentClient || instance.type == .sabnzbd }
    var supportsSpeedLimit: Bool { instance.type == .sabnzbd || instance.type == .nzbget }

    func load(store: InstanceStore) async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        switch instance.type {
        case .qbittorrent:
            guard let c = store.qbittorrentClient(for: instance) else { items = []; return }
            items = ((try? await c.torrents()) ?? []).map { t in
                let paused = t.isPaused
                return Item(id: t.hash, title: t.name, progress: t.progress ?? 0, state: t.displayState,
                            isPaused: paused, isError: t.state == "error" || t.state == "missingFiles",
                            size: t.size.map(Double.init),
                            seedingSeconds: t.seedingTime, ratio: t.ratio,
                            togglePause: { if paused { try? await c.resume(hashes: [t.hash]) } else { try? await c.pause(hashes: [t.hash]) } },
                            remove: { try? await c.delete(hashes: [t.hash], deleteFiles: $0) },
                            recheck: { try? await c.recheck(hashes: [t.hash]) })
            }
        case .transmission:
            guard let c = store.transmissionClient(for: instance) else { items = []; return }
            items = ((try? await c.torrents()) ?? []).map { t in
                let paused = t.isPaused
                return Item(id: "\(t.id)", title: t.name ?? "Unknown", progress: t.progress, state: t.displayState,
                            isPaused: paused, isError: t.hasError, size: t.totalSize.map(Double.init),
                            seedingSeconds: t.secondsSeeding, ratio: t.uploadRatio,
                            togglePause: { if paused { try? await c.start(ids: [t.id]) } else { try? await c.stop(ids: [t.id]) } },
                            remove: { try? await c.remove(ids: [t.id], deleteData: $0) },
                            recheck: { try? await c.verify(ids: [t.id]) })
            }
        case .deluge:
            guard let c = store.delugeClient(for: instance) else { items = []; return }
            items = ((try? await c.torrents()) ?? []).map { t in
                let paused = t.isPaused
                return Item(id: t.id, title: t.name ?? "Unknown", progress: t.fractionDone, state: t.state ?? "—",
                            isPaused: paused, isError: t.hasError, size: t.totalSize.map(Double.init),
                            seedingSeconds: t.seedingTime, ratio: t.ratio,
                            togglePause: { if paused { try? await c.resume(hashes: [t.id]) } else { try? await c.pause(hashes: [t.id]) } },
                            remove: { try? await c.remove(hash: t.id, removeData: $0) },
                            recheck: { try? await c.forceRecheck(hashes: [t.id]) })
            }
        case .sabnzbd:
            guard let c = store.sabnzbdClient(for: instance) else { items = []; return }
            items = ((try? await c.queue().slots) ?? []).map { s in
                let paused = s.isPaused
                return Item(id: s.nzoId, title: s.filename ?? "Unknown", progress: s.progress, state: s.status ?? "—",
                            isPaused: paused, isError: false, size: s.sizeBytes,
                            togglePause: { if paused { try? await c.resume(nzoId: s.nzoId) } else { try? await c.pause(nzoId: s.nzoId) } },
                            remove: { try? await c.delete(nzoId: s.nzoId, deleteFiles: $0) })
            }
        case .nzbget:
            guard let c = store.nzbgetClient(for: instance) else { items = []; return }
            items = ((try? await c.groups()) ?? []).map { g in
                let paused = g.isPaused
                return Item(id: "\(g.nzbID)", title: g.nzbName ?? "Unknown", progress: g.progress,
                            state: paused ? "Paused" : (g.status?.capitalized ?? "—"),
                            isPaused: paused, isError: false, size: g.sizeBytes,
                            togglePause: { if paused { _ = try? await c.resumeGroup(id: g.nzbID) } else { _ = try? await c.pauseGroup(id: g.nzbID) } },
                            remove: { _ = try? await c.deleteGroup(id: g.nzbID, deleteFiles: $0) })
            }
        default:
            items = []
        }
    }

    func pauseAll(store: InstanceStore) async {
        switch instance.type {
        case .qbittorrent: if let c = store.qbittorrentClient(for: instance) { try? await c.pause(hashes: nil) }
        case .sabnzbd: if let c = store.sabnzbdClient(for: instance) { try? await c.pauseAll() }
        case .nzbget: if let c = store.nzbgetClient(for: instance) { _ = try? await c.pauseAll() }
        case .transmission: if let c = store.transmissionClient(for: instance) { let ids = (try? await c.torrents().map(\.id)) ?? []; if !ids.isEmpty { try? await c.stop(ids: ids) } }
        case .deluge: if let c = store.delugeClient(for: instance) { let h = (try? await c.torrents().map(\.id)) ?? []; if !h.isEmpty { try? await c.pause(hashes: h) } }
        default: break
        }
    }

    func resumeAll(store: InstanceStore) async {
        switch instance.type {
        case .qbittorrent: if let c = store.qbittorrentClient(for: instance) { try? await c.resume(hashes: nil) }
        case .sabnzbd: if let c = store.sabnzbdClient(for: instance) { try? await c.resumeAll() }
        case .nzbget: if let c = store.nzbgetClient(for: instance) { _ = try? await c.resumeAll() }
        case .transmission: if let c = store.transmissionClient(for: instance) { let ids = (try? await c.torrents().map(\.id)) ?? []; if !ids.isEmpty { try? await c.start(ids: ids) } }
        case .deluge: if let c = store.delugeClient(for: instance) { let h = (try? await c.torrents().map(\.id)) ?? []; if !h.isEmpty { try? await c.resume(hashes: h) } }
        default: break
        }
    }

    func addMagnet(_ url: String, store: InstanceStore) async {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            switch instance.type {
            case .qbittorrent: if let c = store.qbittorrentClient(for: instance) { try await c.add(urls: [trimmed]) }
            case .transmission: if let c = store.transmissionClient(for: instance) { try await c.addMagnet(trimmed) }
            case .deluge: if let c = store.delugeClient(for: instance) { try await c.addMagnet(trimmed) }
            case .sabnzbd: if let c = store.sabnzbdClient(for: instance) { try await c.addURL(trimmed) }
            default: break
            }
            status = "Added to \(instance.name)."
        } catch {
            status = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    func setSpeedLimit(_ value: String, store: InstanceStore) async {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        do {
            switch instance.type {
            case .sabnzbd: if let c = store.sabnzbdClient(for: instance) { try await c.setSpeedLimit(trimmed) }
            case .nzbget: if let c = store.nzbgetClient(for: instance), let kbps = Int(trimmed) { _ = try await c.setRate(kbps: kbps) }
            default: break
            }
            status = "Speed limit updated."
        } catch {
            status = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}

struct DownloadClientView: View {
    @EnvironmentObject private var instanceStore: InstanceStore
    @StateObject private var model: DownloadClientViewModel
    @State private var pendingRemoval: DownloadClientViewModel.Item?
    @State private var showAddMagnet = false
    @State private var magnet = ""
    @State private var showSpeed = false
    @State private var speed = ""

    init(instance: ServiceInstance) {
        _model = StateObject(wrappedValue: DownloadClientViewModel(instance: instance))
    }

    var body: some View {
        Group {
            if model.items.isEmpty && !model.isLoading {
                ContentUnavailableLabel(
                    "Nothing here",
                    systemImage: "tray",
                    description: "This client has no active items."
                )
            } else {
                List {
                    ForEach(model.items) { item in
                        row(item)
                            .swipeActions(edge: .trailing) {
                                if item.remove != nil {
                                    Button(role: .destructive) { pendingRemoval = item } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if item.togglePause != nil {
                                    Button {
                                        Task { await item.togglePause?(); await model.load(store: instanceStore) }
                                    } label: {
                                        Label(item.isPaused ? "Resume" : "Pause",
                                              systemImage: item.isPaused ? "play.fill" : "pause.fill")
                                    }
                                    .tint(item.isPaused ? .green : .orange)
                                }
                                if let recheck = item.recheck {
                                    Button {
                                        Task { await recheck(); await model.load(store: instanceStore) }
                                    } label: { Label("Recheck", systemImage: "arrow.triangle.2.circlepath") }
                                    .tint(.blue)
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(model.instance.name)
        .overlay { if model.isLoading && model.items.isEmpty { ProgressView() } }
        .overlay(alignment: .bottom) { Toast(message: model.status) { model.status = nil } }
        .refreshable { await model.load(store: instanceStore) }
        .task { await model.load(store: instanceStore) }
        .toolbar { toolbarMenu }
        .alert("Add magnet or URL", isPresented: $showAddMagnet) {
            TextField("magnet:?xt=… or https://…", text: $magnet)
            Button("Add") {
                let url = magnet; magnet = ""
                Task { await model.addMagnet(url, store: instanceStore); await model.load(store: instanceStore) }
            }
            Button("Cancel", role: .cancel) { magnet = "" }
        }
        .alert(speedAlertTitle, isPresented: $showSpeed) {
            TextField(speedPrompt, text: $speed)
            Button("Set") {
                let value = speed; speed = ""
                Task { await model.setSpeedLimit(value, store: instanceStore) }
            }
            Button("Cancel", role: .cancel) { speed = "" }
        }
        .confirmationDialog("Remove from \(model.instance.name)?", isPresented: .constant(pendingRemoval != nil), titleVisibility: .visible) {
            if let item = pendingRemoval {
                Button("Remove only") {
                    Task { await item.remove?(false); await model.load(store: instanceStore) }; pendingRemoval = nil
                }
                Button("Remove and delete data", role: .destructive) {
                    Task { await item.remove?(true); await model.load(store: instanceStore) }; pendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        }
    }

    private var speedAlertTitle: String { "Speed limit" }
    private var speedPrompt: String { model.instance.type == .nzbget ? "KB/s (0 = unlimited)" : "e.g. 500K or 0 for unlimited" }

    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if model.supportsAdd {
                    Button { showAddMagnet = true } label: {
                        Label(model.isTorrentClient ? "Add magnet/URL" : "Add NZB URL", systemImage: "plus")
                    }
                    Divider()
                }
                Button { Task { await model.pauseAll(store: instanceStore); await model.load(store: instanceStore) } } label: {
                    Label("Pause All", systemImage: "pause.fill")
                }
                Button { Task { await model.resumeAll(store: instanceStore); await model.load(store: instanceStore) } } label: {
                    Label("Resume All", systemImage: "play.fill")
                }
                if model.supportsSpeedLimit {
                    Button { showSpeed = true } label: { Label("Speed limit…", systemImage: "speedometer") }
                }
                Divider()
                Button { Task { await model.load(store: instanceStore) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
        }
    }

    private func row(_ item: DownloadClientViewModel.Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(item.title).font(.subheadline).lineLimit(2)
                Spacer(minLength: 8)
                controls(item)
            }
            ProgressView(value: item.progress).tint(item.isError ? .red : Theme.teal)
            HStack(spacing: 10) {
                StatusBadge(text: item.state, color: item.isError ? .red : (item.isPaused ? .secondary : Theme.teal))
                if let seed = SeedFormat.duration(item.seedingSeconds) {
                    Label(seed, systemImage: "timer")
                }
                if let ratio = item.ratio, ratio > 0 {
                    Label(String(format: "%.2f", ratio), systemImage: "arrow.up.arrow.down")
                }
                Spacer()
                Text("\(Format.bytes(item.size)) · \(Format.percent(item.progress))")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// Inline icon controls mirroring the unified queue: play/pause, recheck, remove.
    private func controls(_ item: DownloadClientViewModel.Item) -> some View {
        HStack(spacing: 4) {
            if item.togglePause != nil {
                iconButton(item.isPaused ? "play.fill" : "pause.fill",
                           tint: item.isPaused ? .green : .orange,
                           help: item.isPaused ? "Resume" : "Pause") {
                    await item.togglePause?()
                }
            }
            if item.recheck != nil {
                iconButton("arrow.triangle.2.circlepath", tint: .blue, help: "Recheck") {
                    await item.recheck?()
                }
            }
            if item.remove != nil {
                Button(role: .destructive) { pendingRemoval = item } label: {
                    Image(systemName: "trash").font(.body)
                        .frame(width: 30, height: 30)
                        .foregroundStyle(.red)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
        }
    }

    private func iconButton(_ symbol: String, tint: Color, help: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action(); await model.load(store: instanceStore) }
        } label: {
            Image(systemName: symbol).font(.body)
                .frame(width: 30, height: 30)
                .foregroundStyle(tint)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
