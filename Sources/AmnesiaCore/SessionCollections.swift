import Foundation

extension SessionSource: Codable {}

/// Identifies a conversation without depending on the scan's path or metadata.
public struct SessionReference: Hashable, Codable, Sendable {
    public let source: SessionSource
    public let id: String

    public init(source: SessionSource, id: String) {
        self.source = source
        self.id = id
    }

    public init(_ session: Session) {
        self.init(source: session.source, id: session.id)
    }
}

public struct SessionCollection: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public fileprivate(set) var members: Set<SessionReference>
}

public enum SessionCollectionError: LocalizedError, Equatable {
    case emptyName
    case duplicateName(String)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a collection name."
        case .duplicateName(let name): "A collection named ‘\(name)’ already exists."
        case .invalidData: "The collections file contains invalid collections."
        }
    }
}

/// Amnesia's own collection metadata. It stores no paths or transcript data.
public struct SessionCollections: Equatable, Sendable {
    public private(set) var collections: [SessionCollection] = []

    public init() {}

    @discardableResult
    public mutating func create(name: String) throws -> SessionCollection {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SessionCollectionError.emptyName }
        guard !collections.contains(where: { Self.nameKey($0.name) == Self.nameKey(name) }) else {
            throw SessionCollectionError.duplicateName(name)
        }
        let collection = SessionCollection(id: UUID(), name: name, members: [])
        collections.append(collection)
        return collection
    }

    /// Returns only newly added members, so undo can leave existing members alone.
    @discardableResult
    public mutating func add(
        _ references: Set<SessionReference>, to collectionID: UUID
    ) -> Set<SessionReference> {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return [] }
        let inserted = references.subtracting(collections[index].members)
        collections[index].members.formUnion(inserted)
        return inserted
    }

    @discardableResult
    public mutating func remove(
        _ references: Set<SessionReference>, from collectionID: UUID
    ) -> Set<SessionReference> {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return [] }
        let removed = references.intersection(collections[index].members)
        collections[index].members.subtract(removed)
        return removed
    }

    /// A missing file represents a fresh library. Read or decoding failures are errors.
    public static func load(from url: URL) throws -> SessionCollections {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return SessionCollections()
        }
        let stored = try JSONDecoder().decode(CollectionFile.self, from: data).collections
        let names = stored.map { nameKey($0.name) }
        guard !names.contains(""),
              Set(names).count == stored.count,
              Set(stored.map(\.id)).count == stored.count else {
            throw SessionCollectionError.invalidData
        }
        var result = SessionCollections()
        result.collections = stored
        return result
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(CollectionFile(collections: collections))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: .caseInsensitive, locale: nil)
    }

    private struct CollectionFile: Codable {
        let collections: [SessionCollection]
    }
}
