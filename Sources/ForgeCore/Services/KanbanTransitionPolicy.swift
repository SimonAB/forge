import Foundation

/// Optional workflow guards for `forge move --strict`.
///
/// Default `forge move` remains permissive (any configured column). Strict mode
/// encodes the documented left-to-right flow plus Paused as a side column.
public enum KanbanTransitionPolicy {

    public enum Decision: Sendable, Equatable {
        case allowed
        case rejected(reason: String)
    }

    /// Main left-to-right columns (Paused is handled separately).
    public static let mainFlowOrder: [String] = [
        "Plan", "Watch", "Coding", "Write", "Review", "Shipped",
    ]

    /// Validates a column change under strict rules.
    ///
    /// - Parameters:
    ///   - fromColumn: Current column name, or `nil` if untagged.
    ///   - toColumn: Target column name (must already be a configured column).
    public static func validate(from fromColumn: String?, to toColumn: String) -> Decision {
        let from = fromColumn ?? "Untagged"

        if fromColumn == toColumn {
            return .allowed
        }

        if fromColumn == "Shipped" {
            return .rejected(reason: "Strict mode: a Shipped project must stay Shipped.")
        }

        if toColumn == "Paused" {
            return .allowed
        }

        if fromColumn == "Paused" || fromColumn == nil {
            return .allowed
        }

        // Restarting into Plan is always allowed from an active column.
        if toColumn == "Plan" {
            return .allowed
        }

        guard let fromIndex = mainFlowOrder.firstIndex(of: from),
              let toIndex = mainFlowOrder.firstIndex(of: toColumn) else {
            // Unknown names relative to the default flow (custom boards): allow.
            return .allowed
        }

        let step = abs(toIndex - fromIndex)
        if step == 1 {
            return .allowed
        }

        let direction = toIndex > fromIndex ? "forward" : "backward"
        return .rejected(
            reason: "Strict mode: cannot jump \(direction) from \(from) to \(toColumn) (move one column at a time, or via Paused)."
        )
    }
}
