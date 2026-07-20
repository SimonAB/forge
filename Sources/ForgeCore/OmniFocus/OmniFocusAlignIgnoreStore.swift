import Foundation

/// Paths/tags the user has opted to ignore during OmniFocus align (OF-only / rename suggestions).
public enum OmniFocusAlignIgnoreStore {
    public static let relativePath = ".cache/omnifocus-align-ignore.json"

    public struct Payload: Codable, Sendable, Equatable {
        public var folderNames: [String]
        public var ofTags: [String]

        public init(folderNames: [String] = [], ofTags: [String] = []) {
            self.folderNames = folderNames
            self.ofTags = ofTags
        }

        public var folderSet: Set<String> { Set(folderNames) }
        public var ofTagSet: Set<String> { Set(ofTags) }
    }

    public static func filePath(forgeDir: String) -> String {
        (forgeDir as NSString).appendingPathComponent(relativePath)
    }

    public static func load(forgeDir: String) -> Payload {
        let path = filePath(forgeDir: forgeDir)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return Payload()
        }
        return payload
    }

    public static func save(_ payload: Payload, forgeDir: String) throws {
        let path = filePath(forgeDir: forgeDir)
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(payload)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// Add a folder name and/or OF tag path to the ignore list.
    public static func add(
        forgeDir: String,
        folderName: String? = nil,
        ofTag: String? = nil
    ) throws {
        var payload = load(forgeDir: forgeDir)
        if let folderName, !payload.folderNames.contains(folderName) {
            payload.folderNames.append(folderName)
            payload.folderNames.sort()
        }
        if let ofTag, !payload.ofTags.contains(ofTag) {
            payload.ofTags.append(ofTag)
            payload.ofTags.sort()
        }
        try save(payload, forgeDir: forgeDir)
    }
}
