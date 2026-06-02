import SwiftUI
import NautilarrCore
import SonarrKit

/// Search the metadata provider and add a new series, choosing the target
/// Sonarr instance, quality profile and root folder.
struct AddSeriesView: View {
    var onAdded: () -> Void = {}
    @EnvironmentObject private var instanceStore: InstanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedInstance: ServiceInstance?
    @State private var term = ""
    @State private var results: [SonarrSeries] = []
    @State private var isSearching = false
    @State private var pendingAdd: SonarrSeries?

    private var sonarrInstances: [ServiceInstance] { instanceStore.instances(ofType: .sonarr) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if sonarrInstances.count > 1 {
                    Picker("Instance", selection: $selectedInstance) {
                        ForEach(sonarrInstances) { Text($0.name).tag(Optional($0)) }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal)
                }
                List {
                    ForEach(results) { series in
                        Button { pendingAdd = series } label: {
                            LookupRow(series: series)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .overlay { if isSearching { ProgressView() } }
            }
            .navigationTitle("Add Series")
            .searchable(text: $term, prompt: "Search for a series")
            .onSubmitSearch { Task { await search() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .sheet(item: $pendingAdd) { series in
                if let instance = activeInstance {
                    AddSeriesOptionsView(instance: instance, lookup: series) {
                        onAdded()
                        dismiss()
                    }
                }
            }
            .onAppear { if selectedInstance == nil { selectedInstance = sonarrInstances.first } }
        }
    }

    private var activeInstance: ServiceInstance? { selectedInstance ?? sonarrInstances.first }

    private func search() async {
        guard let instance = activeInstance,
              let client = instanceStore.sonarrClient(for: instance),
              !term.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        results = (try? await client.lookupSeries(term: term)) ?? []
    }
}

struct LookupRow: View {
    let series: SonarrSeries
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(series.title).font(.body)
            HStack(spacing: 6) {
                if let year = series.year { Text(String(year)) }
                if let network = series.network { Text("· \(network)") }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Quality profile + root folder selection before adding.
struct AddSeriesOptionsView: View {
    let instance: ServiceInstance
    let lookup: SonarrSeries
    var onAdded: () -> Void

    @EnvironmentObject private var instanceStore: InstanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var profiles: [SonarrQualityProfile] = []
    @State private var languageProfiles: [SonarrLanguageProfile] = []
    @State private var rootFolders: [SonarrRootFolder] = []
    @State private var qualityProfileId: Int?
    @State private var languageProfileId: Int?
    @State private var rootFolderPath: String?
    @State private var monitored = true
    @State private var seasonFolder = true
    @State private var searchOnAdd = true
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(lookup.title).font(.headline) }
                Section("Options") {
                    Picker("Quality profile", selection: $qualityProfileId) {
                        ForEach(profiles) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if !languageProfiles.isEmpty {
                        Picker("Language profile", selection: $languageProfileId) {
                            ForEach(languageProfiles) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    Picker("Root folder", selection: $rootFolderPath) {
                        ForEach(rootFolders) { Text($0.path).tag(Optional($0.path)) }
                    }
                    Toggle("Monitored", isOn: $monitored)
                    Toggle("Season folders", isOn: $seasonFolder)
                    Toggle("Search on add", isOn: $searchOnAdd)
                }
                if let error {
                    Section { Label(error, systemImage: "xmark.octagon").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add Options")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await add() } }
                        .disabled(qualityProfileId == nil || rootFolderPath == nil || isWorking)
                }
            }
            .task { await loadOptions() }
        }
    }

    private func loadOptions() async {
        guard let client = instanceStore.sonarrClient(for: instance) else { return }
        async let p = client.qualityProfiles()
        async let l = client.languageProfiles()
        async let r = client.rootFolders()
        profiles = (try? await p) ?? []
        languageProfiles = (try? await l) ?? []
        rootFolders = (try? await r) ?? []
        qualityProfileId = profiles.first?.id
        languageProfileId = languageProfiles.first?.id
        rootFolderPath = rootFolders.first?.path
    }

    private func add() async {
        guard let client = instanceStore.sonarrClient(for: instance),
              let qualityProfileId, let rootFolderPath else { return }
        isWorking = true
        defer { isWorking = false }
        let request = SonarrAddSeriesRequest(
            lookup: lookup,
            qualityProfileId: qualityProfileId,
            languageProfileId: languageProfileId,
            rootFolderPath: rootFolderPath,
            monitored: monitored,
            seasonFolder: seasonFolder,
            addOptions: SonarrAddOptions(searchForMissingEpisodes: searchOnAdd, monitor: monitored ? "all" : "none")
        )
        do {
            _ = try await client.addSeries(request)
            onAdded()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}

// MARK: - onSubmit search helper (keeps call-sites tidy across platforms)

private extension View {
    func onSubmitSearch(_ action: @escaping () -> Void) -> some View {
        onSubmit(of: .search, action)
    }
}
