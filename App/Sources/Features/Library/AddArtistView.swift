import SwiftUI
import NautilarrCore
import LidarrKit

/// Search the metadata provider and add an artist to a Lidarr instance.
struct AddArtistView: View {
    var onAdded: () -> Void = {}
    @EnvironmentObject private var instanceStore: InstanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedInstance: ServiceInstance?
    @State private var term = ""
    @State private var results: [LidarrArtist] = []
    @State private var isSearching = false
    @State private var pendingAdd: LidarrArtist?

    private var instances: [ServiceInstance] { instanceStore.instances(ofType: .lidarr) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if instances.count > 1 {
                    Picker("Instance", selection: $selectedInstance) {
                        ForEach(instances) { Text($0.name).tag(Optional($0)) }
                    }.pickerStyle(.menu).padding(.horizontal)
                }
                List {
                    ForEach(results) { artist in
                        Button { pendingAdd = artist } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artist.artistName)
                                if let genres = artist.genres, !genres.isEmpty {
                                    Text(genres.prefix(3).joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                    .tintedCards()
                }
                .overlay { if isSearching { ProgressView() } }
            }
            .navigationTitle("Add Artist")
            .searchable(text: $term, prompt: "Search for an artist")
            .onSubmit(of: .search) { Task { await search() } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { if selectedInstance == nil { selectedInstance = instances.first } }
            .sheet(item: $pendingAdd) { artist in
                if let instance = selectedInstance ?? instances.first {
                    AddArtistOptionsView(instance: instance, lookup: artist) { onAdded(); dismiss() }
                }
            }
        }
    }

    private func search() async {
        guard let instance = selectedInstance ?? instances.first,
              let client = instanceStore.lidarrClient(for: instance),
              !term.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        results = (try? await client.lookupArtists(term: term)) ?? []
    }
}

struct AddArtistOptionsView: View {
    let instance: ServiceInstance
    let lookup: LidarrArtist
    var onAdded: () -> Void

    @EnvironmentObject private var instanceStore: InstanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var qualityProfiles: [LidarrQualityProfile] = []
    @State private var metadataProfiles: [LidarrMetadataProfile] = []
    @State private var rootFolders: [LidarrRootFolder] = []
    @State private var qualityProfileId: Int?
    @State private var metadataProfileId: Int?
    @State private var rootFolderPath: String?
    @State private var monitored = true
    @State private var searchOnAdd = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(lookup.artistName).font(.headline) }
                    .tintedCards()
                Section("Options") {
                    Picker("Quality profile", selection: $qualityProfileId) {
                        ForEach(qualityProfiles) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Metadata profile", selection: $metadataProfileId) {
                        ForEach(metadataProfiles) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Root folder", selection: $rootFolderPath) {
                        ForEach(rootFolders) { Text($0.path).tag(Optional($0.path)) }
                    }
                    Toggle("Monitored", isOn: $monitored)
                    Toggle("Search on add", isOn: $searchOnAdd)
                }
                .tintedCards()
                if let error { Section { Label(error, systemImage: "xmark.octagon").foregroundStyle(.red) }.tintedCards() }
            }
            .navigationTitle("Add Options")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await add() } }
                        .disabled(qualityProfileId == nil || metadataProfileId == nil || rootFolderPath == nil)
                }
            }
            .task { await loadOptions() }
        }
    }

    private func loadOptions() async {
        guard let client = instanceStore.lidarrClient(for: instance) else { return }
        async let q = client.qualityProfiles()
        async let m = client.metadataProfiles()
        async let r = client.rootFolders()
        qualityProfiles = (try? await q) ?? []
        metadataProfiles = (try? await m) ?? []
        rootFolders = (try? await r) ?? []
        qualityProfileId = qualityProfiles.first?.id
        metadataProfileId = metadataProfiles.first?.id
        rootFolderPath = rootFolders.first?.path
    }

    private func add() async {
        guard let client = instanceStore.lidarrClient(for: instance),
              let qualityProfileId, let metadataProfileId, let rootFolderPath else { return }
        let request = LidarrAddArtistRequest(
            lookup: lookup,
            qualityProfileId: qualityProfileId,
            metadataProfileId: metadataProfileId,
            rootFolderPath: rootFolderPath,
            monitored: monitored,
            addOptions: LidarrAddOptions(monitor: "all", searchForMissingAlbums: searchOnAdd)
        )
        do { _ = try await client.addArtist(request); onAdded(); dismiss() }
        catch { self.error = (error as? APIError)?.localizedDescription ?? error.localizedDescription }
    }
}
