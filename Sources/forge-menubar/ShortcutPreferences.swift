import AppKit
import Foundation

/// Persistent, user-editable keyboard shortcuts for Forge menubar actions.
/// Stored in UserDefaults; changes post `ShortcutPreferences.didChangeNotification` so menus and global monitor can update.
@MainActor
enum ShortcutPreferences {

    static let didChangeNotification = Notification.Name("ShortcutPreferencesDidChange")

    enum Identifier: String, CaseIterable {
        case openBoard = "openBoard"
        case capture = "capture"
    }

    /// Stored key + modifiers for one shortcut. Used for menu items and global monitor matching.
    struct Spec: Equatable {
        let keyEquivalent: String
        let keyCode: UInt16
        let modifierFlags: NSEvent.ModifierFlags
    }

    private static let keyPrefix = "forge.shortcut."

    private static var defaults: UserDefaults { .standard }

    private static let defaultSpecs: [Identifier: Spec] = [
        .openBoard: Spec(keyEquivalent: "b", keyCode: 11, modifierFlags: .command),
        // ⌃⌘Space — quick capture (device-independent modifiers).
        .capture: Spec(keyEquivalent: " ", keyCode: 49, modifierFlags: [.control, .command]),
    ]

    /// Human-readable label for each shortcut (for Preferences UI).
    static func label(for id: Identifier) -> String {
        switch id {
        case .openBoard: return "Board"
        case .capture: return "Capture"
        }
    }

    /// Returns the current spec for the identifier (saved or default).
    static func spec(for id: Identifier) -> Spec {
        let k = keyPrefix + id.rawValue
        guard let keyEq = defaults.string(forKey: k + ".key"),
              let keyCodeRaw = defaults.object(forKey: k + ".keyCode") as? Int,
              let modRaw = defaults.object(forKey: k + ".modifiers") as? UInt else {
            return defaultSpecs[id]!
        }
        return Spec(
            keyEquivalent: keyEq,
            keyCode: UInt16(keyCodeRaw),
            modifierFlags: NSEvent.ModifierFlags(rawValue: modRaw)
        )
    }

    /// Saves the shortcut and posts didChangeNotification.
    static func set(_ id: Identifier, spec new: Spec) {
        let k = keyPrefix + id.rawValue
        defaults.set(new.keyEquivalent, forKey: k + ".key")
        defaults.set(Int(new.keyCode), forKey: k + ".keyCode")
        defaults.set(new.modifierFlags.rawValue, forKey: k + ".modifiers")
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Resets the shortcut to the default.
    static func reset(_ id: Identifier) {
        let k = keyPrefix + id.rawValue
        defaults.removeObject(forKey: k + ".key")
        defaults.removeObject(forKey: k + ".keyCode")
        defaults.removeObject(forKey: k + ".modifiers")
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Display string for the shortcut (e.g. "⇧⌘N", "⌃⌥⌘.").
    static func displayString(for spec: Spec) -> String {
        var s = ""
        if spec.modifierFlags.contains(.control) { s += "⌃" }
        if spec.modifierFlags.contains(.option) { s += "⌥" }
        if spec.modifierFlags.contains(.shift) { s += "⇧" }
        if spec.modifierFlags.contains(.command) { s += "⌘" }
        let key = spec.keyEquivalent.isEmpty ? keyCodeDisplay(spec.keyCode) : spec.keyEquivalent
        s += key
        return s
    }

    private static func keyCodeDisplay(_ code: UInt16) -> String {
        switch code {
        case 36: return "↵"
        case 48: return "⇥"
        case 49: return "␣"
        case 51: return "⌫"
        case 53: return "⎋"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key \(code)"
        }
    }

    /// Returns true if the given key event matches this spec (for global monitor). Uses device-independent modifier mask.
    static func eventMatches(_ event: NSEvent, spec: Spec) -> Bool {
        let mask = NSEvent.ModifierFlags.deviceIndependentFlagsMask
        let mods = event.modifierFlags.intersection(mask)
        guard mods == spec.modifierFlags.intersection(mask) else { return false }
        if !spec.keyEquivalent.isEmpty {
            return event.characters == spec.keyEquivalent || event.charactersIgnoringModifiers == spec.keyEquivalent
        }
        return event.keyCode == spec.keyCode
    }
}
