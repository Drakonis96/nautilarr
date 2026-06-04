import SwiftUI
import NautilarrCore

/// The Activity Inbox — a triage screen that surfaces stalled/errored downloads,
/// failed or stuck *arr imports, and service-health warnings, each with the
/// matching one-tap fix. Aggregation lives in `InboxViewModel`; this view is the
/// list + actions.
struct InboxView: View {
    @EnvironmentObject private var instanceStore: InstanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.openURL) private var openURL
    @StateObject private var model = InboxViewModel()
    @State private var filter: InboxFilter = .all
    @State private var pendingRemoval: UnifiedDownload?
    @State private var bulkConfirm: BulkAction?

    var body: some View {
        Group {
            if !model.hasServices {
                ContentUnavailableLabel(
                    "Nothing to watch",
                    systemImage: "bell.slash",
                    description: "Add a media or download service in Settings and the Activity inbox will flag anything that needs attention."
                )
            } else {
                VStack(spacing: 0) {
                    filterBar
                    list
                }
            }
        }
        .overlay { if model.isLoading && model.entries.isEmpty { ProgressView() } }
        .task(id: settings.autoRefreshSeconds) { await autoRefreshLoop() }
        .toolbar {
            if !model.entries.isEmpty { bulkMenu }
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
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        }
        .confirmationDialog(bulkConfirm?.prompt ?? "", isPresented: .constant(bulkConfirm != nil), titleVisibility: .visible) {
            if let bulkConfirm {
                Button(bulkConfirm.confirmLabel, role: bulkConfirm.isDestructive ? .destructive : nil) {
                    Task { await runBulk(bulkConfirm); await reload() }
                    self.bulkConfirm = nil
                }
            }
            Button("Cancel", role: .cancel) { bulkConfirm = nil }
        }
    }

    // MARK: Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InboxFilter.allCases) { f in
                    FilterChip(title: f.label, systemImage: f.symbol,
                               count: model.entries(for: f).count,
                               isSelected: filter == f) { filter = f }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .frame(height: 56)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        let entries = model.entries(for: filter)
        if entries.isEmpty && !model.isLoading {
            ContentUnavailableLabel(
                "All clear",
                systemImage: "checkmark.seal",
                description: "Nothing needs your attention right now."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(entries) { entry in
                    InboxRow(entry: entry,
                             onRemove: { pendingRemoval = entry.download },
                             onOpenWiki: { if let s = entry.issue.wikiURL, let url = URL(string: s) { openURL(url) } },
                             reload: reload)
                }
                .tintedCards()
            }
            .refreshable { await reload() }
        }
    }

    // MARK: Bulk actions

    private var bulkMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if model.entries.contains(where: { $0.issue.kind == .failedImport && $0.download?.retryImport != nil }) {
                    Button { bulkConfirm = .retryImports } label: { Label("Retry all imports", systemImage: "arrow.clockwise") }
                }
                if model.entries.contains(where: { $0.issue.kind == .failedImport && $0.download?.blocklist != nil }) {
                    Button(role: .destructive) { bulkConfirm = .blocklistFailed } label: {
                        Label("Blocklist & re-search failed", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            } label: { Label("Actions", systemImage: "ellipsis.circle") }
        }
    }

    enum BulkAction: Identifiable {
        case retryImports, blocklistFailed
        var id: String { String(describing: self) }
        var prompt: String {
            switch self {
            case .retryImports: return "Retry all stuck imports?"
            case .blocklistFailed: return "Blocklist and re-search every failed import?"
            }
        }
        var confirmLabel: String {
            switch self {
            case .retryImports: return "Retry imports"
            case .blocklistFailed: return "Blocklist & re-search"
            }
        }
        var isDestructive: Bool { self == .blocklistFailed }
    }

    private func runBulk(_ action: BulkAction) async {
        let failed = model.entries.filter { $0.issue.kind == .failedImport }
        switch action {
        case .retryImports:
            // retryImport is instance-global; calling once per instance suffices.
            var doneInstances = Set<String>()
            for entry in failed {
                guard let retry = entry.download?.retryImport else { continue }
                if doneInstances.insert(entry.issue.instanceName).inserted { await retry() }
            }
        case .blocklistFailed:
            for entry in failed { await entry.download?.blocklist?() }
        }
    }

    // MARK: Loading

    private func reload() async {
        await model.load(store: instanceStore, settings: settings)
        environment.inboxIssueCount = model.entries.count
    }

    private func autoRefreshLoop() async {
        let interval = max(5, settings.autoRefreshSeconds)
        while !Task.isCancelled {
            await reload()
            try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
        }
    }
}

// MARK: - Row

private struct InboxRow: View {
    let entry: InboxViewModel.Entry
    let onRemove: () -> Void
    let onOpenWiki: () -> Void
    let reload: () async -> Void

    private var issue: InboxIssue { entry.issue }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: issue.severity.symbol)
                    .foregroundStyle(issue.severity.color)
                    .font(.body)
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.title).font(.subheadline).lineLimit(2)
                    Text(issue.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 4)
                ServiceIcon(type: issue.serviceType, size: 18)
            }
            HStack(spacing: 8) {
                StatusBadge(text: issue.kind.label, color: issue.severity.color)
                Spacer()
                actions
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 4) {
            if issue.kind == .health {
                if issue.wikiURL != nil {
                    iconButton("book", help: "Open wiki", action: onOpenWiki)
                }
            } else if let download = entry.download {
                if let retry = download.retryImport, issue.kind == .failedImport {
                    asyncIconButton("arrow.clockwise", help: "Retry import") { await retry() }
                }
                if let blocklist = download.blocklist {
                    asyncIconButton("arrow.triangle.2.circlepath", help: "Blocklist & search") { await blocklist() }
                }
                if download.recheck != nil {
                    asyncIconButton("checkmark.circle", help: "Recheck") { await download.recheck?() }
                }
                if download.togglePause != nil {
                    asyncIconButton(download.isPaused ? "play.fill" : "pause.fill",
                                    help: download.isPaused ? "Resume" : "Pause") { await download.togglePause?() }
                }
                if download.remove != nil {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash").font(.callout)
                            .frame(width: 28, height: 28).foregroundStyle(.red).glassCircle()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.callout)
                .frame(width: 28, height: 28).foregroundStyle(Theme.teal).glassCircle()
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func asyncIconButton(_ symbol: String, help: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action(); await reload() }
        } label: {
            Image(systemName: symbol).font(.callout)
                .frame(width: 28, height: 28).foregroundStyle(Theme.teal).glassCircle()
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Severity & kind presentation

extension InboxSeverity {
    var color: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        case .notice: return .blue
        }
    }
    var symbol: String {
        switch self {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .notice: return "info.circle.fill"
        }
    }
}

extension InboxKind {
    var label: String {
        switch self {
        case .stuckDownload: return "Download"
        case .failedImport: return "Import"
        case .health: return "Health"
        }
    }
}
