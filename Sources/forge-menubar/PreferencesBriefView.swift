import AppKit
import ForgeCore

/// Preferences tab that generates an LLM-backed brief from the current board and calendar context.
@MainActor
final class PreferencesBriefView: NSView {
    private let configPath: String?
    private let config: ForgeConfig?

    private var providerPopup: NSPopUpButton?
    private var baseURLField: NSTextField?
    private var modelField: NSTextField?
    private var daysField: NSTextField?
    private var includeCalendarCheckbox: NSButton?

    private var generateButton: NSButton?
    private var statusLabel: NSTextField?
    private var outputView: NSTextView?

    private var proposalsStack: NSStackView?
    private var applyButton: NSButton?

    private var lastResult: BriefResult?
    private var selectedProposalIndexes: Set<Int> = []

    init(configPath: String?, config: ForgeConfig?) {
        self.configPath = configPath
        self.config = config
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])

        guard configPath != nil, config != nil else {
            root.addArrangedSubview(NSTextField(labelWithString: "No config loaded — add config.yaml to enable Brief generation."))
            return
        }

        let privacy = NSTextField(labelWithString: "Brief is local-first. Local Ollama runs on this Mac; external providers may transmit board and calendar data.")
        privacy.textColor = .secondaryLabelColor
        privacy.maximumNumberOfLines = 0
        root.addArrangedSubview(privacy)

        let providerRow = NSStackView()
        providerRow.orientation = .horizontal
        providerRow.alignment = .centerY
        providerRow.spacing = 8

        let providerLabel = NSTextField(labelWithString: "Provider:")
        let popup = NSPopUpButton()
        popup.addItems(withTitles: ["Local Ollama", "External agent (advanced)"])
        popup.target = self
        popup.action = #selector(providerChanged)
        providerPopup = popup

        providerRow.addArrangedSubview(providerLabel)
        providerRow.addArrangedSubview(popup)
        root.addArrangedSubview(providerRow)

        let settingsGrid = NSGridView(views: [
            [NSTextField(labelWithString: "Base URL:"), NSTextField(string: "http://127.0.0.1:11434/v1")],
            [NSTextField(labelWithString: "Model:"), NSTextField(string: "qwen3-coder")],
            [NSTextField(labelWithString: "Days:"), NSTextField(string: "2")],
        ])
        settingsGrid.rowSpacing = 6
        settingsGrid.columnSpacing = 10
        settingsGrid.translatesAutoresizingMaskIntoConstraints = false
        baseURLField = settingsGrid.cell(atColumnIndex: 1, rowIndex: 0).contentView as? NSTextField
        modelField = settingsGrid.cell(atColumnIndex: 1, rowIndex: 1).contentView as? NSTextField
        daysField = settingsGrid.cell(atColumnIndex: 1, rowIndex: 2).contentView as? NSTextField
        root.addArrangedSubview(settingsGrid)

        let includeCalendar = NSButton(checkboxWithTitle: "Include Calendar events", target: nil, action: nil)
        includeCalendar.state = .on
        includeCalendarCheckbox = includeCalendar
        root.addArrangedSubview(includeCalendar)

        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 10
        let generate = NSButton(title: "Generate brief", target: self, action: #selector(generateBrief))
        generateButton = generate
        let status = NSTextField(labelWithString: "")
        status.textColor = .secondaryLabelColor
        statusLabel = status
        actionRow.addArrangedSubview(generate)
        actionRow.addArrangedSubview(status)
        root.addArrangedSubview(actionRow)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 170).isActive = true

        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = true
        text.string = ""
        outputView = text
        scroll.documentView = text
        root.addArrangedSubview(scroll)

        let proposalsLabel = NSTextField(labelWithString: "Proposals (optional)")
        proposalsLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        root.addArrangedSubview(proposalsLabel)

        let proposalsStack = NSStackView()
        proposalsStack.orientation = .vertical
        proposalsStack.alignment = .leading
        proposalsStack.spacing = 6
        proposalsStack.translatesAutoresizingMaskIntoConstraints = false
        self.proposalsStack = proposalsStack
        root.addArrangedSubview(proposalsStack)

        let apply = NSButton(title: "Apply selected", target: self, action: #selector(applySelected))
        apply.isEnabled = false
        applyButton = apply
        root.addArrangedSubview(apply)

        updateProviderEnabledState()
    }

    @objc private func providerChanged() {
        updateProviderEnabledState()
    }

    private func updateProviderEnabledState() {
        let isExternal = (providerPopup?.indexOfSelectedItem ?? 0) == 1
        baseURLField?.isEnabled = !isExternal
        modelField?.isEnabled = !isExternal
        statusLabel?.stringValue = isExternal ? "External agent provider is not yet implemented." : ""
    }

    @objc private func generateBrief() {
        guard let config, let configPath else { return }
        let forgeDir = (configPath as NSString).deletingLastPathComponent

        let includeCalendar = (includeCalendarCheckbox?.state ?? .on) == .on
        let days = Int(daysField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 2

        let providerIndex = providerPopup?.indexOfSelectedItem ?? 0
        statusLabel?.stringValue = "Working…"
        generateButton?.isEnabled = false
        applyButton?.isEnabled = false
        outputView?.string = ""
        setProposals([])

        Task {
            do {
                let context = try await BriefContextBuilder(config: config, forgeDir: forgeDir).build(days: max(1, days), includeCalendar: includeCalendar)
                let result: BriefResult
                if providerIndex == 0 {
                    let baseURL = URL(string: baseURLField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                    guard let baseURL else { throw ForgeAIError.invalidEndpoint("Invalid base URL.") }
                    let model = modelField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "qwen3-coder"
                    let settings = LocalOllamaProvider.Settings(baseURL: baseURL, model: model)
                    result = try await LocalOllamaProvider(settings: settings).generateBrief(context: context)
                } else {
                    let endpoint = URL(string: "http://127.0.0.1:0")!
                    result = try await ExternalAgentProvider(settings: .init(endpoint: endpoint)).generateBrief(context: context)
                }

                lastResult = result
                outputView?.string = result.briefMarkdown
                setProposals(result.proposals)
                statusLabel?.stringValue = "Done."
            } catch {
                statusLabel?.stringValue = error.localizedDescription
            }
            generateButton?.isEnabled = true
        }
    }

    private func setProposals(_ proposals: [BriefProposal]) {
        selectedProposalIndexes = []
        proposalsStack?.arrangedSubviews.forEach { v in
            proposalsStack?.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        for (idx, proposal) in proposals.enumerated() {
            let title = proposalTitle(proposal)
            let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(proposalToggled(_:)))
            checkbox.tag = idx
            proposalsStack?.addArrangedSubview(checkbox)
        }
        applyButton?.isEnabled = false
    }

    private func proposalTitle(_ p: BriefProposal) -> String {
        switch p.kind {
        case .move:
            return "Move \(lastPathComponent(p.projectPath)) → \(p.columnName ?? "?") — \(p.why)"
        case .tagAdd:
            return "Add \(p.tag ?? "?") to \(lastPathComponent(p.projectPath)) — \(p.why)"
        case .tagRemove:
            return "Remove \(p.tag ?? "?") from \(lastPathComponent(p.projectPath)) — \(p.why)"
        }
    }

    private func lastPathComponent(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    @objc private func proposalToggled(_ sender: NSButton) {
        if sender.state == .on {
            selectedProposalIndexes.insert(sender.tag)
        } else {
            selectedProposalIndexes.remove(sender.tag)
        }
        applyButton?.isEnabled = !selectedProposalIndexes.isEmpty
    }

    @objc private func applySelected() {
        guard let config, let result = lastResult else { return }
        let selected = result.proposals.enumerated().compactMap { idx, p in
            selectedProposalIndexes.contains(idx) ? p : nil
        }
        guard !selected.isEmpty else { return }

        do {
            let changes = try BriefProposalApplier(config: config).apply(selected)
            if changes.isEmpty {
                statusLabel?.stringValue = "No changes applied."
            } else {
                statusLabel?.stringValue = "Applied: " + changes.map(\.description).joined(separator: " • ")
            }
            applyButton?.isEnabled = false
        } catch {
            statusLabel?.stringValue = error.localizedDescription
        }
    }
}
