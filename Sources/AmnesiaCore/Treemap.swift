import CoreGraphics

/// Lays out values as rectangles whose areas match them, keeping each as close
/// to square as possible (the squarified treemap algorithm).
public enum Treemap {
    public struct Item: Sendable {
        public let id: String
        public let value: Double

        public init(id: String, value: Double) {
            self.id = id
            self.value = value
        }
    }

    public static func layout(_ items: [Item], in bounds: CGRect) -> [String: CGRect] {
        let positive = items.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let total = positive.reduce(0) { $0 + $1.value }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return [:] }

        let scale = bounds.width * bounds.height / total
        var remaining = positive[...]
        var space = bounds
        var result: [String: CGRect] = [:]

        while !remaining.isEmpty {
            let side = min(space.width, space.height)
            var row: [Item] = []
            var worst = CGFloat.infinity

            while let next = remaining.first {
                let candidate = row + [next]
                let ratio = worstRatio(candidate, scale: scale, side: side)
                guard ratio <= worst else { break }
                worst = ratio
                row = candidate
                remaining.removeFirst()
            }
            space = place(row, scale: scale, in: space, result: &result)
        }
        return result
    }

    private static func worstRatio(_ row: [Item], scale: Double, side: CGFloat) -> CGFloat {
        let areas = row.map { CGFloat($0.value * scale) }
        let sum = areas.reduce(0, +)
        guard let largest = areas.max(), let smallest = areas.min(), smallest > 0 else { return .infinity }
        return max(side * side * largest / (sum * sum), sum * sum / (side * side * smallest))
    }

    /// Fills the short side of `space` with a row and returns what's left.
    private static func place(
        _ row: [Item],
        scale: Double,
        in space: CGRect,
        result: inout [String: CGRect]
    ) -> CGRect {
        let area = row.reduce(CGFloat(0)) { $0 + CGFloat($1.value * scale) }
        var offset: CGFloat = 0

        if space.width >= space.height {
            let width = area / space.height
            for item in row {
                let height = CGFloat(item.value * scale) / width
                result[item.id] = CGRect(x: space.minX, y: space.minY + offset, width: width, height: height)
                offset += height
            }
            return CGRect(x: space.minX + width, y: space.minY, width: space.width - width, height: space.height)
        }

        let height = area / space.width
        for item in row {
            let width = CGFloat(item.value * scale) / height
            result[item.id] = CGRect(x: space.minX + offset, y: space.minY, width: width, height: height)
            offset += width
        }
        return CGRect(x: space.minX, y: space.minY + height, width: space.width, height: space.height - height)
    }
}
