import SwiftUI
import NautilarrCore
import OverseerrKit

/// Overseerr / Jellyseerr: review the request feed (approve / decline / delete)
/// and discover + request new titles.
struct RequestsView: View {
    @EnvironmentObject private var instanceStore: InstanceStore
    @StateObject private var model = RequestsViewModel()

    private enum Tab: Hashable { case requests, discover }
    @State private var tab: Tab = .requests
    @State private var requesting: OverseerrSearchResult?

    var body: some View {
        Group {
            if !model.hasServices {
                ContentUnavailableLabel(
                    "No requests service",
                    systemImage: "tray.and.arrow.down",
                    description: "Add an Overseerr or Jellyseerr service in Settings to manage requests."
                )
            } else {
                VStack(spacing: 0) {
                    Picker("", selection: $tab) {
                        Text("Requests").tag(Tab.requests)
                        Text("Discover").tag(Tab.discover)
                    }
                    .pickerStyle(.segmented)
                    .padding([.horizontal, .top])
                    .padding(.bottom, 8)

                    if tab == .requests { requestsList } else { discoverList }
                }
            }
        }
        .overlay(alignment: .bottom) { Toast(message: model.statusMessage) { model.statusMessage = nil } }
        .task(id: model.filter) { await model.load(store: instanceStore) }
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
        .sheet(item: $requesting) { result in
            if let instance = instanceStore.instances(ofType: .overseerr).first {
                RequestOptionsView(instance: instance, result: result) { message in
                    model.statusMessage = message
                    Task { await model.load(store: instanceStore) }
                }
            }
        }
    }

    // MARK: Requests feed

    private var requestsList: some View {
        List {
            Picker("Filter", selection: $model.filter) {
                ForEach(model.filters, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            .tintedCards()

            ForEach(model.entries) { entry in
                RequestRow(
                    entry: entry,
                    onApprove: { Task { await model.approve(entry, store: instanceStore) } },
                    onDecline: { Task { await model.decline(entry, store: instanceStore) } }
                )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await model.deleteRequest(entry, store: instanceStore) }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .tintedCards()
            if model.entries.isEmpty && !model.isLoading {
                Text("No requests.").foregroundStyle(.secondary)
                    .tintedCards()
            }
        }
        .overlay { if model.isLoading && model.entries.isEmpty { ProgressView() } }
        .refreshable { await model.load(store: instanceStore) }
    }

    // MARK: Discover / create

    private var discoverList: some View {
        VStack(spacing: 0) {
            SearchField(prompt: "Search titles to request", text: $model.searchText) {
                Task { await model.search(store: instanceStore) }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            List {
                if model.isSearching {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .tintedCards()
                } else if model.searchResults.isEmpty {
                    Text("Search to find movies and shows to request.")
                        .foregroundStyle(.secondary).font(.subheadline)
                        .tintedCards()
                }
                ForEach(model.searchResults) { result in
                    DiscoverRow(result: result) { requesting = result }
                }
                .tintedCards()
            }
        }
    }
}

private struct RequestRow: View {
    let entry: RequestEntry
    let onApprove: () -> Void
    let onDecline: () -> Void

    private var tmdbPosterURL: URL? {
        guard let path = entry.posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(path)")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncCachedImage(url: tmdbPosterURL)
                .frame(width: 54, height: 81)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.subheadline).lineLimit(2)
                HStack(spacing: 6) {
                    StatusBadge(text: entry.request.mediaType.uppercased())
                    StatusBadge(text: entry.request.status.label, color: statusColor)
                }
                if let user = entry.request.requestedBy?.name {
                    Text("by \(user)").font(.caption2).foregroundStyle(.secondary)
                }
                if entry.request.status == .pending {
                    HStack(spacing: 10) {
                        Button("Approve", action: onApprove)
                            .buttonStyle(.borderedProminent).controlSize(.small).tint(.green)
                        Button("Decline", action: onDecline)
                            .buttonStyle(.bordered).controlSize(.small).tint(.red)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch entry.request.status {
        case .pending: return .orange
        case .approved: return .green
        case .declined: return .red
        case .unknown: return .secondary
        }
    }
}

private struct DiscoverRow: View {
    let result: OverseerrSearchResult
    let onRequest: () -> Void

    private var posterURL: URL? {
        guard let path = result.posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(path)")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncCachedImage(url: posterURL)
                .frame(width: 54, height: 81)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(result.displayTitle).font(.subheadline).lineLimit(2)
                HStack(spacing: 6) {
                    StatusBadge(text: (result.mediaType ?? "movie").uppercased())
                    if let year = result.year { StatusBadge(text: year) }
                }
                if let overview = result.overview, !overview.isEmpty {
                    Text(overview).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                requestControl
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var requestControl: some View {
        // status: 1 unknown, 2 pending, 3 processing, 4 partial, 5 available
        if let status = result.mediaInfo?.status, status >= 2 {
            StatusBadge(text: availabilityLabel(status), color: status >= 4 ? .green : .orange)
                .padding(.top, 2)
        } else {
            Button("Request", action: onRequest)
                .buttonStyle(.borderedProminent).controlSize(.small)
                .padding(.top, 2)
        }
    }

    private func availabilityLabel(_ status: Int) -> String {
        switch status {
        case 5: return "Available"
        case 4: return "Partially available"
        case 3: return "Processing"
        case 2: return "Pending"
        default: return "Requested"
        }
    }
}
