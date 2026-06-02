import Foundation

/// Runtime language override. The standard `AppleLanguages` preference only
/// applies on the *next* launch (and is unreliable on Mac Catalyst), so to switch
/// the UI language *immediately* we swap `Bundle.main`'s class for one that
/// resolves localized strings against the chosen `.lproj`.
final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        switch LanguageOverride.current {
        case .bundle(let bundle):
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        case .base:
            // The development language (English): keys ARE the English strings.
            return value ?? key
        case .system:
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
    }
}

/// What `Bundle.main.localizedString` should do.
enum LanguageOverride {
    case system            // follow the device language
    case base              // force the development language (English literals)
    case bundle(Bundle)    // force a specific bundled .lproj

    /// Stored on `LocalizedBundle` via an associated object so the override
    /// survives across the swizzled instance.
    static var current: LanguageOverride {
        get { (objc_getAssociatedObject(Bundle.main, &key) as? Box)?.value ?? .system }
        set { objc_setAssociatedObject(Bundle.main, &key, Box(newValue), .OBJC_ASSOCIATION_RETAIN) }
    }
    private final class Box { let value: LanguageOverride; init(_ v: LanguageOverride) { value = v } }
    private static var key: UInt8 = 0
}

extension Bundle {
    /// Applies a language override. Pass `nil`/"" to follow the system language.
    static func setAppLanguage(_ code: String?) {
        if !(Bundle.main is LocalizedBundle) {
            object_setClass(Bundle.main, LocalizedBundle.self)
        }
        guard let code, !code.isEmpty else { LanguageOverride.current = .system; return }
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) {
            LanguageOverride.current = .bundle(bundle)
        } else {
            // e.g. "en" with no en.lproj — use the base English keys, not the
            // system language (which is what `super` would otherwise return).
            LanguageOverride.current = .base
        }
    }
}
