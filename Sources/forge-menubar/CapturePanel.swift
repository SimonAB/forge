import AppKit

/// A floating panel for quick task capture. Appears centred on screen,
/// accepts a single line of text, and dismisses on Enter or Escape.
final class CapturePanel {

    private var window: NSPanel?
    private var textField: NSTextField?
    private let onCapture: (String) -> Void

    init(onCapture: @escaping (String) -> Void) {
        self.onCapture = onCapture
    }

    func show() {
        if window == nil {
            createWindow()
        }

        textField?.stringValue = ""
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        textField?.becomeFirstResponder()
    }

    private func createWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 60),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Forge — Quick Capture"
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 60))

        let label = NSTextField(labelWithString: "⚒ Capture:")
        label.frame = NSRect(x: 12, y: 18, width: 80, height: 24)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        container.addSubview(label)

        let field = CaptureTextField(frame: NSRect(x: 95, y: 16, width: 390, height: 28))
        field.font = .systemFont(ofSize: 14)
        field.placeholderString = "Task description… (@due, @ctx tags supported)"
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.target = self
        field.action = #selector(textFieldAction(_:))
        field.capturePanel = self
        container.addSubview(field)

        panel.contentView = container
        self.window = panel
        self.textField = field
    }

    @objc private func textFieldAction(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        onCapture(text)
        window?.orderOut(nil)
    }

    func dismiss() {
        window?.orderOut(nil)
    }
}

/// Custom text field that handles Escape to dismiss the capture panel.
final class CaptureTextField: NSTextField {
    weak var capturePanel: CapturePanel?

    override func cancelOperation(_ sender: Any?) {
        capturePanel?.dismiss()
    }
}
