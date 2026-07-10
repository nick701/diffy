import AppKit
import DiffyCore
import SwiftUI

struct PopoverContentView: View {
    @ObservedObject var store: DiffyStore
    let groupID: UUID
    let onOpenWindow: () -> Void

    @State private var contentHeight: CGFloat = 0
    @State private var copyConfirmationID: UUID?
    private let bodyCap: CGFloat = 520

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 420)
        .task(id: copyConfirmationID) {
            guard let copyConfirmationID else { return }

            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, self.copyConfirmationID == copyConfirmationID else { return }
            self.copyConfirmationID = nil
        }
    }

    private var group: RepositoryGroup? {
        store.groups.first { $0.id == groupID }
    }

    private var groupRepos: [RepositoryConfig] {
        store.repositories.filter { $0.groupID == groupID && !$0.isHidden }
    }

    private var orderedGroupRepos: [RepositoryConfig] {
        store.orderedRepositories(in: groupID, includeHidden: false)
    }

    private var headerColors: DiffColors {
        group?.diffColors ?? .default
    }

    private var headerTitle: String {
        if let group, !group.name.isEmpty {
            return group.name
        }
        return "Diffy"
    }

    private var header: some View {
        let totals = aggregateTotals
        return HStack(alignment: .firstTextBaseline) {
            Text(headerTitle)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            HStack(spacing: 4) {
                Text("+\(totals.added)")
                    .foregroundStyle(AppColor.swiftUIColor(hex: headerColors.additionHex))
                Text("/")
                    .foregroundStyle(.secondary)
                Text("-\(totals.removed)")
                    .foregroundStyle(AppColor.swiftUIColor(hex: headerColors.removalHex))
            }
            .font(.system(.callout, design: .monospaced).weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if group == nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Group not found")
                    .font(.subheadline.weight(.semibold))
                Text("This menu-bar item is no longer associated with a group.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(14)
        } else if groupRepos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No visible repositories")
                    .font(.subheadline.weight(.semibold))
                Text("Add a repository or unhide one of this group's repositories from the main window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(14)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(orderedGroupRepos) { repository in
                        RepoBlock(
                            store: store,
                            repository: repository,
                            groupColors: headerColors,
                            onCopyPath: copyPath
                        )
                            .padding(.leading, repository.parentRepositoryID == nil ? 0 : 16)
                    }
                }
                .padding(14)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    contentHeight = newHeight
                }
            }
            .frame(height: contentHeight == 0 ? nil : min(contentHeight, bodyCap))
        }
    }

    private var footer: some View {
        HStack {
            Button {
                RepositoryPicker.addRepository(to: store)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add Repository")

            Spacer()

            if copyConfirmationID != nil {
                Text("Path copied")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            } else if let lastRefreshed {
                Text(lastRefreshed, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Button("See all groups") {
                onOpenWindow()
            }
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var lastRefreshed: Date? {
        groupRepos.compactMap { store.summaries[$0.id]?.refreshedAt }.max()
    }

    private var aggregateTotals: (added: Int, removed: Int) {
        var added = 0
        var removed = 0
        for repository in groupRepos {
            if let summary = store.summaries[repository.id] {
                added += summary.addedLines
                removed += summary.removedLines
            }
        }
        return (added, removed)
    }

    private func copyPath(_ file: ChangedFileSummary, in repository: RepositoryConfig) {
        let path = URL(fileURLWithPath: repository.path).appendingPathComponent(file.path).path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        copyConfirmationID = UUID()
    }
}

private struct RepoBlock: View {
    @ObservedObject var store: DiffyStore
    let repository: RepositoryConfig
    let groupColors: DiffColors
    let onCopyPath: (ChangedFileSummary, RepositoryConfig) -> Void

    private var summary: RepoDiffSummary? {
        store.summaries[repository.id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(repository.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    BranchSubtitle(branch: summary?.branch)
                }
                Spacer(minLength: 8)
                if let summary {
                    HStack(spacing: 2) {
                        Text("+\(summary.addedLines)")
                            .foregroundStyle(AppColor.swiftUIColor(hex: groupColors.additionHex))
                        Text("-\(summary.removedLines)")
                            .foregroundStyle(AppColor.swiftUIColor(hex: groupColors.removalHex))
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            }

            if let summary {
                if let error = summary.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                section(title: "Staged", files: summary.stagedFiles)
                section(title: "Unstaged", files: summary.unstagedFiles)
                if summary.stagedFiles.isEmpty && summary.unstagedFiles.isEmpty && summary.errorMessage == nil {
                    Text("No local changes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func section(title: String, files: [ChangedFileSummary]) -> some View {
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(height: 0.5)
                }
                VStack(spacing: 0) {
                    ForEach(files) { file in
                        ZStack {
                            Button {
                                EditorLauncher.open(file: file, in: repository)
                            } label: {
                                CompactFileRow(file: file, diffColors: groupColors)
                            }
                            .buttonStyle(.plain)
                            .disabled(!file.isOpenableFromWorkingTree)
                            .help(file.isOpenableFromWorkingTree ? "Open file" : "Deleted files cannot be opened from the working tree.")
                        }
                        .contextMenu {
                            Button("Copy Full Path") {
                                onCopyPath(file, repository)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct CompactFileRow: View {
    let file: ChangedFileSummary
    let diffColors: DiffColors

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(file.displayStatus)
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .leading)

            Text(file.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            if file.isBinary {
                Text("binary")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if file.isTooLarge {
                Text("large")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 3) {
                    Text("+\(file.addedLines)")
                        .foregroundStyle(AppColor.swiftUIColor(hex: diffColors.additionHex))
                    Text("-\(file.removedLines)")
                        .foregroundStyle(AppColor.swiftUIColor(hex: diffColors.removalHex))
                }
                .font(.system(.caption2, design: .monospaced))
            }
        }
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isHovering ? Color.primary.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
