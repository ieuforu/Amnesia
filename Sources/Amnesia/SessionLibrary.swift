import AmnesiaCore
import Foundation
import Observation

@MainActor
@Observable
final class SessionLibrary {
    private(set) var contents = SessionCollections()
    var error: String?

    private let file: URL?
    private(set) var canEdit = true

    init(demo: Bool) {
        let libraryFolder = Bundle.main.bundleIdentifier == "com.ieuforu.Amnesia.preview" ? "Amnesia Preview" : "Amnesia"
        file = demo ? nil : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: libraryFolder, directoryHint: .isDirectory)
            .appending(path: "SessionCollections.json", directoryHint: .notDirectory)

        if let file {
            do {
                contents = try SessionCollections.load(from: file)
            } catch {
                canEdit = false
                self.error = "Couldn't read your collections. \(error.localizedDescription)"
            }
        } else if demo {
            _ = try? contents.create(name: "Release notes")
            _ = try? contents.create(name: "To revisit")
        } else {
            canEdit = false
            error = "Couldn't find the Application Support folder."
        }
    }

    func create(_ name: String) throws -> UUID {
        var draft = contents
        let collection = try draft.create(name: name)
        try save(draft)
        return collection.id
    }

    @discardableResult
    func setMembership(
        of sessions: Set<SessionReference>, in collection: UUID, to isMember: Bool, undo: UndoManager?
    ) -> Set<SessionReference> {
        var draft = contents
        let changed = isMember ? draft.add(sessions, to: collection) : draft.remove(sessions, from: collection)
        guard !changed.isEmpty else { return [] }

        do {
            try save(draft)
        } catch {
            self.error = "Couldn't save the collection. \(error.localizedDescription)"
            return []
        }

        if let undo {
            undo.registerUndo(withTarget: self) { [weak undo] library in
                MainActor.assumeIsolated {
                    _ = library.setMembership(of: changed, in: collection, to: !isMember, undo: undo)
                }
            }
            undo.setActionName("Change Collection")
        }
        return changed
    }

    private func save(_ draft: SessionCollections) throws {
        guard canEdit else { throw CocoaError(.fileWriteNoPermission) }
        if let file { try draft.save(to: file) }
        contents = draft
    }
}
