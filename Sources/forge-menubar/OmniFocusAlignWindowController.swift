import AppKit
import ForgeCore

/// Preview-first OmniFocus align sheet (dry-run plan; Apply writes after confirmation).
@MainActor
final class OmniFocusAlignWindowController: NSWindowController {

    private let config: ForgeConfig
    private let forgeDir: String
    private var plan: OmniFocusAlignPlan
    private var tableView: NSTableView!
    private var statusLabel: NSTextField!
    private var applyButton: NSButton!
    private var isApplying = false

    init(config: ForgeConfig, forgeDir: String, plan: OmniFocusAlignPlan) {
        self.config = config
        self.forgeDir = forgeDir
        self.plan = plan
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OmniFocus Align"
        window.center()
        super.init(window: window)
        window.contentView = buildContent()
        reloadTable()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildContent() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 420))

        let blurb = NSTextField(wrappingLabelWithString: """
        Dry-run plan — nothing is written until you press Apply. Review each proposal, then Apply to update OmniFocus and/or Finder tags.
        """)
        blurb.font = .systemFont(ofSize: 12)
        blurb.textColor = .secondaryLabelColor
        blurb.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(blurb)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = 28
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("summary"))
        column.title = "Proposal"
        column.width = 680
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        tableView = table

        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(status)
        statusLabel = status

        let refresh = NSButton(title: "Refresh plan", target: self, action: #selector(refreshPlan))
        refresh.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(refresh)

        let apply = NSButton(title: "Apply", target: self, action: #selector(applyPlan))
        apply.translatesAutoresizingMaskIntoConstraints = false
        apply.keyEquivalent = "\r"
        root.addSubview(apply)
        applyButton = apply

        let close = NSButton(title: "Close", target: self, action: #selector(closeSheet))
        close.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(close)

        NSLayoutConstraint.activate([
            blurb.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            blurb.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            blurb.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: blurb.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -12),

            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(lessThanOrEqualTo: refresh.leadingAnchor, constant: -8),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),

            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            close.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),

            apply.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),
            apply.centerYAnchor.constraint(equalTo: close.centerYAnchor),

            refresh.trailingAnchor.constraint(equalTo: apply.leadingAnchor, constant: -8),
            refresh.centerYAnchor.constraint(equalTo: close.centerYAnchor),
        ])

        return root
    }

    private func reloadTable() {
        tableView.reloadData()
        let count = plan.proposals.count
        statusLabel.stringValue = count == 0
            ? "No proposals — inventories look aligned."
            : "\(count) proposal(s) (dry-run)."
        applyButton.isEnabled = count > 0 && !isApplying
    }

    @objc private func refreshPlan() {
        Task {
            do {
                let plan = try await Self.loadPlan(config: config, forgeDir: forgeDir)
                await MainActor.run {
                    self.plan = plan
                    self.reloadTable()
                }
            } catch {
                await MainActor.run {
                    self.statusLabel.stringValue = error.localizedDescription
                    self.statusLabel.textColor = .systemRed
                }
            }
        }
    }

    @objc private func applyPlan() {
        guard !plan.proposals.isEmpty, !isApplying else { return }
        let alert = NSAlert()
        alert.messageText = "Apply \(plan.proposals.count) OmniFocus align proposal(s)?"
        alert.informativeText = "This may create OF tags and/or change Finder workflow tags."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isApplying = true
        applyButton.isEnabled = false
        statusLabel.stringValue = "Applying…"
        statusLabel.textColor = .secondaryLabelColor

        Task {
            do {
                let service = OmniFocusService(config: config)
                let result = try OmniFocusPlanExecutor.executeAlign(
                    plan: plan,
                    apply: true,
                    service: service,
                    config: config,
                    forgeDir: forgeDir
                )
                _ = try? service.refreshSnapshot(forgeDir: forgeDir)
                let refreshed = try await Self.loadPlan(config: config, forgeDir: forgeDir)
                await MainActor.run {
                    self.isApplying = false
                    switch result {
                    case .dryRun:
                        break
                    case .applied(let applied, let errors):
                        self.statusLabel.stringValue = errors.isEmpty
                            ? "Applied \(applied.count) proposal(s)."
                            : "Applied \(applied.count); \(errors.count) error(s)."
                        self.statusLabel.textColor = errors.isEmpty ? .secondaryLabelColor : .systemOrange
                    }
                    self.plan = refreshed
                    self.reloadTable()
                }
            } catch {
                await MainActor.run {
                    self.isApplying = false
                    self.statusLabel.stringValue = error.localizedDescription
                    self.statusLabel.textColor = .systemRed
                    self.applyButton.isEnabled = !self.plan.proposals.isEmpty
                }
            }
        }
    }

    @objc private func closeSheet() {
        window?.close()
    }

    static func loadPlan(config: ForgeConfig, forgeDir: String) async throws -> OmniFocusAlignPlan {
        let scanner = WorkspaceScanner(config: config)
        let projects = try await scanner.scanProjects()
        let service = OmniFocusService(config: config)
        try service.requireEnabled()
        let inventory = try service.fetchInventory()
        let ignore = OmniFocusAlignIgnoreStore.load(forgeDir: forgeDir)
        return OmniFocusAlignment.alignPlan(
            projects: projects,
            inventory: inventory,
            config: config,
            preference: .finder,
            ignore: ignore
        )
    }

    static func present(config: ForgeConfig, forgeDir: String) {
        Task {
            do {
                let plan = try await loadPlan(config: config, forgeDir: forgeDir)
                await MainActor.run {
                    let controller = OmniFocusAlignWindowController(
                        config: config,
                        forgeDir: forgeDir,
                        plan: plan
                    )
                    controller.showWindow(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "OmniFocus Align"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }
}

extension OmniFocusAlignWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        plan.proposals.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField
            ?? NSTextField(labelWithString: "")
        cell.identifier = id
        cell.font = .systemFont(ofSize: 12)
        cell.lineBreakMode = .byTruncatingTail
        let proposal = plan.proposals[row]
        cell.stringValue = "[\(proposal.kind.rawValue)] \(proposal.summary)"
        return cell
    }
}
