import SwiftUI
import NautilarrCore

/// Displays a service's official logo (bundled vector asset) when available,
/// falling back to its SF Symbol. Used wherever a service is represented.
struct ServiceIcon: View {
    let type: ServiceType
    var size: CGFloat = 28

    var body: some View {
        if let asset = type.logoAssetName, Self.assetExists(asset) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: type.symbolName)
                .font(.system(size: size * 0.78))
                .foregroundStyle(Theme.teal)
                .frame(width: size, height: size)
        }
    }

    private static func assetExists(_ name: String) -> Bool {
        #if canImport(UIKit)
        return UIImage(named: name) != nil
        #else
        return true
        #endif
    }
}
