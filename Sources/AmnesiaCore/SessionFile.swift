import Foundation

/// The file attributes every scanner needs.
struct SessionFile {
    let updatedAt: Date
    let size: Int64

    init?(url: URL) {
        guard
            let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey, .fileSizeKey, .isRegularFileKey,
            ]),
            values.isRegularFile == true,
            let updatedAt = values.contentModificationDate,
            let size = values.fileSize
        else { return nil }

        self.updatedAt = updatedAt
        self.size = Int64(size)
    }
}
