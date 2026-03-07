import AppKit
import ForgeCore

/// Menu bar application delegate. Manages the status item, background sync,
/// quick capture, and overdue notifications.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
        statusBar.start()
    }
}
