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
                    queueList
                }
            }
        }
        .overlay { if model.isLoading && model.items.isEmpty { ProgressView() } }
        .overlay(alignment: .bottom) { Toast(message: model.seedLimitStatus) { model.seedLimitStatus = nil } }
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
                    Task { await pendingRemoval.remove?(false); await reload() }
                    self.pendingRemoval = nil
                }
                Button("Remove and delete from disk", role: .destructive) {
                    Task { await pendingRemoval.remove?(true); await reload() }
                    self.pendingRemoval = nil
                }
                if pendingRemoval.blocklist != nil {
                    Button("Blocklist & search again") {
                        Task { await pendingRemoval.blocklist?(); await reload() }
                        self.pendingRemoval = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        }
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
                    DownloadRow(download: download, reload: reload) { pendingRemoval = download }
                        .swipeActions(edge: .trailing) {
                            if download.remove != nil {
                                Button(role: .destructive) { pendingRemoval = download } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if download.togglePause != nil {
                                Button {
                                    Task { await download.togglePause?(); await reload() }
                                } label: {
                                    Label(download.isPaused ? "Resume" : "Pause",
                                          systemImage: download.isPaused ? "play.fill" : "pause.fill")
                                }
                                .tint(download.isPaused ? .green : .orange)
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
                    Task { await model.pauseAllClients(store: instanceStore); await reload() }
                } label: { Label("Pause All", systemImage: "pause.fill") }
                Button {
                    Task { await model.resumeAllClients(store: instanceStore); await reload() }
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
    let onRemove: () -> Void

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
            Text(download.instanceName).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    /// Inline icon controls: play/pause, recheck and remove.
    private var controls: some View {
        HStack(spacing: 4) {
            if download.togglePause != nil {
                iconButton(download.isPaused ? "play.fill" : "pause.fill",
                           tint: download.isPaused ? .green : .orange,
                           help: download.isPaused ? "Resume" : "Pause") {
                    await download.togglePause?()
                }
            }
            if download.recheck != nil {
                iconButton("arrow.triangle.2.circlepath", tint: .blue, help: "Recheck") {
                    await download.recheck?()
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

    private func iconButton(_ symbol: String, tint: Color, help: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action(); await reload() }
        } label: {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 30, height: 30)
                .foregroundStyle(tint)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
