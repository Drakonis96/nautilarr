import SwiftUI
import NautilarrCore

/// Dashboard: per-service stat cards, active streams, an upcoming-releases
/// poster carousel, health and active downloads. Adaptive across iPhone/iPad/Mac.
struct HomeView: View {
    @EnvironmentObject private var instanceStore: InstanceStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @StateObject private var model = HomeViewModel()
    @StateObject private var prank = ServicePrankController()

    private let cardColumns = [GridItem(.adaptive(minimum: 300), spacing: 16)]
    private let compactColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    /// On iPhone, show the services as a dense 3-up grid by default; toggleable
    /// to the roomy full-width row cards.
    @AppStorage("homeServicesGrid") private var servicesGrid = true

    private var isMac: Bool { ProcessInfo.processInfo.isMacCatalystApp }
    private let refreshThreshold: CGFloat = 110
    private let restingHeight: CGFloat = 122
    @State private var pullOffset: CGFloat = 0
    @State private var isRefreshing = false
    @State private var armed = false

    private func refresh() async {
        await model.load(store: instanceStore)
        environment.activeDownloadCount = model.downloads.count
    }

    /// Pull distance, normalised (0…~1.3) for the visual.
    private var pullProgress: CGFloat { min(1.3, max(0, pullOffset) / refreshThreshold) }

    /// Header height: a tall resting submarine that grows generously as you pull,
    /// holding a touch taller while refreshing (room for the bounce).
    private var indicatorHeight: CGFloat {
        if isRefreshing { return refreshThreshold + 50 }
        return max(restingHeight, min(pullOffset * 1.1, refreshThreshold + 50))
    }

    private func handlePull(_ value: CGFloat) {
        guard !isMac, !isRefreshing else { return }
        pullOffset = max(0, value)
        if pullOffset >= refreshThreshold && !armed {
            armed = true
            Task { @MainActor in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { isRefreshing = true }
                await refresh()
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { isRefreshing = false; pullOffset = 0 }
            }
        } else if pullOffset < 8 {
            armed = false
        }
    }

    private var baseScroll: some View {
        ScrollView {
            VStack(spacing: 0) {
                // The submarine sits at the top of Home (touch devices). It grows
                // and sails as you pull down to refresh, then bounces on the swell.
                if !isMac {
                    OceanRefreshIndicator(progress: pullProgress, refreshing: isRefreshing, accent: settings.accent.color)
                        .frame(height: indicatorHeight)
                        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: isRefreshing)
                }
                dashboard
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: HomePullKey.self,
                                           value: max(0, geo.frame(in: .named("homeScroll")).minY))
                }
            )
        }
        .coordinateSpace(name: "homeScroll")
    }

    /// Uses the reliable iOS 18+ scroll-offset reader (correct even with a large
    /// navigation title — the old preference reader barely moved), falling back
    /// to the preference reader on older systems.
    @ViewBuilder
    private var pullableScroll: some View {
        if #available(iOS 18.0, macCatalyst 18.0, *) {
            baseScroll.onScrollGeometryChange(for: CGFloat.self) { geo in
                max(0, -(geo.contentOffset.y + geo.contentInsets.top))
            } action: { _, newValue in
                handlePull(newValue)
            }
        } else {
            baseScroll.onPreferenceChange(HomePullKey.self) { handlePull($0) }
        }
    }

    var body: some View {
        pullableScroll
        .navigationDestination(for: MediaEntry.self) { entry in
            switch entry {
            case let .series(instance, series):
                SeriesDetailView(item: LibraryItem(instance: instance, series: series))
            case let .movie(instance, movie):
                MovieDetailView(instance: instance, movie: movie)
            case let .artist(instance, artist):
                ArtistDetailView(instance: instance, artist: artist)
            }
        }
        // Easter egg: tapping a service icon sends it bouncing toward the top.
        .overlay { ServicePrankOverlay(controller: prank) }
        .overlay { if model.isLoading && model.serviceStats.isEmpty { ProgressView() } }
        .task(id: settings.autoRefreshNowPlaying) {
            await model.load(store: instanceStore)
            environment.activeDownloadCount = model.downloads.count
            while settings.autoRefreshNowPlaying && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { break }
                await model.load(store: instanceStore)
                environment.activeDownloadCount = model.downloads.count
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nautilarrRefresh)) { _ in
            Task { await model.load(store: instanceStore) }
        }
        .toolbar {
            if instanceStore.networks.count > 1 {
                ToolbarItem(placement: .topBarLeading) { NetworkSwitcher() }
            }
            // On touch devices the submarine pull-to-refresh replaces this; keep
            // the explicit button on Mac, where there's no rubber-band pull.
            if isMac {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await refresh() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                }
            }
        }
    }

    @ViewBuilder
    private var dashboard: some View {
        if !model.hasServices {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 22) {
                if !model.serviceStats.isEmpty { servicesSection }
                if !model.librarySummary.isEmpty { libraryStatsCard }
                if !model.streams.isEmpty { streamsCard }
                if !model.upcoming.isEmpty { upcomingSection }
                bottomCards
            }
            .padding()
        }
    }

    private var emptyState: some View {
        ContentUnavailableLabel(
            "No services yet",
            systemImage: "sailboat",
            description: "Add a service in Settings to see your dashboard."
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: Services stat cards

    /// Compact 3-up grid only on iPhone with more than one service.
    private var useCompactServices: Bool {
        hSizeClass == .compact && servicesGrid && model.serviceStats.count > 1
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("Services", systemImage: "square.stack.3d.up")
                Spacer()
                if hSizeClass == .compact && model.serviceStats.count > 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { servicesGrid.toggle() }
                    } label: {
                        Image(systemName: servicesGrid ? "rectangle.grid.1x2" : "square.grid.3x3")
                            .font(.title3)
                    }
                    .accessibilityLabel(servicesGrid ? "Row view" : "Grid view")
                }
            }
            LazyVGrid(columns: useCompactServices ? compactColumns : cardColumns,
                      alignment: .leading, spacing: useCompactServices ? 10 : 16) {
                ForEach(model.serviceStats) { stat in
                    serviceCard(stat)
                }
            }
        }
    }

    @ViewBuilder
    private func serviceCard(_ stat: HomeViewModel.ServiceStat) -> some View {
        let card = Group {
            if useCompactServices {
                CompactServiceCard(stat: stat) { prank.bump(stat.type) }
            } else {
                ServiceStatCard(stat: stat) { prank.bump(stat.type) }
            }
        }
        if let instance = downloadClientInstance(for: stat) {
            NavigationLink { DownloadClientView(instance: instance) } label: { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }

    /// Resolves the download-client instance behind a card so it can open the
    /// per-client management screen (nil for non-clients or failed cards).
    private func downloadClientInstance(for stat: HomeViewModel.ServiceStat) -> ServiceInstance? {
        let clientTypes: Set<ServiceType> = [.qbittorrent, .transmission, .deluge, .sabnzbd, .nzbget]
        guard clientTypes.contains(stat.type), stat.errorMessage == nil, let id = stat.instanceID else { return nil }
        return instanceStore.instancesInActiveNetwork.first { $0.id == id }
    }

    // MARK: Library statistics

    private var libraryStatsCard: some View {
        let summary = model.librarySummary
        let stats: [(String, String)] = ([
            summary.series > 0 ? ("Series", "\(summary.series)") : nil,
            summary.movies > 0 ? ("Movies", "\(summary.movies)") : nil,
            summary.artists > 0 ? ("Artists", "\(summary.artists)") : nil,
            ("Files", "\(summary.files)"),
            ("Library Size", Format.bytes(summary.size))
        ] as [(String, String)?]).compactMap { $0 }

        return CardContainer(title: "Library Statistics", systemImage: "chart.bar.xaxis") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), alignment: .leading)], alignment: .leading, spacing: 12) {
                ForEach(stats, id: \.0) { stat in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.1).font(.title3.weight(.bold))
                        Text(stat.0).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Active streams

    private var streamsCard: some View {
        CardContainer(title: "Currently Playing", systemImage: "play.tv") {
            ForEach(model.streams) { stream in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(stream.title).font(.subheadline).lineLimit(1)
                        Spacer()
                        if stream.transcoding { StatusBadge(text: "Transcode", color: .orange) }
                    }
                    ProgressView(value: stream.progress).tint(Theme.teal)
                    Text(stream.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    // MARK: Upcoming carousel

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Upcoming Releases", systemImage: "calendar")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(model.upcoming) { line in
                        if let media = line.mediaEntry {
                            NavigationLink(value: media) {
                                UpcomingPoster(line: line).environmentObject(instanceStore)
                            }
                            .buttonStyle(.plain)
                        } else {
                            UpcomingPoster(line: line).environmentObject(instanceStore)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: Health & downloads

    /// Health and Active Downloads, laid out side-by-side (top-aligned) on
    /// iPad/Mac and stacked on iPhone. A plain `LazyVGrid` here vertically
    /// centres a short card next to a tall one, so it's done explicitly.
    @ViewBuilder
    private var bottomCards: some View {
        if hSizeClass == .compact {
            healthCard
            downloadsCard
        } else {
            HStack(alignment: .top, spacing: 16) {
                healthCard.frame(maxWidth: .infinity, alignment: .topLeading)
                downloadsCard.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var healthCard: some View {
        CardContainer(title: "Health", systemImage: "heart.text.square") {
            if model.health.isEmpty {
                Label("All systems healthy", systemImage: "checkmark.circle")
                    .foregroundStyle(.green).font(.subheadline)
            } else {
                ForEach(model.health.prefix(6)) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: line.level.symbol).foregroundStyle(line.level.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.message).font(.subheadline)
                            Text(line.instanceName).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if model.health.count > 6 {
                    Text("+\(model.health.count - 6) more")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var downloadsCard: some View {
        CardContainer(title: "Active Downloads", systemImage: "arrow.down.circle") {
            if model.downloads.isEmpty {
                Text("Queue is empty").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(model.downloads.prefix(6)) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.title).font(.subheadline).lineLimit(1)
                        ProgressView(value: line.progress).tint(Theme.teal)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title3.weight(.semibold))
    }
}

// MARK: - Compact service card (iPhone 3-up grid)

private struct CompactServiceCard: View {
    let stat: HomeViewModel.ServiceStat
    var onIconTap: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ServiceIcon(type: stat.type, size: 30)
                    .contentShape(Circle())
                    .highPriorityGesture(TapGesture().onEnded { onIconTap() })
                Spacer(minLength: 0)
                Circle().fill(stat.errorMessage == nil ? .green : .red).frame(width: 7, height: 7)
            }
            Text(stat.headline)
                .font(.callout.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            Text(stat.instanceName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .glassSurface(in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
    }
}

// MARK: - Service stat card

private struct ServiceStatCard: View {
    let stat: HomeViewModel.ServiceStat
    /// Tapping just the icon triggers the dashboard easter egg.
    var onIconTap: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ServiceIcon(type: stat.type, size: 26)
                    .contentShape(Circle())
                    // High-priority so an icon tap pranks instead of following
                    // the card's navigation link (download-client cards).
                    .highPriorityGesture(TapGesture().onEnded { onIconTap() })
                Text(stat.instanceName).font(.headline)
                Spacer()
                Circle().fill(stat.errorMessage == nil ? .green : .red).frame(width: 8, height: 8)
            }
            Text(stat.headline).font(.title2.weight(.bold))
            if let error = stat.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red).lineLimit(2)
            } else {
                HStack(spacing: 18) {
                    ForEach(stat.metrics) { metric in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(metric.value).font(.subheadline.weight(.semibold))
                            Text(metric.label).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if let size = stat.librarySize {
                    diskBar(used: size, free: stat.freeSpace)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Metrics.cardPadding)
        // Uniform card height so service cards (e.g. Sonarr/Radarr, which show an
        // extra disk-usage bar) don't tower over the lighter cards next to them.
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .glassSurface(in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
    }

    @ViewBuilder
    private func diskBar(used: Int64, free: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let free, free > 0 {
                let total = used + free
                ProgressView(value: Double(used), total: Double(max(total, 1))).tint(Theme.teal)
                Text("\(Format.bytes(used)) used · \(Format.bytes(free)) free").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Library: \(Format.bytes(used))").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Upcoming poster card

private struct UpcomingPoster: View {
    let line: HomeViewModel.UpcomingLine
    @EnvironmentObject private var instanceStore: InstanceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            poster
                .frame(width: 116, height: 174)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(line.title).font(.caption).lineLimit(1).frame(width: 116, alignment: .leading)
            if let date = line.date {
                Text(date, format: .dateTime.month().day().hour().minute())
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var poster: some View {
        if let url = PosterURL.resolve(line.posterURLString, instance: line.instance) {
            AsyncCachedImage(
                url: url,
                headers: instanceStore.imageHeaders(for: line.instance),
                allowSelfSignedHosts: line.instance.allowSelfSignedCertificates
                    ? Set(line.instance.candidateBaseURLs().compactMap { $0.host }) : []
            )
        } else {
            ZStack { Theme.backgroundGradient; Image(systemName: "film").foregroundStyle(.white.opacity(0.6)) }
        }
    }
}
