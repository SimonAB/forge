import Foundation

/// Prefer the synchronous `tags(at:)` overload on an existential tag store.
public func syncTags(from store: any TagWriting, at path: String) -> [String] {
    if let finder = store as? FinderTagStore {
        return (try? finder.readTags(at: path)) ?? []
    }
    if let xattr = store as? XattrTagStore {
        return (try? xattr.readTags(at: path)) ?? []
    }
    if let memory = store as? InMemoryTagStore {
        return memory.tags(at: path)
    }
    return []
}
