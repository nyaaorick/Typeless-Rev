import Foundation

/// A privacy permission as the menu shows it.
enum PermissionStatus: Equatable {
    case notDetermined
    case allowed
    case denied
    /// Blocked by a profile or parental controls; the user cannot change it.
    case restricted

    func menuTitle(_ name: String) -> String {
        switch self {
        case .notDetermined: return "\(name): Not Asked Yet"
        case .allowed: return "\(name): Allowed"
        case .denied: return "\(name): Off"
        case .restricted: return "\(name): Restricted"
        }
    }

    /// What the user can do about it from the menu, or nil when there is nothing to do.
    var actionTitle: String? {
        switch self {
        case .notDetermined: return "Allow…"
        case .denied: return "Open Privacy Settings…"
        case .allowed, .restricted: return nil
        }
    }
}
