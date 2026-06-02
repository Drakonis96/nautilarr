import SwiftUI
import NautilarrCore
import RadarrKit

/// Search the metadata provider and add a movie to a Radarr instance.
struct AddMovieView: View {
    var onAdded: () -> Void = {}
    @EnvironmentObject private var instanceStore: InstanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedInstance: ServiceInstance?
    @State private var term = ""
    @State private var results: [RadarrMovie] = []
    @State private var isSearching = false
    @State private var pendingAdd: RadarrMovie?

    private var instances: [ServiceInstance] { instanceStore.instances(ofType: .radarr) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if instances.count > 1 {
                    Picker("Instance", selection: $selectedInstance) {
                        ForEach(instances) { Text($0.name).tag(Optional($0)) }
                    }.pickerStyle(.menu).padding(.horizontal)
                }
                List {
                    ForEach(results) { movie in
                        Button { pendingAdd = movie } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(movie.title)
                                HStack(spacing: 6) {
                                    if let year = movie.year { Text(String(year)) }
                                    if let studio = movie.studio { Text("· \(studio)") }
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                    .tintedCards()
                }
                .overlay { if isSearching { ProgressView() } }
            }
            .navigationTitle("Add Movie")
            .searchable(text: $term, prompt: "Search for a movie")
            .onSubmit(of: .search) { Task { await search() } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { if selectedInstance == nil { selectedInstance = instances.first } }
            .sheet(item: $pendingAdd) { movie in
                if let instance = selectedInstance ?? instances.first {
                    AddMovieOptionsView(instance: instance, lookup: movie) { onAdded(); dismiss() }
                }
            }
        }
    }

    private func search() async {
        guard let instance = selectedInstance ?? instances.first,
              let client = instanceStore.radarrClient(for: instance),
              !term.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        results = (try? await client.lookupMovies(term: term)) ?? []
    }
}

struct AddMovieOptionsView: View {
    let instance: ServiceInstance
    let lookup: RadarrMovie
    var onAdded: () -> Void

    @EnvironmentObject private var instanceStore: InstanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var profiles: [RadarrQualityProfile] = []
    @State private var rootFolders: [RadarrRootFolder] = []
    @State private var qualityProfileId: Int?
    @State private var rootFolderPath: String?
    @State private var minimumAvailability = "released"
    @State private var monitored = true
    @State private var searchOnAdd = true
    @State private var error: String?

    private let availabilities = ["announced", "inCinemas", "released"]

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(lookup.title).font(.headline) }
                    .tintedCards()
                Section("Options") {
                    Picker("Quality profile", selection: $qualityProfileId) {
                        ForEach(profiles) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Root folder", selection: $rootFolderPath) {
                        ForEach(rootFolders) { Text($0.path).tag(Optional($0.path)) }
                    }
                    Picker("Minimum availability", selection: $minimumAvailability) {
                        ForEach(availabilities, id: \.self) { Text($0).tag($0) }
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
                        .disabled(qualityProfileId == nil || rootFolderPath == nil)
                }
            }
            .task { await loadOptions() }
        }
    }

    private func loadOptions() async {
        guard let client = instanceStore.radarrClient(for: instance) else { return }
        async let p = client.qualityProfiles()
        async let r = client.rootFolders()
        profiles = (try? await p) ?? []
        rootFolders = (try? await r) ?? []
        qualityProfileId = profiles.first?.id
        rootFolderPath = rootFolders.first?.path
    }

    private func add() async {
        guard let client = instanceStore.radarrClient(for: instance),
              let qualityProfileId, let rootFolderPath else { return }
        let request = RadarrAddMovieRequest(
            lookup: lookup,
            qualityProfileId: qualityProfileId,
            rootFolderPath: rootFolderPath,
            monitored: monitored,
            minimumAvailability: minimumAvailability,
            addOptions: RadarrAddOptions(searchForMovie: searchOnAdd, monitor: "movieOnly")
        )
        do { _ = try await client.addMovie(request); onAdded(); dismiss() }
        catch { self.error = (error as? APIError)?.localizedDescription ?? error.localizedDescription }
    }
}
