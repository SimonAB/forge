import AppKit

/// Bare-bones preferences window. Follows macOS conventions (title "Preferences", close/minimize).
final class PreferencesWindowController: NSWindowController {

    static let windowTitle = "Preferences"

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = Self.windowTitle
        window.center()
        super.init(window: window)

        let content = PreferencesContentView()
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            content.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            content.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindow() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Simple preferences content: General section placeholder.
private final class PreferencesContentView: NSView {

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let label = NSTextField(labelWithString: "General")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let sublabel = NSTextField(labelWithString: "More options will appear here.")
        sublabel.font = .systemFont(ofSize: 12, weight: .regular)
        sublabel.textColor = .secondaryLabelColor
        sublabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sublabel)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            sublabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            sublabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
