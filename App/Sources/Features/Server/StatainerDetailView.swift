import SwiftUI
import NautilarrCore
import StatainerKit

/// A Statainer dashboard: a host/Docker overview plus the live container list
/// with per-container CPU/RAM, start/stop/restart and one-tap image updates.
/// Containers can be filtered (by status or search) and sorted, and an
/// update-available dot flags containers with a newer image.
struct StatainerDetailView: View {
    let instance: ServiceInstance
    @EnvironmentObject private var instanceStore: InstanceStore
    @EnvironmentObject private var settings: AppSettings

    @State private var dashboard: StatainerDashboard?
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var searchText = ""
    @State private var statusFilter: StatusFilter = .all
    @State private var sort: ContainerSort = .name

    /// Containers with an in-flight action (start/stop/restart/update).
    @State private var busyIDs: Set<String> = []
    @State private var actionError: String?
    @State private var confirmUpdateAll = false

    private var client: StatainerClient? { instanceStore.statainerClient(for: instance) }

    // MARK: - Filtering & sorting

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all, running, stopped, paused, updates
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .all: return "All"
            case .running: return "Running"
            case .stopped: return "Stopped"
            case .paused: return "Paused"
            case .updates: return "Updates"
            }
        }
        /// SF Symbol shown on the filter chip so its meaning is obvious at a glance.
        var systemImage: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .running: return "play.fill"
            case .stopped: return "stop.fill"
            case .paused: return "pause.fill"
            case .updates: return "arrow.up.circle"
            }
        }
        /// Accent colour for the chip's icon (reflects the status semantics).
        var tint: Color {
            switch self {
            case .all: return Theme.teal
            case .running: return .green
            case .stopped: return .red
            case .paused: return .orange
            case .updates: return .orange
            }
        }
        func matches(_ c: StatainerContainer) -> Bool {
            switch self {
            case .all: return true
            case .running: return c.isRunning
            case .paused: return c.isPaused
            case .stopped: return !c.isRunning && !c.isPaused
            case .updates: return c.hasUpdate
            }
        }
    }

    enum ContainerSort: String, CaseIterable, Identifiable {
        case name, cpu, memory, status, updates
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .name: return "Name"
            case .cpu: return "CPU usage"
            case .memory: return "Memory usage"
            case .status: return "Status"
            case .updates: return "Updates first"
            }
        }
    }

    private var allContainers: [StatainerContainer] { dashboard?.containers ?? [] }

    private func count(_ filter: StatusFilter) -> Int {
        allContainers.filter { filter.matches($0) }.count
    }

    private var visibleContainers: [StatainerContainer] {
        var items = allContainers.filter { statusFilter.matches($0) }
        if !searchText.isEmpty {
            items = items.filter {
                $0.displayName.localizedStandardContains(searchText)
                    || ($0.image?.localizedStandardContains(searchText) ?? false)
                    || ($0.composeService?.localizedStandardContains(searchText) ?? false)
            }
        }
        switch sort {
        case .name:
            items.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .cpu:
            items.sort { ($0.cpu ?? -1) > ($1.cpu ?? -1) }
        case .memory:
            items.sort { ($0.mem ?? -1) > ($1.mem ?? -1) }
        case .status:
            items.sort { (stateRank($0), $0.displayName) < (stateRank($1), $1.displayName) }
        case .updates:
            items.sort { ($0.hasUpdate ? 0 : 1, $0.displayName) < ($1.hasUpdate ? 0 : 1, $1.displayName) }
        }
        return items
    }

    /// Running containers first, then paused, then stopped — for the status sort.
    private func stateRank(_ c: StatainerContainer) -> Int {
        if c.isRunning { return 0 }
        if c.isPaused { return 1 }
        return 2
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            controls
            list
        }
        .navigationTitle(instance.name)
        .appBackground(settings.background)
        .overlay { if isLoading && dashboard == nil { ProgressView() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RefreshSpinnerButton(isLoading: isLoading) { Task { await load() } }
            }
        }
        .task { await load() }
        .alert("Action failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
        .confirmationDialog("Update all containers with a newer image?", isPresented: $confirmUpdateAll, titleVisibility: .visible) {
            Button("Update all") { updateAll() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Controls header

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                SearchField(prompt: "Filter containers", text: $searchText)
                sortMenu
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StatusFilter.allCases) { filter in
                        statusChip(filter)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// A status filter chip: an icon (so its meaning is obvious), the localized
    /// label and the matching container count.
    private func statusChip(_ filter: StatusFilter) -> some View {
        let selected = statusFilter == filter
        return Button { statusFilter = filter } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.systemImage)
                    .font(.caption)
                    .foregroundStyle(selected ? .white : filter.tint)
                Text(filter.label).lineLimit(1)
                Text("\(count(filter))")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(selected ? Color.white.opacity(0.25) : Theme.teal.opacity(0.18), in: Capsule())
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(selected ? .white : .primary)
            .background {
                if selected {
                    Capsule().fill(Theme.teal)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(Color.hairline.opacity(0.5)))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(ContainerSort.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.title3)
                .foregroundStyle(Theme.teal)
        }
        .accessibilityLabel("Sort containers")
    }

    // MARK: List

    private var list: some View {
        List {
            if let error = errorMessage {
                Section { ErrorBanner(message: error) }.tintedCards()
            }

            if let system = dashboard?.system {
                Section("Host") { systemRows(system) }.tintedCards()
            }

            if let dashboard, dashboard.updatesAvailable > 0 {
                Section {
                    Button { confirmUpdateAll = true } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill").foregroundStyle(.orange)
                            Text("\(dashboard.updatesAvailable) update(s) available")
                            Spacer()
                            Text("Update all").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.teal)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .tintedCards()
            }

            Section {
                if visibleContainers.isEmpty {
                    Text(allContainers.isEmpty ? "No containers." : "No containers match the filter.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleContainers) { container in
                        ContainerRow(
                            container: container,
                            isBusy: busyIDs.contains(container.id),
                            action: { run($0, on: container) }
                        )
                    }
                }
            } header: {
                Text("Containers — \(dashboard?.runningCount ?? 0)/\(allContainers.count) running")
            }
            .tintedCards()
        }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func systemRows(_ system: StatainerSystem) -> some View {
        if let hostname = system.hostname { LabeledContent("Hostname", value: hostname) }
        if let os = system.operatingSystem {
            LabeledContent("OS", value: [os, system.architecture].compactMap { $0 }.joined(separator: " · "))
        }
        if let docker = system.dockerVersion { LabeledContent("Docker", value: docker) }
        if let cores = system.cpuCores { LabeledContent("CPU", value: "\(cores) cores") }
        if let bytes = system.memoryTotalBytes { LabeledContent("Memory", value: Format.bytes(bytes)) }
        if let images = system.images { LabeledContent("Images", value: "\(images)") }
        HStack(spacing: 8) {
            Text("Containers")
            Spacer()
            countPill("\(system.containersRunning ?? dashboard?.runningCount ?? 0)", "play.fill", .green)
            if (system.containersPaused ?? 0) > 0 { countPill("\(system.containersPaused ?? 0)", "pause.fill", .orange) }
            countPill("\(system.containersStopped ?? 0)", "stop.fill", .secondary)
        }
        if let version = system.appVersion {
            Text("Statainer \(version)").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func countPill(_ text: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9))
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Actions

    private func run(_ action: StatainerContainerAction, on container: StatainerContainer) {
        guard let client, !busyIDs.contains(container.id) else { return }
        busyIDs.insert(container.id)
        Task {
            defer { busyIDs.remove(container.id) }
            do {
                _ = try await client.perform(action, on: container.id)
                await load()
            } catch {
                actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            }
        }
    }

    private func updateAll() {
        let targets = allContainers.filter(\.hasUpdate)
        guard let client, !targets.isEmpty else { return }
        let ids = targets.map(\.id)
        busyIDs.formUnion(ids)
        Task {
            defer { busyIDs.subtract(ids) }
            var lastError: String?
            for id in ids {
                do { _ = try await client.update(id) }
                catch { lastError = (error as? APIError)?.localizedDescription ?? error.localizedDescription }
            }
            await load()
            if let lastError { actionError = lastError }
        }
    }

    private func load() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            dashboard = try await client.dashboard()
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Container row

private struct ContainerRow: View {
    let container: StatainerContainer
    let isBusy: Bool
    let action: (StatainerContainerAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Circle().fill(stateColor).frame(width: 8, height: 8)
                    Text(container.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if container.hasUpdate {
                        Circle().fill(.orange).frame(width: 7, height: 7)
                            .accessibilityLabel("Update available")
                    }
                    Spacer(minLength: 4)
                    StatusBadge(text: (container.status ?? "—").capitalized, color: stateColor)
                }
                if let image = container.image, !image.isEmpty {
                    Text(image).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                metrics
            }
            actions
        }
        .padding(.vertical, 2)
    }

    private var metrics: some View {
        HStack(spacing: 6) {
            if let cpu = container.cpu {
                metricChip("cpu", String(format: "%.1f%%", cpu))
            }
            if let mem = container.mem {
                let usage = container.memoryUsageBytes.map { " · \(Format.bytes($0))" } ?? ""
                metricChip("memorychip", String(format: "%.0f%%", mem) + usage)
            }
            if let uptime = container.uptimeSec, uptime > 0 {
                metricChip("clock", Format.duration(uptime))
            }
        }
    }

    private func metricChip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9))
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var actions: some View {
        if isBusy {
            ProgressView().frame(width: 30, height: 30)
        } else {
            HStack(spacing: 6) {
                if container.isRunning {
                    iconButton("stop.fill", .red) { action(.stop) }
                } else {
                    iconButton("play.fill", .green) { action(.start) }
                }
                iconButton("arrow.clockwise", Theme.teal) { action(.restart) }
                if container.hasUpdate {
                    iconButton("arrow.up.circle.fill", .orange) { action(.update) }
                }
            }
        }
    }

    private func iconButton(_ symbol: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.15), in: Circle())
                .foregroundStyle(tint)
        }
        .buttonStyle(.borderless)
    }

    private var stateColor: Color {
        switch container.state {
        case .running: return .green
        case .restarting: return .blue
        case .paused: return .orange
        case .exited, .dead: return .red
        case .created, .unknown: return .secondary
        }
    }
}
