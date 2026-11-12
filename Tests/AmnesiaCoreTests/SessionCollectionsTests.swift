import Foundation
import Testing

@testable import AmnesiaCore

@Suite struct SessionCollectionsTests {
    @Test func collectionNamesAreTrimmedAndMustBeUnique() throws {
        var library = SessionCollections()
        let collection = try library.create(name: "  Selena\n")
        #expect(collection.name == "Selena")
        #expect(throws: SessionCollectionError.duplicateName("selena")) {
            try library.create(name: " selena ")
        }
        #expect(throws: SessionCollectionError.emptyName) {
            try library.create(name: " \n")
        }
        #expect(library.collections == [collection])
    }

    @Test func batchChangesKeepSourceIdentityAndReportOnlyChanges() throws {
        var library = SessionCollections()
        let collection = try library.create(name: "Selena")
        let codex = SessionReference(source: .codex, id: "same-id")
        let claude = SessionReference(source: .claudeCode, id: "same-id")

        #expect(library.add([codex], to: collection.id) == [codex])
        let batch = library.add([codex, claude], to: collection.id)
        #expect(batch == [claude])
        #expect(library.collections.first?.members == [codex, claude])
        #expect(library.add([claude], to: collection.id).isEmpty)
        #expect(library.remove(batch, from: collection.id) == [claude])
        #expect(library.remove(batch, from: collection.id).isEmpty)
        #expect(library.collections.first?.members == [codex])
        #expect(library.add([claude], to: UUID()).isEmpty)
    }

    @Test func collectionsPersistAndReloadFromTheSuppliedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let file = directory.appending(path: "library/collections.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        var library = try SessionCollections.load(from: file)
        #expect(library.collections.isEmpty)
        let collection = try library.create(name: "Selena")
        library.add([.init(source: .codex, id: "a"), .init(source: .claudeCode, id: "a")], to: collection.id)
        try library.save(to: file)
        #expect(try SessionCollections.load(from: file) == library)

        library.remove([.init(source: .codex, id: "a")], from: collection.id)
        try library.save(to: file)
        #expect(try SessionCollections.load(from: file) == library)
    }

    @Test func malformedFileIsNotTreatedAsAnEmptyLibrary() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let contents = Data("{not valid JSON".utf8)
        try contents.write(to: file)
        #expect(throws: DecodingError.self) { try SessionCollections.load(from: file) }
        #expect(try Data(contentsOf: file) == contents)
    }
}
