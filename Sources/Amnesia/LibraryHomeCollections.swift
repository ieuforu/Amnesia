import AmnesiaCore
import SwiftUI

struct LibraryHomeDropReceipt: Identifiable {
    let id = UUID()
    let collectionID: UUID
    let claude: Int
    let codex: Int
}

struct LibraryHomeCollections: View {
    let collections: [SessionCollection]
    let selectedID: UUID?
    let onSelect: (UUID?) -> Void
    let onDrop: ([SessionReference], UUID) -> Bool
    let onNew: () -> Void
    let receipt: LibraryHomeDropReceipt?

    @FocusState private var focus: FocusTarget?

    private enum FocusTarget: Hashable { case all, new }

    var body: some View {
        HStack(spacing: 10) {
            Text("COLLECTIONS")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(LibraryAppearance.muted)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal) {
                chips
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollIndicators(.hidden)
            .frame(height: 30)
            .frame(maxWidth: .infinity)

            Button(action: onNew) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                    Text("New")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(LibraryAppearance.muted)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .contentShape(Rectangle())
                .fixedSize()
            }
            .buttonStyle(LibraryHomeCollectionStyle(isFocused: focus == .new))
            .focused($focus, equals: .new)
            .accessibilityLabel("New collection")
            .help("New collection")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chips: some View {
        HStack(spacing: 3) {
            Button { onSelect(nil) } label: {
                LibraryHomeCollectionLabel(title: "All", count: nil, isSelected: selectedID == nil)
            }
            .buttonStyle(LibraryHomeCollectionStyle(isSelected: selectedID == nil, isFocused: focus == .all))
            .focused($focus, equals: .all)
            .accessibilityLabel("All sessions")
            .accessibilityAddTraits(selectedID == nil ? .isSelected : [])

            ForEach(collections) { collection in
                LibraryHomeCollectionChip(
                    collection: collection,
                    isSelected: selectedID == collection.id,
                    receipt: receipt?.collectionID == collection.id ? receipt : nil,
                    onSelect: { onSelect(collection.id) },
                    onDrop: { onDrop($0, collection.id) }
                )
            }
        }
    }
}

private struct LibraryHomeCollectionChip: View {
    let collection: SessionCollection
    let isSelected: Bool
    let receipt: LibraryHomeDropReceipt?
    let onSelect: () -> Void
    let onDrop: ([SessionReference]) -> Bool

    @State private var isTargeted = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            LibraryHomeCollectionLabel(
                title: collection.name,
                count: collection.members.count,
                isSelected: isSelected
            )
        }
        .buttonStyle(LibraryHomeCollectionStyle(isSelected: isSelected, isFocused: isFocused, isTargeted: isTargeted))
        .focused($isFocused)
        .accessibilityLabel(Text(verbatim: collection.name))
        .accessibilityValue(Text("\(collection.members.count) sessions"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(collection.name)
        .dropDestination(for: SessionReference.self) { references, _ in
            !references.isEmpty && onDrop(references)
        } isTargeted: { isTargeted = $0 }
        .overlay {
            if let receipt {
                LibraryDropParticles(claudeCount: receipt.claude, codexCount: receipt.codex)
                    .id(receipt.id)
                    .frame(width: 84, height: 30)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct LibraryHomeCollectionLabel: View {
    let title: String
    let count: Int?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? LibraryAppearance.ink : LibraryAppearance.muted)
                .lineLimit(1)
                .frame(maxWidth: 136)
            if let count {
                Text(count, format: .number)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(LibraryAppearance.muted)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .contentShape(Rectangle())
    }
}

private struct LibraryHomeCollectionStyle: ButtonStyle {
    var isSelected = false
    var isFocused = false
    var isTargeted = false

    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isTargeted || isHovered || configuration.isPressed {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LibraryAppearance.selection.opacity(isTargeted || configuration.isPressed ? 1 : 0.6))
                }
            }
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(LibraryAppearance.accent)
                        .frame(height: 1.5)
                        .padding(.horizontal, 7)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if isTargeted || isFocused {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(LibraryAppearance.accent, lineWidth: isTargeted ? 1.5 : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onHover { isHovered = $0 }
    }
}
