import DiffyCore
import SwiftUI

struct GroupColorEditor: View {
    @ObservedObject var store: DiffyStore
    let groupID: UUID

    private var group: RepositoryGroup? {
        store.groups.first { $0.id == groupID }
    }

    var body: some View {
        if let group {
            HStack(spacing: 12) {
                ColorPicker("Additions", selection: colorBinding(for: group, keyPath: \.additionHex))
                    .labelsHidden()
                    .help("Addition color")
                ColorPicker("Removals", selection: colorBinding(for: group, keyPath: \.removalHex))
                    .labelsHidden()
                    .help("Removal color")
                ColorPicker("Badge", selection: optionalColorBinding(for: group, keyPath: \.badgeBackgroundHex))
                    .labelsHidden()
                    .help("Menu bar badge background")
                Button("Clear Background") {
                    var colors = group.diffColors
                    colors.badgeBackgroundHex = nil
                    store.updateGroupColors(group.id, diffColors: colors)
                }
                .disabled(group.diffColors.badgeBackgroundHex == nil)
                Button("Reset Colors") {
                    store.updateGroupColors(group.id, diffColors: .default)
                }
            }
        }
    }

    private func colorBinding(
        for group: RepositoryGroup,
        keyPath: WritableKeyPath<DiffColors, String>
    ) -> Binding<Color> {
        Binding {
            AppColor.swiftUIColor(hex: group.diffColors[keyPath: keyPath])
        } set: { color in
            var colors = group.diffColors
            colors[keyPath: keyPath] = AppColor.hex(color)
            store.updateGroupColors(group.id, diffColors: colors)
        }
    }

    private func optionalColorBinding(
        for group: RepositoryGroup,
        keyPath: WritableKeyPath<DiffColors, String?>
    ) -> Binding<Color> {
        Binding {
            if let hex = group.diffColors[keyPath: keyPath] {
                return AppColor.swiftUIColor(hex: hex)
            }
            return .clear
        } set: { color in
            var colors = group.diffColors
            colors[keyPath: keyPath] = AppColor.hex(color)
            store.updateGroupColors(group.id, diffColors: colors)
        }
    }
}

struct GroupBadgeLabelEditor: View {
    @ObservedObject var store: DiffyStore
    let groupID: UUID

    @State private var draftText: String = ""

    private var group: RepositoryGroup? {
        store.groups.first { $0.id == groupID }
    }

    var body: some View {
        if let group {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Label", text: $draftText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onSubmit { commit(group: group) }
                        .onChange(of: draftText) { _, newValue in
                            // Cap at 2 grapheme clusters live.
                            if newValue.count > 2 {
                                draftText = String(newValue.prefix(2))
                            }
                        }

                    Picker("Position", selection: positionBinding(for: group)) {
                        Text("Leading").tag(BadgeLabelPosition.leading)
                        Text("Trailing").tag(BadgeLabelPosition.trailing)
                        Text("Above").tag(BadgeLabelPosition.above)
                        Text("Below").tag(BadgeLabelPosition.below)
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .disabled(group.badgeLabel == nil && draftText.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("Apply") {
                        commit(group: group)
                    }
                    .disabled(draftText == (group.badgeLabel?.text ?? ""))

                    Button("Clear") {
                        draftText = ""
                        store.updateGroupBadgeLabel(group.id, badgeLabel: nil)
                    }
                    .disabled(group.badgeLabel == nil)
                }

                Text("1–2 characters or a single emoji shown on the menu bar icon.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .onAppear {
                draftText = group.badgeLabel?.text ?? ""
            }
            .onChange(of: group.badgeLabel?.text ?? "") { _, newValue in
                draftText = newValue
            }
        }
    }

    private func commit(group: RepositoryGroup) {
        let trimmed = draftText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            store.updateGroupBadgeLabel(group.id, badgeLabel: nil)
        } else {
            let position = group.badgeLabel?.position ?? .leading
            store.updateGroupBadgeLabel(
                group.id,
                badgeLabel: BadgeLabel(text: String(trimmed.prefix(2)), position: position)
            )
        }
    }

    private func positionBinding(for group: RepositoryGroup) -> Binding<BadgeLabelPosition> {
        Binding {
            group.badgeLabel?.position ?? .leading
        } set: { newPosition in
            let trimmed = draftText.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            store.updateGroupBadgeLabel(
                group.id,
                badgeLabel: BadgeLabel(text: String(trimmed.prefix(2)), position: newPosition)
            )
        }
    }
}
