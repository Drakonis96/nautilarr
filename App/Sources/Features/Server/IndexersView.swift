import SwiftUI
import NautilarrCore

/// Top-level "Indexers" destination. For a single Prowlarr it shows a segmented
/// Search / Indexers screen directly (consistent with the Subtitles tab); with
/// several Prowlarr instances it lists them first.
struct IndexersView: View {
    @EnvironmentObject private var instanceStore: InstanceStore
    private var prowlarr: [ServiceInstance] { instanceStore.instances(ofType: .prowlarr) }

    var body: some View {
        Group {
            if prowlarr.isEmpty {
                ContentUnavailableLabel(
                    "No indexers",
                    systemImage: "magnifyingglass.circle",
                    description: "Add a Prowlarr service in Settings to search and manage your indexers."
                )
            } else if prowlarr.count == 1 {
                ProwlarrHubView(instance: prowlarr[0])
            } else {
                List {
                    ForEach(prowlarr) { instance in
                        NavigationLink {
                            ProwlarrHubView(instance: instance)
                        } label: { Label(instance.name, systemImage: "magnifyingglass.circle") }
                    }
                }
            }
        }
    }
}

/// Segmented Search / Indexers for one Prowlarr instance.
private struct ProwlarrHubView: View {
    let instance: ServiceInstance
    private enum Segment: Hashable { case search, indexers }
    @State private var segment: Segment = .search

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                Text("Search").tag(Segment.search)
                Text("Indexers").tag(Segment.indexers)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            if segment == .search {
                ProwlarrSearchView(instance: instance)
            } else {
                ProwlarrIndexersView(instance: instance)
            }
        }
    }
}
