import SwiftUI
import NautilarrCore

/// How the unified queue is ordered.
enum DownloadSort: String, CaseIterable, Identifiable {
    case progress, name, size, seedTime, status
    var id: String { rawValue }
    var label: String {
        switch self {
        case .progress: return "Progress"
        case .name: return "Name"
        case .size: return "Size"
        case .seedTime: return "Seed time"
        case .status: return "Status"
        }
    }
    var symbol: String {
        switch self {
        case .progress: return "chart.bar"
        case .name: return "textformat"
        case .size: return "internaldrive"
        case .seedTime: return "timer"
        case .status: return "circle.grid.2x2"
        }
    }
}

/// Unified download queue across all media-management services and download
/// clients. Service tabs, status filtering and sorting; each item has inline
/// play/pause, recheck and remove controls. Auto-refreshes while visible.
struct DownloadsView: View {
    @EnvironmentObject private var instanceStore: InstanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var model = DownloadsViewModel()
    @State private var pendingRemoval: UnifiedDownload?
    @State private var sourceFilter: String?            // nil = all services
    @State private var statusFilter: DownloadStatusCategory?
    @State private var sort: DownloadSort = .progress
    /// Drives the pushed interactive-search section for a stuck *arr item.
    @State private var interactiveTarget: InteractiveSearchTarget?
    /// One transient confirmation banner for every queue action (retry, re-search,
    /// pause, recheck, remove, seed-limit) so a tap always shows it took effect.
    @State private var toast: String?
    /// Tracks the banner-wide "Retry all" so it can show a spinner and lock out
    /// re-taps while the imports are being re-processed.
    @State private var isRetryingAll = false

    var body: some View {
        Group {
            if !model.hasServices {
                ContentUnavailableLabel(
                    "No downloads",
                    systemImage: "arrow.down.circle",
                    description: "Add a service in Settings to see its download queue."
                )
            } else {
                VStack(spacing: 0) {
                    serviceTabs
                    statusBar
                    stuckBanner
                    queueList
                }
            }
        }
        .navigationDestination(item: $interactiveTarget) { target in
            InteractiveReleaseSearchView(title: target.title, load: interactiveLoader(target))
        }
        .overlay { if model.isLoading && model.items.isEmpty { ProgressView() } }
        .overlay(alignment: .bottom) { Toast(message: toast) { toast = nil } }
        .task(id: settings.autoRefreshSeconds) { await autoRefreshLoop() }
        .toolbar {
            if model.hasServices { globalActions }
            // When a single download client is selected via the service filter,
            // offer its per-client management (add magnet/NZB, speed limit).
            if let client = selectedClientInstance {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        DownloadClientView(instance: client)
                    } label: {
                        Label("Manage client", systemImage: "slider.horizontal.3")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                RefreshSpinnerButton(isLoading: model.isLoading) { Task { await reload() } }
            }
        }
        .confirmationDialog("Remove from queue?", isPresented: .constant(pendingRemoval != nil), titleVisibility: .visible) {
            if let pendingRemoval {
                Button("Remove from queue only") {
                    Task { await pendingRemoval.remove?(false); await reload(); present("Removed from queue.") }
                    self.pendingRemoval = nil
                }
                Button("Remove and delete from disk", role: .destructive) {
                    Task { await pendingRemoval.remove?(true); await reload(); present("Removed and deleted from disk.") }
                    self.pendingRemoval = nil
                }
                if pendingRemoval.blocklist != nil {
                    Button("Blocklist & search again") {
                        Task { await pendingRemoval.blocklist?(); await reload(); present("Blocklisted — searching again.") }
                        self.pendingRemoval = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        }
    }

    // MARK: Stuck imports (Sonarr/Radarr waiting to import)

    /// *arr queue items that finished downloading but are stuck/failed in import.
    private var stuckImports: [UnifiedDownload] { model.items.filter(\.isStuckImport) }

    @ViewBuilder
    private var stuckBanner: some View {
        if !stuckImports.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stuckImports.count) waiting to import")
                        .font(.subheadline.weight(.semibold))
                    Text("Finished downloading, but couldn't be imported automatically.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    Task {
                        isRetryingAll = true
                        let count = await retryAllImports()
                        isRetryingAll = false
                        present(count == 1 ? "Retrying 1 import…" : "Retrying \(count) imports…")
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isRetryingAll {
                            ProgressView().controlSize(.mini).tint(.white)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Retry all")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isRetryingAll)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    /// Re-processes monitored downloads on each affected instance once. Returns
    /// the number of instances nudged, so the caller can confirm the action.
    @discardableResult
    private func retryAllImports() async -> Int {
        var done = Set<String>()
        for item in stuckImports {
            guard let retry = item.retryImport else { continue }
            if done.insert(item.instanceName).inserted { await retry() }
        }
        await reload()
        return done.count
    }

    /// Shows a transient confirmation banner for a completed queue action.
    private func present(_ message: String) {
        withAnimation { toast = message }
    }

    /// Builds the interactive-search loader for a stuck item's deep-link.
    private func interactiveLoader(_ target: InteractiveSearchTarget) -> () async throws -> [InteractiveRelease] {
        let instance = instanceStore.instancesInActiveNetwork.first { $0.id == target.instanceID }
        switch target.serviceType {
        case .sonarr:
            if let instance, let client = instanceStore.sonarrClient(for: instance), let episodeId = target.episodeId {
                return InteractiveSearchLoader.sonarrEpisode(client, episodeId: episodeId)
            }
        case .radarr:
            if let instance, let client = instanceStore.radarrClient(for: instance), let movieId = target.movieId {
                return InteractiveSearchLoader.radarrMovie(client, movieId: movieId)
            }
        default: break
        }
        return { throw APIError.invalidResponse }
    }

    /// Opens the interactive search for a queue item, if it can be deep-linked.
    private func openInteractiveSearch(_ download: UnifiedDownload) {
        guard download.supportsInteractiveSearch, let instanceID = download.instanceID else { return }
        interactiveTarget = InteractiveSearchTarget(
            id: download.id, serviceType: download.serviceType, instanceID: instanceID,
            title: download.title, movieId: download.movieId, episodeId: download.episodeId)
    }

    // MARK: Service tabs

    private var serviceTabs: some View {
        let sources = Array(Set(model.items.map(\.instanceName))).sorted()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", systemImage: "square.stack.3d.up", count: model.items.count,
                           isSelected: sourceFilter == nil) { sourceFilter = nil }
                ForEach(sources, id: \.self) { source in
                    let type = model.items.first { $0.instanceName == source }?.serviceType
                    FilterChip(title: source, serviceType: type,
                               count: model.items.filter { $0.instanceName == source }.count,
                               isSelected: sourceFilter == source) {
                        sourceFilter = (sourceFilter == source) ? nil : source
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        // Pin the height: two horizontal ScrollViews stacked in a VStack can
        // otherwise collapse the first one to zero height.
        .frame(height: 56)
    }

    // MARK: Status filter bar

    private var statusBar: some View {
        let scoped = scopedItems
        let present = DownloadStatusCategory.allCases.filter { cat in scoped.contains { $0.category == cat } }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All status", systemImage: "line.3.horizontal.decrease.circle",
                           count: scoped.count, isSelected: statusFilter == nil) { statusFilter = nil }
                ForEach(present) { cat in
                    FilterChip(title: cat.label, systemImage: cat.symbol, tint: cat.color,
                               count: scoped.filter { $0.category == cat }.count,
                               isSelected: statusFilter == cat) {
                        statusFilter = (statusFilter == cat) ? nil : cat
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(height: 46)
    }

    // MARK: Queue list

    @ViewBuilder
    private var queueList: some View {
        let items = filtered
        if items.isEmpty && !model.isLoading {
            ContentUnavailableLabel(
                "Nothing here",
                systemImage: "checkmark.circle",
                description: "No downloads match the current filters."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(items) { download in
                    DownloadRow(download: download, reload: reload, notify: present,
                                onRemove: { pendingRemoval = download },
                                onInteractiveSearch: { openInteractiveSearch(download) })
                        .swipeActions(edge: .trailing) {
                            if download.remove != nil {
                                Button(role: .destructive) { pendingRemoval = download } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if download.togglePause != nil {
                                let wasPaused = download.isPaused
                                Button {
                                    Task {
                                        await download.togglePause?(); await reload()
                                        present(wasPaused ? "Resuming…" : "Pausing…")
                                    }
                                } label: {
                                    Label(wasPaused ? "Resume" : "Pause",
                                          systemImage: wasPaused ? "play.fill" : "pause.fill")
                                }
                                .tint(wasPaused ? .green : .orange)
                            }
                        }
                }
                .tintedCards()
            }
            // Scope pull-to-refresh to the queue list only. Applying it higher up
            // makes the horizontal filter ScrollViews refreshable too, so a
            // vertical drag on the filter chips triggers — and jams — the refresh.
            .refreshable { await reload() }
        }
    }

    // MARK: Filtering & sorting

    /// The download-client instance currently isolated by the service filter, if
    /// any — used to surface its per-client management screen.
    private var selectedClientInstance: ServiceInstance? {
        guard let sourceFilter else { return nil }
        let clientTypes: Set<ServiceType> = [.qbittorrent, .transmission, .deluge, .sabnzbd, .nzbget]
        return instanceStore.instancesInActiveNetwork.first { $0.name == sourceFilter && clientTypes.contains($0.type) }
    }

    /// Items after the service-tab filter (used to compute available statuses).
    private var scopedItems: [UnifiedDownload] {
        guard let sourceFilter else { return model.items }
        return model.items.filter { $0.instanceName == sourceFilter }
    }

    private var filtered: [UnifiedDownload] {
        var list = scopedItems
        if let statusFilter { list = list.filter { $0.category == statusFilter } }
        return list.sorted(by: comparator)
    }

    private func comparator(_ a: UnifiedDownload, _ b: UnifiedDownload) -> Bool {
        switch sort {
        case .progress: return a.progress > b.progress
        case .name: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        case .size: return (a.size ?? 0) > (b.size ?? 0)
        case .seedTime: return (a.seedingSeconds ?? 0) > (b.seedingSeconds ?? 0)
        case .status: return a.category.label < b.category.label
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var globalActions: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(DownloadSort.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                Divider()
                Button {
                    Task { await model.pauseAllClients(store: instanceStore); await reload(); present("Paused all download clients.") }
                } label: { Label("Pause All", systemImage: "pause.fill") }
                Button {
                    Task { await model.resumeAllClients(store: instanceStore); await reload(); present("Resumed all download clients.") }
                } label: { Label("Resume All", systemImage: "play.fill") }
                Divider()
                Button {
                    Task { await reload() }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: Loading

    private func reload() async {
        await model.load(store: instanceStore, disabledClientIDs: settings.disabledClientIDs)
        environment.activeDownloadCount = model.items.count
        await model.enforceSeedLimit(enabled: settings.seedLimitEnabled,
                                     byDays: settings.seedLimitByDays, maxDays: settings.maxSeedDays,
                                     byRatio: settings.seedLimitByRatio, maxRatio: settings.maxSeedRatio,
                                     action: settings.seedLimitAction)
        // Route the seed-limit janitor's result through the shared toast.
        if let status = model.seedLimitStatus { present(status); model.seedLimitStatus = nil }
    }

    /// Polls on the configured interval while on screen. SwiftUI cancels the
    /// `.task` when the view disappears, ending the loop.
    private func autoRefreshLoop() async {
        let interval = max(2, settings.autoRefreshSeconds)
        while !Task.isCancelled {
            await reload()
            try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
        }
    }
}

// MARK: - Filter chip

/// A pill that doubles as a tab/filter. Optionally shows a service logo.
struct FilterChip: View {
    var title: String
    var systemImage: String? = nil
    var serviceType: ServiceType? = nil
    var tint: Color = Theme.teal
    var count: Int? = nil
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let serviceType {
                    ServiceIcon(type: serviceType, size: 16)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).lineLimit(1)
                if let count {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(isSelected ? Color.white.opacity(0.25) : tint.opacity(0.18), in: Capsule())
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(isSelected ? .white : .primary)
            .background {
                if isSelected {
                    Capsule().fill(tint)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(Color.hairline.opacity(0.5)))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Download row

private struct DownloadRow: View {
    let download: UnifiedDownload
    let reload: () async -> Void
    /// Surfaces a confirmation banner after an action completes.
    var notify: (String) -> Void = { _ in }
    let onRemove: () -> Void
    var onInteractiveSearch: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                ServiceIcon(type: download.serviceType, size: 18)
                Text(download.title).font(.subheadline).lineLimit(2)
                Spacer(minLength: 8)
                controls
            }
            ProgressView(value: download.progress).tint(download.category.color)
            HStack(spacing: 8) {
                StatusBadge(text: download.category.label, color: download.category.color)
                if let client = download.downloadClient { Text(client) }
                if let seed = SeedFormat.duration(download.seedingSeconds) {
                    Label(seed, systemImage: "timer")
                }
                if let ratio = download.ratio, ratio > 0 {
                    Label(String(format: "%.2f", ratio), systemImage: "arrow.up.arrow.down")
                }
                Spacer()
                Text("\(Format.bytes(download.size)) · \(Format.percent(download.progress))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if let error = download.errorMessage, !error.isEmpty {
                Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(2)
            }
            if download.isStuckImport { importActions }
            Text(download.instanceName).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    /// Reprocess actions for an *arr item stuck waiting to import: open its
    /// interactive search, retry the import, or blocklist & search again. The
    /// chips share one equal-width row so labels stay on a single line at a
    /// consistent size instead of one wrapping when a longer neighbour crowds it.
    @ViewBuilder
    private var importActions: some View {
        HStack(spacing: 8) {
            if download.supportsInteractiveSearch {
                DownloadActionChip(title: "Search", systemImage: "magnifyingglass", tint: Theme.teal,
                                   navigate: onInteractiveSearch)
            }
            if download.retryImport != nil {
                DownloadActionChip(title: "Retry import", systemImage: "arrow.clockwise", tint: .blue) {
                    await download.retryImport?(); await reload(); notify("Retrying import…")
                }
            }
            if download.blocklist != nil {
                DownloadActionChip(title: "Re-search", systemImage: "arrow.triangle.2.circlepath", tint: .orange) {
                    await download.blocklist?(); await reload(); notify("Blocklisted — searching again.")
                }
            }
        }
        .padding(.top, 2)
    }

    /// Inline icon controls: play/pause, recheck and remove.
    private var controls: some View {
        HStack(spacing: 4) {
            if download.togglePause != nil {
                let paused = download.isPaused
                AsyncGlassIconButton(
                    symbol: paused ? "play.fill" : "pause.fill",
                    tint: paused ? .green : .orange,
                    help: paused ? "Resume" : "Pause"
                ) {
                    await download.togglePause?(); await reload(); notify(paused ? "Resuming…" : "Pausing…")
                }
            }
            if download.recheck != nil {
                AsyncGlassIconButton(symbol: "arrow.triangle.2.circlepath", tint: .blue, help: "Recheck") {
                    await download.recheck?(); await reload(); notify("Rechecking…")
                }
            }
            if download.remove != nil {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                        .font(.body)
                        .frame(width: 30, height: 30)
                        .foregroundStyle(.red)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
        }
    }
}

// MARK: - Reusable download-action controls

/// An equal-width action pill for a download row. The async variant shows an
/// inline spinner and disables itself while running, so a tap is unmistakably
/// acknowledged and can't fire twice; the navigate variant just triggers (its
/// pushed screen is its own feedback). Equal width + single-line text keep the
/// row's chips visually consistent.
private struct DownloadActionChip: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let showsProgress: Bool
    let action: () async -> Void
    @State private var running = false

    /// Async action: shows a spinner and locks out re-taps until it finishes.
    init(title: LocalizedStringKey, systemImage: String, tint: Color, action: @escaping () async -> Void) {
        self.title = title; self.systemImage = systemImage; self.tint = tint
        self.showsProgress = true; self.action = action
    }

    /// Navigation action: fires immediately, no spinner.
    init(title: LocalizedStringKey, systemImage: String, tint: Color, navigate: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.tint = tint
        self.showsProgress = false; self.action = { navigate() }
    }

    var body: some View {
        Button {
            guard !running else { return }
            if showsProgress {
                running = true
                Task { await action(); running = false }
            } else {
                Task { await action() }  // navigate: completes immediately, no spinner
            }
        } label: {
            HStack(spacing: 5) {
                if running {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.caption2.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(running)
    }
}

/// A circular glass icon control that swaps its glyph for a spinner and disables
/// itself while its async action runs — so inline pause/resume and recheck taps
/// show progress and can't double-fire.
private struct AsyncGlassIconButton: View {
    let symbol: String
    let tint: Color
    let help: String
    let action: () async -> Void
    @State private var running = false

    var body: some View {
        Button {
            guard !running else { return }
            running = true
            Task { await action(); running = false }
        } label: {
            Group {
                if running {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: symbol).font(.body)
                }
            }
            .frame(width: 30, height: 30)
            .foregroundStyle(tint)
            .glassCircle()
        }
        .buttonStyle(.plain)
        .disabled(running)
        .help(help)
    }
}

// MARK: - Interactive-search deep-link target

/// Identifies a stuck *arr queue item whose interactive search is being pushed
/// from the Downloads queue.
struct InteractiveSearchTarget: Identifiable, Hashable {
    let id: String
    let serviceType: ServiceType
    let instanceID: UUID
    let title: String
    var movieId: Int? = nil
    var episodeId: Int? = nil
}
