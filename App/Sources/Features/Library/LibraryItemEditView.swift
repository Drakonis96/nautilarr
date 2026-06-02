import SwiftUI
import NautilarrCore
import SonarrKit
import RadarrKit
import LidarrKit

/// Loads the editable settings for a library item (monitored, quality profile,
/// root folder, and — for artists — metadata profile) and saves changes through
/// the matching *arr `editor` endpoint.
@MainActor
final class LibraryEditViewModel: ObservableObject {
    struct Option: Identifiable, Hashable { let id: Int; let name: String }

    let entry: MediaEntry

    @Published var monitored: Bool
    @Published var qualityProfileId: Int?
    @Published var metadataProfileId: Int?
    @Published var rootFolderPath: String?
    @Published var moveFiles = false

    @Published var qualityProfiles: [Option] = []
    @Published var metadataProfiles: [Option] = []
    @Published var rootFolders: [Option] = []

    @Published var isLoading = false
    @Published var isSaving = false
    @Published var statusMessage: String?
    @Published var saved = false

    /// The root folder that currently contains the item, used to detect a move.
    private var initialRootFolderPath: String?

    init(entry: MediaEntry) {
        self.entry = entry
        self.monitored = entry.isMonitored
        self.qualityProfileId = entry.qualityProfileId
        self.metadataProfileId = entry.metadataProfileId
    }

    var isArtist: Bool { entry.kind == .artist }

    /// True when the user has picked a root folder different from the current one.
    var pathChanged: Bool {
        guard let rootFolderPath else { return false }
        return rootFolderPath != initialRootFolderPath
    }

    func load(store: InstanceStore) async {
        isLoading = true
        defer { isLoading = false }
        switch entry {
        case let .series(instance, _):
            guard let c = store.sonarrClient(for: instance) else { return }
            qualityProfiles = ((try? await c.qualityProfiles()) ?? []).map { Option(id: $0.id, name: $0.name) }
            rootFolders = ((try? await c.rootFolders()) ?? []).map { Option(id: $0.id, name: $0.path) }
        case let .movie(instance, _):
            guard let c = store.radarrClient(for: instance) else { return }
            qualityProfiles = ((try? await c.qualityProfiles()) ?? []).map { Option(id: $0.id, name: $0.name) }
            rootFolders = ((try? await c.rootFolders()) ?? []).map { Option(id: $0.id, name: $0.path) }
        case let .artist(instance, _):
            guard let c = store.lidarrClient(for: instance) else { return }
            qualityProfiles = ((try? await c.qualityProfiles()) ?? []).map { Option(id: $0.id, name: $0.name) }
            metadataProfiles = ((try? await c.metadataProfiles()) ?? []).map { Option(id: $0.id, name: $0.name) }
            rootFolders = ((try? await c.rootFolders()) ?? []).map { Option(id: $0.id, name: $0.path) }
        }
        // Pre-select the root folder that prefixes the item's path. Prefer the
        // longest match so nested roots resolve to the most specific one.
        if let path = entry.path {
            let match = rootFolders
                .filter { path.hasPrefix($0.name) }
                .max { $0.name.count < $1.name.count }
            initialRootFolderPath = match?.name
            if rootFolderPath == nil { rootFolderPath = match?.name }
        }
    }

    func save(store: InstanceStore) async {
        isSaving = true
        defer { isSaving = false }
        let changedPath = pathChanged ? rootFolderPath : nil
        let err: String?
        switch entry {
        case let .series(instance, _):
            guard let c = store.sonarrClient(for: instance) else { saved = true; return }
            err = await Self.run {
                try await c.editSeries(ids: [entry.mediaId], monitored: monitored,
                                       qualityProfileId: qualityProfileId,
                                       rootFolderPath: changedPath, moveFiles: moveFiles)
            }
        case let .movie(instance, _):
            guard let c = store.radarrClient(for: instance) else { saved = true; return }
            err = await Self.run {
                try await c.editMovies(ids: [entry.mediaId], monitored: monitored,
                                       qualityProfileId: qualityProfileId,
                                       rootFolderPath: changedPath, moveFiles: moveFiles)
            }
        case let .artist(instance, _):
            guard let c = store.lidarrClient(for: instance) else { saved = true; return }
            err = await Self.run {
                try await c.editArtists(ids: [entry.mediaId], monitored: monitored,
                                        qualityProfileId: qualityProfileId,
                                        metadataProfileId: metadataProfileId,
                                        rootFolderPath: changedPath, moveFiles: moveFiles)
            }
        }
        if let err { statusMessage = err } else { saved = true }
    }

    private static func run(_ work: () async throws -> Void) async -> String? {
        do { try await work(); return nil }
        catch { return (error as? APIError)?.localizedDescription ?? error.localizedDescription }
    }
}

/// A reusable edit sheet for any library item. Presented from the detail views
/// and the library list's context menu.
struct LibraryItemEditView: View {
    @EnvironmentObject private var store: InstanceStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: LibraryEditViewModel
    private let onSaved: () -> Void

    init(entry: MediaEntry, onSaved: @escaping () -> Void = {}) {
        _model = StateObject(wrappedValue: LibraryEditViewModel(entry: entry))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Monitored", isOn: $model.monitored)
                }
                .tintedCards()
                Section("Quality Profile") {
                    Picker("Quality Profile", selection: $model.qualityProfileId) {
                        Text("Unchanged").tag(Int?.none)
                        ForEach(model.qualityProfiles) { Text($0.name).tag(Int?.some($0.id)) }
                    }
                }
                .tintedCards()
                if model.isArtist && !model.metadataProfiles.isEmpty {
                    Section("Metadata Profile") {
                        Picker("Metadata Profile", selection: $model.metadataProfileId) {
                            Text("Unchanged").tag(Int?.none)
                            ForEach(model.metadataProfiles) { Text($0.name).tag(Int?.some($0.id)) }
                        }
                    }
                    .tintedCards()
                }
                if !model.rootFolders.isEmpty {
                    Section("Root Folder") {
                        Picker("Root Folder", selection: $model.rootFolderPath) {
                            Text("Unchanged").tag(String?.none)
                            ForEach(model.rootFolders) { Text($0.name).tag(String?.some($0.name)) }
                        }
                        if model.pathChanged {
                            Toggle("Move files now", isOn: $model.moveFiles)
                        }
                    }
                    .tintedCards()
                }
            }
            .navigationTitle("Edit \(model.entry.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await model.save(store: store) } }
                        .disabled(model.isSaving)
                }
            }
            .overlay { if model.isLoading { ProgressView() } }
            .overlay(alignment: .bottom) { Toast(message: model.statusMessage) { model.statusMessage = nil } }
            .task { await model.load(store: store) }
            .onReceive(model.$saved) { if $0 { onSaved(); dismiss() } }
        }
    }
}
