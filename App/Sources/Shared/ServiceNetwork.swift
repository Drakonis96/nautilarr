import Foundation

/// A named profile that groups service instances — e.g. "Home", "Remote",
/// "Friend's Server". The user switches the active network from the header; the
/// whole app then reflects only that network's services.
struct ServiceNetwork: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}
