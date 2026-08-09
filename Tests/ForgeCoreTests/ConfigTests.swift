import Foundation
import Testing
@testable import ForgeCore

@Test func defaultConfigHasSevenColumns() {
    let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp/test"])
    #expect(config.board.columns.count == 7)
}

@Test func defaultProjectScanDepthIsOne() {
    let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp/test"])
    #expect(config.projectScanDepth == 1)
    #expect(config.resolvedProjectScanDepth == 1)
}

@Test func columnLookupResolvesAliases() {
    let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp/test"])
    let col = config.column(forTag: "active 🚧")
    #expect(col?.name == "Watch")
}

@Test func columnLookupMapsLegacyAnalyseToCoding() {
    let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp/test"])
    let col = config.column(forTag: "Analyse 🔍")
    #expect(col?.name == "Coding")
}

@Test func columnLookupFindsWatchTag() {
    let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp/test"])
    let col = config.column(forTag: "Watch 👁️")
    #expect(col?.name == "Watch")
}

@Test func columnLookupFindsCanonicalTag() {
    let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp/test"])
    let col = config.column(forTag: "Write ✒️")
    #expect(col?.name == "Write")
}

@Test func remindersDefaultIsDisabledForgeList() {
    let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp/test"])
    #expect(config.reminders.enabled == false)
    #expect(config.reminders.list == "Forge")
    #expect(config.reminders.includeCompleted == false)
    #expect(config.reminders.syncOnMove == false)
    #expect(config.reminders.syncFromReminders == false)
    #expect(config.reminders.sentinelPrefix == RemindersConfig.defaultSentinelPrefix)
    #expect(config.reminders.source == nil)
}

@Test func remindersListMigratesFromGtdWhenRemindersSectionMissing() throws {
    let config = try loadForgeYAML("""
    project_roots:
      - /tmp
    board:
      columns:
        - name: Plan
          tag: "Plan"
          colour: 4
      meta_tags: []
      tag_aliases: {}
    gtd:
      reminders_list: Inbox
    """)
    #expect(config.reminders.enabled == false)
    #expect(config.reminders.list == "Inbox")
}

@Test func remindersListWinsOverGtd() throws {
    let config = try loadForgeYAML("""
    project_roots:
      - /tmp
    board:
      columns:
        - name: Plan
          tag: "Plan"
          colour: 4
      meta_tags: []
      tag_aliases: {}
    reminders:
      enabled: true
      list: ForgeInbox
    gtd:
      reminders_list: Inbox
    """)
    #expect(config.reminders.enabled == true)
    #expect(config.reminders.list == "ForgeInbox")
}

@Test func remindersSectionWithoutListMigratesGtd() throws {
    let config = try loadForgeYAML("""
    project_roots:
      - /tmp
    board:
      columns:
        - name: Plan
          tag: "Plan"
          colour: 4
      meta_tags: []
      tag_aliases: {}
    reminders:
      enabled: true
    gtd:
      reminders_list: Inbox
    """)
    #expect(config.reminders.enabled == true)
    #expect(config.reminders.list == "Inbox")
}

@Test func remindersDecodesIncludeCompletedAndAliases() throws {
    let config = try loadForgeYAML("""
    project_roots:
      - /tmp
    board:
      columns:
        - name: Plan
          tag: "Plan"
          colour: 4
      meta_tags: []
      tag_aliases: {}
    reminders:
      enabled: true
      list: Inbox
      include_completed: true
      snapshot_max_age_seconds: 120
      folder_aliases:
        "VHP2 ms": VHP2_manuscript
    """)
    #expect(config.reminders.enabled)
    #expect(config.reminders.list == "Inbox")
    #expect(config.reminders.includeCompleted)
    #expect(config.reminders.snapshotMaxAgeSeconds == 120)
    #expect(config.reminders.folderAliases["VHP2 ms"] == "VHP2_manuscript")
}

@Test func remindersEmptyListFallsBackToDefault() throws {
    let config = try loadForgeYAML("""
    project_roots:
      - /tmp
    board:
      columns:
        - name: Plan
          tag: "Plan"
          colour: 4
      meta_tags: []
      tag_aliases: {}
    reminders:
      enabled: true
      list: "   "
    """)
    #expect(config.reminders.list == "Forge")
}

@Test func remindersRoundTripThroughSave() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("forge-config-rt-\(UUID().uuidString).yaml")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let original = try loadForgeYAML("""
    project_roots:
      - /tmp
    board:
      columns:
        - name: Plan
          tag: "Plan"
          colour: 4
      meta_tags: []
      tag_aliases: {}
    reminders:
      enabled: true
      list: Inbox
      include_completed: true
      folder_aliases:
        "VHP2 ms": VHP2_manuscript
    """)
    try original.save(to: tmp.path)
    let reloaded = try ForgeConfig.load(from: tmp.path)
    #expect(reloaded.reminders.enabled)
    #expect(reloaded.reminders.list == "Inbox")
    #expect(reloaded.reminders.includeCompleted)
    #expect(reloaded.reminders.folderAliases["VHP2 ms"] == "VHP2_manuscript")
}


@Test func remindersDecodesPhase2SyncFlags() throws {
    let config = try loadForgeYAML("""
    project_roots:
      - /tmp
    board:
      columns:
        - name: Plan
          tag: "Plan"
          colour: 4
      meta_tags: []
      tag_aliases: {}
    reminders:
      enabled: true
      sync_on_move: true
      sync_from_reminders: true
      sentinel_prefix: "Kanban · "
      source: iCloud
    """)
    #expect(config.reminders.syncOnMove)
    #expect(config.reminders.syncFromReminders)
    #expect(config.reminders.sentinelPrefix == "Kanban · ")
    #expect(config.reminders.source == "iCloud")
    #expect(config.reminders.columnSyncEnabled)
}

@Test func remindersPhase2FlagsRoundTrip() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("forge-config-p2-\(UUID().uuidString).yaml")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let original = try loadForgeYAML("""
    project_roots:
      - /tmp
    board:
      columns:
        - name: Plan
          tag: "Plan"
          colour: 4
      meta_tags: []
      tag_aliases: {}
    reminders:
      enabled: true
      sync_on_move: true
      sync_from_reminders: false
      source: "On My Mac"
    """)
    try original.save(to: tmp.path)
    let reloaded = try ForgeConfig.load(from: tmp.path)
    #expect(reloaded.reminders.syncOnMove)
    #expect(!reloaded.reminders.syncFromReminders)
    #expect(reloaded.reminders.source == "On My Mac")
}

@Test func remindersUpdatingSyncFlags() {
    let updated = RemindersConfig().updating(enabled: true, syncOnMove: true, syncFromReminders: true)
    #expect(updated.syncOnMove)
    #expect(updated.syncFromReminders)
    #expect(updated.columnSyncEnabled)
}

private func loadForgeYAML(_ yaml: String) throws -> ForgeConfig {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("forge-config-\(UUID().uuidString).yaml")
    try yaml.write(to: tmp, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tmp) }
    return try ForgeConfig.load(from: tmp.path)
}
