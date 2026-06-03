import SwiftUI
import NautilarrCore

/// A top-level section for a single service type (Tautulli, Jellystat, Unraid,
/// SSH). With one configured instance it shows its dashboard directly; with
/// several it adds a chip bar to switch between them.
struct ServiceSection<Detail: View>: View {
    let type: ServiceType
    let emptyTitle: LocalizedStringKey
    let emptyDescription: LocalizedStringKey
    @ViewBuilder let detail: (ServiceInstance) -> Detail

    @EnvironmentObject private var instanceStore: InstanceStore
    @EnvironmentObject private var settings: AppSettings
    @State private var selectedID: UUID?

    private var instances: [ServiceInstance] { instanceStore.instances(ofType: type) }
    private var selected: ServiceInstance? { instances.first { $0.id == selectedID } ?? instances.first }

    var body: some View {
        Group {
            if instances.isEmpty {
                ContentUnavailableLabel(emptyTitle, systemImage: type.symbolName, description: emptyDescription)
            } else if instances.count == 1 {
                detail(instances[0])
            } else {
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(instances) { instance in
                                FilterChip(title: instance.name, serviceType: instance.type,
                                           isSelected: instance.id == selected?.id) {
                                    selectedID = instance.id
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                    .frame(height: 56)
                    if let selected { detail(selected).id(selected.id) }
                }
                .appBackground(settings.background)
            }
        }
    }
}
