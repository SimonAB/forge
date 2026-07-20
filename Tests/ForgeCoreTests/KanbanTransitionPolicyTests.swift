import Foundation
import ForgeCore
import Testing

@Suite("Kanban transition policy")
struct KanbanTransitionPolicyTests {

    @Test("Adjacent forward move is allowed")
    func adjacentForwardAllowed() {
        #expect(KanbanTransitionPolicy.validate(from: "Watch", to: "Coding") == .allowed)
    }

    @Test("Adjacent backward move is allowed")
    func adjacentBackwardAllowed() {
        #expect(KanbanTransitionPolicy.validate(from: "Write", to: "Coding") == .allowed)
    }

    @Test("Skipping ahead is rejected")
    func skipAheadRejected() {
        let decision = KanbanTransitionPolicy.validate(from: "Plan", to: "Coding")
        guard case .rejected = decision else {
            Issue.record("Expected rejection for Plan → Coding")
            return
        }
    }

    @Test("Shipped to Paused is rejected")
    func shippedToPausedRejected() {
        let decision = KanbanTransitionPolicy.validate(from: "Shipped", to: "Paused")
        guard case .rejected(let reason) = decision else {
            Issue.record("Expected rejection for Shipped → Paused")
            return
        }
        #expect(reason.contains("Shipped"))
    }

    @Test("Active to Paused is allowed")
    func activeToPausedAllowed() {
        #expect(KanbanTransitionPolicy.validate(from: "Coding", to: "Paused") == .allowed)
    }

    @Test("Paused to any column is allowed")
    func pausedResumeAllowed() {
        #expect(KanbanTransitionPolicy.validate(from: "Paused", to: "Watch") == .allowed)
        #expect(KanbanTransitionPolicy.validate(from: "Paused", to: "Review") == .allowed)
    }

    @Test("Restart to Plan is allowed")
    func restartToPlanAllowed() {
        #expect(KanbanTransitionPolicy.validate(from: "Review", to: "Plan") == .allowed)
    }

    @Test("Untagged to any column is allowed")
    func untaggedAllowed() {
        #expect(KanbanTransitionPolicy.validate(from: nil, to: "Plan") == .allowed)
        #expect(KanbanTransitionPolicy.validate(from: nil, to: "Coding") == .allowed)
    }

    @Test("Same column is allowed")
    func sameColumnAllowed() {
        #expect(KanbanTransitionPolicy.validate(from: "Watch", to: "Watch") == .allowed)
    }
}
