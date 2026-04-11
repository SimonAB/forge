import Foundation

/// Rules for which Finder tags may be added or removed with `forge project-tag` (meta and assignee only;
/// workflow column tags belong to `forge move`).
public enum ProjectFolderTagPolicy {

    public enum ValidationResult: Sendable, Equatable {
        /// Meta tag from `board.meta_tags` or a `#Person` assignee tag.
        case allowed
        /// Matches a kanban column Finder tag (including aliases); use `forge move` instead.
        case workflowColumn
        /// Not a configured meta tag and not a `#…` assignee tag; use `--force` to override.
        case unrecognized
    }

    /// Classifies a tag string for CLI validation (when `--force` is false).
    public static func validationResult(tag: String, config: ForgeConfig) -> ValidationResult {
        if config.column(forTag: tag) != nil {
            return .workflowColumn
        }
        if config.board.metaTags.contains(tag) {
            return .allowed
        }
        if ForgeTask.normalisedAssigneeIdentifier(fromRawTag: tag) != nil {
            return .allowed
        }
        return .unrecognized
    }
}
