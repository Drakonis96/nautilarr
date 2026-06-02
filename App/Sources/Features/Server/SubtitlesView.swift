import SwiftUI
import NautilarrCore

/// Top-level "Subtitles" destination — Bazarr wanted lists. Shows a single
/// instance directly, or a chooser when several are configured.
struct SubtitlesView: View {
    @EnvironmentObject private var instanceStore: InstanceStore
    private var bazarr: [ServiceInstance] { instanceStore.instances(ofType: .bazarr) }

    var body: some View {
        Group {
            if bazarr.isEmpty {
                ContentUnavailableLabel(
                    "No subtitles",
                    systemImage: "captions.bubble",
                    description: "Add a Bazarr service in Settings to manage missing subtitles."
                )
            } else if bazarr.count == 1 {
                BazarrWantedView(instance: bazarr[0])
            } else {
                List {
                    ForEach(bazarr) { instance in
                        NavigationLink {
                            BazarrWantedView(instance: instance)
                        } label: { Label(instance.name, systemImage: "captions.bubble") }
                    }
                }
            }
        }
    }
}
