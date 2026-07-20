import Foundation

extension Notification.Name {
    /// Posted when Forge.app writes `config.yaml` (Preferences). Object is the config path string.
    public static let forgeConfigDidChange = Notification.Name("forge.config.didChange")
}
