/// Which rows of a list are selected, following the usual Mac rules for plain,
/// Command and Shift clicks.
public struct ListSelection: Hashable, Sendable {
    public enum Click: Sendable {
        case plain, toggle, extend
    }

    public private(set) var ids: Set<String>
    private var anchor: String?

    public init(ids: Set<String> = []) {
        self.ids = ids
        anchor = ids.first
    }

    public mutating func click(_ id: String, _ click: Click, in ordered: [String]) {
        switch click {
        case .plain:
            ids = [id]
            anchor = id
        case .toggle:
            ids.formSymmetricDifference([id])
            anchor = id
        case .extend:
            guard let anchor, let start = ordered.firstIndex(of: anchor),
                let end = ordered.firstIndex(of: id)
            else {
                self.click(id, .plain, in: ordered)
                return
            }
            ids = Set(ordered[min(start, end)...max(start, end)])
        }
    }

    /// Selects the row before or after the current one.
    public mutating func move(by offset: Int, in ordered: [String]) {
        let current = anchor.flatMap(ordered.firstIndex(of:))
        let target = current.map { $0 + offset } ?? 0
        guard ordered.indices.contains(target) else { return }
        click(ordered[target], .plain, in: ordered)
    }

    /// Keeps only the given ids.
    public mutating func limit(to allowed: Set<String>) {
        ids.formIntersection(allowed)
        if let anchor, !allowed.contains(anchor) {
            self.anchor = nil
        }
    }

    public mutating func clear() {
        self = ListSelection()
    }
}
