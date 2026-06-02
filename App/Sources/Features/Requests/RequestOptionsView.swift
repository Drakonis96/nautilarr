import SwiftUI
import NautilarrCore
import OverseerrKit

/// Advanced request dialog mirroring Overseerr/Jellyseerr's own: pick the
/// destination server, quality profile, root folder, language profile (TV) and
/// which seasons to request. Any option left untouched falls back to Overseerr's
/// defaults, so a plain "Request" still works even without advanced permissions.
struct RequestOptionsView: View {
    let instance: ServiceInstance
    let result: OverseerrSearchResult
    var onComplete: (String) -> Void

    @EnvironmentObject private var instanceStore: InstanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var servers: [OverseerrServer] = []
    @State private var selectedServerId: Int?
    @State private var details: OverseerrServerDetails?
    @State private var profileId: Int?
    @State private var rootFolder: String?
    @State private var languageProfileId: Int?
    @State private var seasons: [OverseerrSeason] = []
    @State private var allSeasons = true
    @State private var selectedSeasons: Set<Int> = []

    @State private var isLoading = false
    @State private var isLoadingDetails = false
    @State private var isSubmitting = false
    @State private var error: String?

    private var isTV: Bool { (result.mediaType ?? "movie") == "tv" }
    private var selectedServer: OverseerrServer? { servers.first { $0.id == selectedServerId } }

    var body: some View {
        NavigationStack {
            Form {
                header
                if let error { Section { ErrorBanner(message: error) } }

                if !servers.isEmpty {
                    serverSection
                    qualitySection
                    rootFolderSection
                    if isTV { languageSection }
                } else if isLoading {
                    Section { HStack { Spacer(); ProgressView(); Spacer() } }
                } else {
                    Section {
                        Label("Using Overseerr's default server and profiles.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if isTV { seasonsSection }
            }
            .navigationTitle("Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting { ProgressView() } else { Text("Request").bold() }
                    }
                    .disabled(isSubmitting)
                }
            }
            .task { await loadServers() }
        }
    }

    // MARK: Sections

    private var header: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                AsyncCachedImage(url: posterURL)
                    .frame(width: 54, height: 81)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.displayTitle).font(.headline).lineLimit(2)
                    HStack(spacing: 6) {
                        StatusBadge(text: (result.mediaType ?? "movie").uppercased())
                        if let year = result.year { StatusBadge(text: year) }
                        if selectedServer?.is4k == true { StatusBadge(text: "4K", color: .purple) }
                    }
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    private var serverSection: some View {
        Section("Destination Server") {
            Picker("Server", selection: $selectedServerId) {
                ForEach(servers) { server in
                    Text(serverLabel(server)).tag(Optional(server.id))
                }
            }
            .onChange(of: selectedServerId) { _, _ in Task { await loadDetails() } }
        }
    }

    private var qualitySection: some View {
        Section("Quality Profile") {
            if isLoadingDetails {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else {
                Picker("Quality", selection: $profileId) {
                    ForEach(details?.profiles ?? []) { profile in
                        Text(profile.name ?? "Profile \(profile.id)").tag(Optional(profile.id))
                    }
                }
            }
        }
    }

    private var rootFolderSection: some View {
        Section("Root Folder") {
            Picker("Folder", selection: $rootFolder) {
                ForEach(details?.rootFolders ?? [], id: \.path) { folder in
                    Text(folderLabel(folder)).tag(folder.path)
                }
            }
        }
    }

    private var languageSection: some View {
        Section("Language Profile") {
            Picker("Language", selection: $languageProfileId) {
                ForEach(details?.languageProfiles ?? []) { profile in
                    Text(profile.name ?? "Profile \(profile.id)").tag(Optional(profile.id))
                }
            }
        }
    }

    @ViewBuilder
    private var seasonsSection: some View {
        Section {
            Toggle("All seasons", isOn: $allSeasons)
            if !allSeasons {
                if seasons.isEmpty {
                    Text("No season information available.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(requestableSeasons, id: \.seasonNumber) { season in
                        Button {
                            toggleSeason(season.seasonNumber ?? 0)
                        } label: {
                            HStack {
                                Text(seasonLabel(season))
                                Spacer()
                                if selectedSeasons.contains(season.seasonNumber ?? 0) {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.teal)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            Text("Seasons")
        } footer: {
            if !allSeasons && selectedSeasons.isEmpty {
                Text("Select at least one season, or turn “All seasons” back on.")
            }
        }
    }

    // MARK: Helpers

    private var posterURL: URL? {
        guard let path = result.posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(path)")
    }

    /// Seasons worth requesting (skip "Specials" / season 0).
    private var requestableSeasons: [OverseerrSeason] {
        seasons.filter { ($0.seasonNumber ?? 0) > 0 }
    }

    private func serverLabel(_ server: OverseerrServer) -> String {
        var label = server.name ?? "Server \(server.id)"
        if server.is4k == true { label += " · 4K" }
        if server.isDefault == true { label += " (default)" }
        return label
    }

    private func folderLabel(_ folder: OverseerrRootFolder) -> String {
        guard let path = folder.path else { return "—" }
        if let free = folder.freeSpace, free > 0 {
            return "\(path) · \(Format.bytes(free)) free"
        }
        return path
    }

    private func seasonLabel(_ season: OverseerrSeason) -> String {
        let number = season.seasonNumber ?? 0
        var label = "Season \(number)"
        if let count = season.episodeCount, count > 0 { label += " · \(count) ep" }
        return label
    }

    private func toggleSeason(_ number: Int) {
        if selectedSeasons.contains(number) { selectedSeasons.remove(number) }
        else { selectedSeasons.insert(number) }
    }

    // MARK: Loading

    private func loadServers() async {
        guard let client = instanceStore.overseerrClient(for: instance) else { return }
        isLoading = true
        defer { isLoading = false }
        // Servers + advanced options need permission; degrade gracefully if not.
        servers = (try? await client.servers(forTV: isTV)) ?? []
        if let preferred = servers.first(where: { $0.isDefault == true && $0.is4k != true })
            ?? servers.first {
            selectedServerId = preferred.id
            await loadDetails()
        }
        if isTV {
            if let details = try? await client.mediaDetails(mediaType: "tv", tmdbId: result.id) {
                seasons = details.seasons ?? []
            }
        }
    }

    private func loadDetails() async {
        guard let client = instanceStore.overseerrClient(for: instance), let serverId = selectedServerId else { return }
        isLoadingDetails = true
        defer { isLoadingDetails = false }
        let fetched = try? await client.serverDetails(forTV: isTV, serverId: serverId)
        details = fetched
        let server = selectedServer
        profileId = server?.activeProfileId ?? fetched?.profiles?.first?.id
        rootFolder = server?.activeDirectory ?? fetched?.rootFolders?.first?.path
        languageProfileId = server?.activeLanguageProfileId ?? fetched?.languageProfiles?.first?.id
    }

    private func submit() async {
        guard let client = instanceStore.overseerrClient(for: instance) else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let seasonsArray: [Int]? = (isTV && !allSeasons) ? Array(selectedSeasons).sorted() : nil
        do {
            try await client.createRequest(
                mediaType: isTV ? "tv" : "movie",
                mediaId: result.id,
                seasons: seasonsArray,
                allSeasons: allSeasons || (seasonsArray?.isEmpty ?? true),
                is4k: selectedServer?.is4k ?? false,
                serverId: selectedServerId,
                profileId: profileId,
                rootFolder: rootFolder,
                languageProfileId: isTV ? languageProfileId : nil
            )
            onComplete("Requested “\(result.displayTitle)”.")
            dismiss()
        } catch {
            self.error = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}
