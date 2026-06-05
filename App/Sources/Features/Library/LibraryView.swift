import SwiftUI
import NautilarrCore

/// Unified poster grid across Sonarr (series), Radarr (movies) and Lidarr
/// (artists), with a kind filter, text search, per-item quick actions
/// (context menu) and a multi-select bulk mode.
struct LibraryView: View {
    @EnvironmentObject private var instanceStore: InstanceStore
    @StateObject private var model = LibraryViewModel()
    @State private var addingKind: MediaKind?
    @State private var editing: MediaEntry?
    @State private var pendingDelete: MediaEntry?
    @State private var statusMessage: String?
    @State private var selectionMode = false
    @State private var selection: Set<String> = []
    /// The entry whose detail is currently pushed. Driving navigation through a
    /// single binding (rather than a per-cell `NavigationLink(value:)`) avoids the
    /// LazyVGrid bug where the link pushes the detail and then immediately pops
    /// back to the grid, forcing the user to tap "back" to reach the detail.
    @State private var openedEntry: MediaEntry?
    @AppStorage("libraryListMode") private var listMode = false
    /// Stored poster column count. Clamped per platform: iPhone keeps the view
    /// clean (1–3), iPad/Mac allow denser grids (4–8). 0 = use the default.
    @AppStorage("libraryGridColumns") private var gridColumns = 0
    @Environment(\.horizontalSizeClass) private var hSize

    private let listColumns = [GridItem(.adaptive(minimum: 420), spacing: 14)]

    /// Column bounds by platform (compact = iPhone).
    private var minCols: Int { hSize == .compact ? 1 : 4 }
    private var maxCols: Int { hSize == .compact ? 3 : 8 }
    private var defaultCols: Int { hSize == .compact ? 2 : 5 }

    /// The effective column count, clamped into the platform's range.
    private var columns: Int {
        let c = gridColumns <= 0 ? defaultCols : gridColumns
        return min(maxCols, max(minCols, c))
    }

    private var posterColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: columns)
    }

    private var selectedEntries: [MediaEntry] { model.filtered.filter { selection.contains($0.id) } }

    var body: some View {
        Group {
            if !model.hasAny {
                ContentUnavailableLabel(
                    "No library",
                    systemImage: "square.grid.2x2",
                    description: "Add a Sonarr, Radarr or Lidarr service in Settings to browse your library."
                )
            } else {
                VStack(spacing: 0) {
                    libraryHeader
                    ScrollView {
                        if model.availableKinds.count > 1 { kindFilterBar }
                        if !listMode && !selectionMode { columnsSlider }
                        if let error = model.errorMessage {
                            ErrorBanner(message: error).padding([.horizontal, .top])
                        }
                        LazyVGrid(columns: listMode ? listColumns : posterColumns, spacing: listMode ? 14 : 16) {
                            ForEach(model.filtered) { entry in
                                itemView(for: entry)
                            }
                        }
                        .padding()
                    }
                    .safeAreaInset(edge: .bottom) { if selectionMode { bulkBar } }
                }
            }
        }
        .navigationDestination(item: $openedEntry) { entry in
            switch entry {
            case let .series(instance, series):
                SeriesDetailView(item: LibraryItem(instance: instance, series: series))
            case let .movie(instance, movie):
                MovieDetailView(instance: instance, movie: movie)
            case let .artist(instance, artist):
                ArtistDetailView(instance: instance, artist: artist)
            }
        }
        .overlay { if model.isLoading && model.entries.isEmpty { ProgressView() } }
        .overlay(alignment: .bottom) { Toast(message: statusMessage) { statusMessage = nil } }
        .refreshable { await model.load(store: instanceStore) }
        .task { await model.load(store: instanceStore) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RefreshSpinnerButton(isLoading: model.isLoading) {
                    Task { await model.load(store: instanceStore) }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nautilarrRefresh)) { _ in
            Task { await model.load(store: instanceStore) }
        }
        .sheet(item: $addingKind) { kind in
            switch kind {
            case .series: AddSeriesView { Task { await model.load(store: instanceStore) } }
            case .movie: AddMovieView { Task { await model.load(store: instanceStore) } }
            case .artist: AddArtistView { Task { await model.load(store: instanceStore) } }
            }
        }
        .sheet(item: $editing) { entry in
            LibraryItemEditView(entry: entry) { Task { await model.load(store: instanceStore) } }
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.title ?? "")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let entry = pendingDelete {
                Button("Remove from library", role: .destructive) {
                    runDelete(entry, deleteFiles: false); pendingDelete = nil
                }
                Button("Remove and delete files", role: .destructive) {
                    runDelete(entry, deleteFiles: true); pendingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    // MARK: - Grid item

    @ViewBuilder
    private func itemView(for entry: MediaEntry) -> some View {
        let label = Group {
            if listMode { MediaListRow(entry: entry) } else { PosterTile(entry: entry) }
        }
        if selectionMode {
            Button { toggleSelection(entry) } label: {
                label
                    .overlay(alignment: .topTrailing) { selectionBadge(entry) }
                    .opacity(selection.contains(entry.id) ? 1 : 0.7)
            }
            .buttonStyle(.plain)
        } else {
            Button { openedEntry = entry } label: { label }
                .buttonStyle(.plain)
                .contextMenu { contextMenu(for: entry) }
        }
    }

    @ViewBuilder
    private func contextMenu(for entry: MediaEntry) -> some View {
        Button {
            perform("Searching “\(entry.title)”…") { await LibraryActions.automaticSearch(entry, store: instanceStore) }
        } label: { Label("Automatic Search", systemImage: "magnifyingglass") }
        Button {
            perform("Refreshing “\(entry.title)”…") { await LibraryActions.refresh(entry, store: instanceStore) }
        } label: { Label("Refresh & Scan", systemImage: "arrow.clockwise") }
        Button {
            perform(entry.isMonitored ? "Unmonitored." : "Now monitoring.", reload: true) {
                await LibraryActions.setMonitored(entry, monitored: !entry.isMonitored, store: instanceStore)
            }
        } label: {
            Label(entry.isMonitored ? "Unmonitor" : "Monitor",
                  systemImage: entry.isMonitored ? "bookmark.slash" : "bookmark")
        }
        Button { editing = entry } label: { Label("Edit…", systemImage: "slider.horizontal.3") }
        Divider()
        Button(role: .destructive) { pendingDelete = entry } label: { Label("Delete", systemImage: "trash") }
    }

    private func selectionBadge(_ entry: MediaEntry) -> some View {
        let selected = selection.contains(entry.id)
        return Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, selected ? Theme.teal : Color.black.opacity(0.35))
            .padding(6)
    }

    // MARK: - Bulk bar

    private var bulkBar: some View {
        HStack(spacing: 6) {
            bulkButton("bookmark", "Monitor") { await LibraryActions.setMonitored($0, monitored: true, store: instanceStore) }
            bulkButton("bookmark.slash", "Unmonitor") { await LibraryActions.setMonitored($0, monitored: false, store: instanceStore) }
            bulkButton("magnifyingglass", "Search") { await LibraryActions.automaticSearch($0, store: instanceStore) }
            bulkButton("arrow.clockwise", "Refresh") { await LibraryActions.refresh($0, store: instanceStore) }
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .glassSurface(in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private func bulkButton(_ icon: String, _ title: String, _ action: @escaping ([MediaEntry]) async -> String?) -> some View {
        Button {
            let entries = selectedEntries
            Task {
                let err = await action(entries)
                statusMessage = err ?? "\(title): \(entries.count) item\(entries.count == 1 ? "" : "s")"
                await model.load(store: instanceStore)
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(selection.isEmpty)
    }

    // MARK: - Actions

    private func toggleSelection(_ entry: MediaEntry) {
        if selection.contains(entry.id) { selection.remove(entry.id) } else { selection.insert(entry.id) }
    }

    private func perform(_ success: String, reload: Bool = false, _ action: @escaping () async -> String?) {
        Task {
            let err = await action()
            statusMessage = err ?? success
            if reload { await model.load(store: instanceStore) }
        }
    }

    private func runDelete(_ entry: MediaEntry, deleteFiles: Bool) {
        Task {
            let err = await LibraryActions.delete(entry, deleteFiles: deleteFiles, store: instanceStore)
            statusMessage = err ?? "Removed “\(entry.title)”."
            await model.load(store: instanceStore)
        }
    }

    // MARK: - Bars & toolbars

    private var kindFilterBar: some View {
        Picker("Kind", selection: $model.kindFilter) {
            Text("All").tag(MediaKind?.none)
            ForEach(model.availableKinds) { Text(LocalizedStringKey($0.plural)).tag(MediaKind?.some($0)) }
        }
        .pickerStyle(.segmented)
        .padding([.horizontal, .top])
    }

    /// Immediate slider for poster size. Inverted: dragging RIGHT reduces the
    /// column count (bigger posters). Range adapts to the platform.
    private var columnsSlider: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.fill").foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { Double(minCols + maxCols - columns) },
                    set: { gridColumns = (minCols + maxCols) - Int($0.rounded()) }
                ),
                in: Double(minCols)...Double(maxCols), step: 1
            )
            Image(systemName: "square.fill").foregroundStyle(.secondary)
            Text("\(columns)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(width: 22, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// In-content header (replaces the cramped Catalyst nav-bar toolbar): the
    /// Select/filter/add controls with breathing room, plus the search field.
    private var libraryHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button(selectionMode ? "Done" : "Select") {
                    withAnimation {
                        selectionMode.toggle()
                        if !selectionMode { selection.removeAll() }
                    }
                }
                if selectionMode {
                    Button(selection.count == model.filtered.count ? "None" : "All") {
                        if selection.count == model.filtered.count { selection.removeAll() }
                        else { selection = Set(model.filtered.map(\.id)) }
                    }
                }
                Spacer()
                layoutToggle
                filterMenu
                addMenu
            }
            SearchField(prompt: "Filter library", text: $model.searchText)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var filterMenu: some View {
        Menu {
                Picker("Sort", selection: $model.sortOrder) {
                    ForEach(LibraryViewModel.SortOrder.allCases) { Text($0.label).tag($0) }
                }
                Section("Filter") {
                    Picker("Monitored", selection: $model.monitoredFilter) {
                        ForEach(LibraryViewModel.MonitoredFilter.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Status", selection: $model.statusFilter) {
                        ForEach(LibraryViewModel.StatusFilter.allCases) { Text($0.label).tag($0) }
                    }
                    if model.availableInstances.count > 1 {
                        Picker("Service", selection: $model.instanceFilter) {
                            Text("All Services").tag(UUID?.none)
                            ForEach(model.availableInstances, id: \.id) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    }
                    if !model.availableQualityProfiles.isEmpty {
                        Picker("Quality", selection: $model.qualityProfileFilter) {
                            Text("All Qualities").tag(String?.none)
                            ForEach(model.availableQualityProfiles, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    }
                    if !model.availableGenres.isEmpty {
                        Picker("Genre", selection: $model.genreFilter) {
                            Text("All Genres").tag(String?.none)
                            ForEach(model.availableGenres, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    }
                }
                Section("View") {
                    Button {
                        withAnimation { listMode.toggle() }
                    } label: {
                        Label(listMode ? "Grid View" : "List View",
                              systemImage: listMode ? "square.grid.2x2" : "list.bullet")
                    }
                    if model.isFiltering {
                        Button("Clear Filters", systemImage: "xmark.circle") { model.clearFilters() }
                    }
                }
        } label: {
            Label("Filter & Sort",
                  systemImage: model.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .labelStyle(.iconOnly)
        }
        .disabled(selectionMode)
    }

    /// Prominent grid ⇄ list switch (also available in the Filter menu's View
    /// section). Shows the icon of the layout you'll switch to.
    private var layoutToggle: some View {
        Button {
            withAnimation { listMode.toggle() }
        } label: {
            Image(systemName: listMode ? "square.grid.2x2" : "list.bullet")
        }
        .accessibilityLabel(listMode ? "Grid view" : "List view")
        .disabled(selectionMode)
    }

    private var addMenu: some View {
        Menu {
            ForEach(model.availableKinds) { kind in
                Button {
                    addingKind = kind
                } label: {
                    Label("Add \(kind.singular)", systemImage: kind.symbol)
                }
            }
        } label: {
            Label("Add", systemImage: "plus").labelStyle(.iconOnly)
        }
        .disabled(!model.hasAny || selectionMode)
    }
}
