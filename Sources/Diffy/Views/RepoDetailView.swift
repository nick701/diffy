import DiffyCore
import SwiftUI

struct RepoDetailView: View {
    @ObservedObject var store: DiffyStore
    let repositoryID: UUID
    @State private var customCommand: String = ""
    @State private var pendingWorktreeRemoval: UUID?
    @State private var showingRemoveConfirmation = false
    @FocusState private var isCustomCommandFocused: Bool

    private var repository: RepositoryConfig? {
        store.repositories.first { $0.id == repositoryID }
    }

    private var summary: RepoDiffSummary? {
        store.summaries[repositoryID]
    }

    private var group: RepositoryGroup? {
        guard let repository else { return nil }
        return store.groups.first { $0.id == repository.groupID }
    }

    private var parentRepository: RepositoryConfig? {
        guard let repository, let pid = repository.parentRepositoryID else { return nil }
        return store.repositories.first { $0.id == pid }
    }

    var body: some View {
        if let repository, let summary {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(repository: repository, summary: summary)

                    if let error = summary.errorMessage {
                        ErrorBanner(message: error)
                    }

                    FileSectionView(
                        title: "Staged",
                        files: summary.stagedFiles,
                        repository: repository,
                        diffColors: group?.diffColors ?? .default
                    )
                    FileSectionView(
                        title: "Unstaged",
                        files: summary.unstagedFiles,
                        repository: repository,
                        diffColors: group?.diffColors ?? .default
                    )

                    if summary.stagedFiles.isEmpty && summary.unstagedFiles.isEmpty && summary.errorMessage == nil {
                        Text("No local changes")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }

                    Divider().padding(.top, 4)
                    settingsSection(for: repository)
                }
                .padding(20)
            }
            .confirmationDialog(
                worktreeRemovalTitle,
                isPresented: worktreeRemovalDialogPresented,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let id = pendingWorktreeRemoval {
                        store.clearWorktreeRemovalError()
                        store.removeWorktree(repositoryID: id)
                    }
                    pendingWorktreeRemoval = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingWorktreeRemoval = nil
                }
            } message: {
                Text(worktreeRemovalMessage)
            }
            .onAppear {
                store.clearWorktreeRemovalError()
            }
        } else {
            ContentUnavailableView("Repository unavailable", systemImage: "questionmark.folder")
        }
    }

    private var worktreeRemovalTitle: String { "Remove worktree?" }

    private var worktreeRemovalMessage: String {
        guard let id = pendingWorktreeRemoval,
              let child = store.repositories.first(where: { $0.id == id })
        else { return "" }
        let parentName = parentRepository?.displayName ?? "its repository"
        let branchName: String
        switch store.summaries[id]?.branch {
        case .some(.branch(let name)): branchName = "branch `\(name)`"
        case .some(.detached(let sha)): branchName = "detached HEAD at `\(sha)`"
        default: branchName = "its checked-out commit"
        }
        return "This will delete the directory at \(child.path) and remove it from \(parentName). \(branchName) itself is preserved and can be checked out elsewhere."
    }

    private var worktreeRemovalDialogPresented: Binding<Bool> {
        Binding {
            pendingWorktreeRemoval != nil
        } set: { newValue in
            if !newValue { pendingWorktreeRemoval = nil }
        }
    }

    private func header(repository: RepositoryConfig, summary: RepoDiffSummary) -> some View {
        let colors = group?.diffColors ?? .default
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(repository.displayName)
                    .font(.title2.weight(.semibold))
                BranchSubtitle(branch: summary.branch)
                Text(repository.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            HStack(spacing: 6) {
                Text("+\(summary.addedLines)")
                    .foregroundStyle(AppColor.swiftUIColor(hex: colors.additionHex))
                Text("/")
                    .foregroundStyle(.secondary)
                Text("-\(summary.removedLines)")
                    .foregroundStyle(AppColor.swiftUIColor(hex: colors.removalHex))
            }
            .font(.system(.title3, design: .monospaced).weight(.medium))

            Button {
                store.refresh(repositoryID: repositoryID)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
    }

    @ViewBuilder
    private func settingsSection(for repository: RepositoryConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Open in")
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    Picker("", selection: editorBinding(for: repository)) {
                        Text("System Default").tag(EditorChoice.systemDefault)
                        Text("Xcode").tag(EditorChoice.xcode)
                        Text("Cursor").tag(EditorChoice.cursor)
                        Text("VS Code").tag(EditorChoice.vsCode)
                        Text("Zed").tag(EditorChoice.zed)
                        Text("Custom Command").tag(EditorChoice.custom)
                    }
                    .labelsHidden()
                    .frame(width: 200)

                    if editorChoice(for: repository) == .custom {
                        TextField("open -a Cursor {path}", text: $customCommand)
                            .textFieldStyle(.roundedBorder)
                            .focused($isCustomCommandFocused)
                            .onSubmit {
                                commitCustomCommand(for: repository)
                            }
                            .onChange(of: isCustomCommandFocused) { _, focused in
                                if !focused {
                                    commitCustomCommand(for: repository)
                                }
                            }
                    }
                }
                if editorChoice(for: repository) == .custom {
                    Text("Supports {path} and {repo} placeholders")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !repository.isAutoManaged {
                HStack(spacing: 12) {
                    Text("Group")
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    Picker("", selection: groupBinding(for: repository)) {
                        ForEach(store.groups) { g in
                            Text(g.name.isEmpty ? "Unnamed group" : g.name).tag(g.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)

                    Button("Move to New Group") {
                        let g = store.addGroup(name: repository.displayName)
                        store.moveRepository(repository.id, toGroup: g.id)
                    }
                }
            }

            HStack(spacing: 12) {
                Text("Recent commits")
                    .foregroundStyle(.secondary)
                    .frame(width: 104, alignment: .leading)
                Stepper(
                    value: recentCommitLimitBinding(for: repository),
                    in: RepositoryConfig.recentCommitLimitRange
                ) {
                    Text("\(repository.recentCommitLimit)")
                        .monospacedDigit()
                        .frame(width: 24, alignment: .trailing)
                }
                .fixedSize()
            }

            Toggle("Count toward group totals", isOn: includedBinding(for: repository))
                .toggleStyle(.switch)

            if repository.isAutoManaged {
                worktreeRemovalControls(for: repository)
            } else {
                Button(role: .destructive) {
                    showingRemoveConfirmation = true
                } label: {
                    Label("Remove Repository", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Remove \"\(repository.displayName)\"?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                store.removeRepository(repository)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the repository from Diffy. The files on disk are not affected.")
        }
        .onAppear {
            if case .command(let command) = repository.editor {
                customCommand = command
            }
        }
        .onDisappear {
            commitCustomCommand(for: repository)
        }
    }

    private func recentCommitLimitBinding(for repository: RepositoryConfig) -> Binding<Int> {
        Binding {
            store.repositories.first(where: { $0.id == repository.id })?.recentCommitLimit
                ?? RepositoryConfig.defaultRecentCommitLimit
        } set: { newValue in
            store.updateRecentCommitLimit(for: repository.id, limit: newValue)
        }
    }

    @ViewBuilder
    private func worktreeRemovalControls(for repository: RepositoryConfig) -> some View {
        let isMain = store.isGitMainWorktree(repositoryID: repository.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(role: .destructive) {
                    pendingWorktreeRemoval = repository.id
                } label: {
                    Label("Remove worktree…", systemImage: "trash")
                }
                .disabled(isMain)
                .help(isMain ? "Diffy can't remove this repo's main worktree." : "Remove this worktree from disk")

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: repository.path)])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            if let removalError = store.lastWorktreeRemovalError {
                ErrorBanner(message: removalError)
            }
        }
    }

    private func editorChoice(for repository: RepositoryConfig) -> EditorChoice {
        EditorChoice(editor: repository.editor)
    }

    private func commitCustomCommand(for repository: RepositoryConfig) {
        guard editorChoice(for: repository) == .custom else { return }
        store.updateEditor(for: repository, editor: .command(customCommand))
    }

    private func editorBinding(for repository: RepositoryConfig) -> Binding<EditorChoice> {
        Binding {
            editorChoice(for: repository)
        } set: { choice in
            if choice == .custom {
                let command = customCommand.isEmpty ? EditorChoice.defaultCustomCommand : customCommand
                customCommand = command
                store.updateEditor(for: repository, editor: .command(command))
            } else {
                store.updateEditor(for: repository, editor: choice.editor)
            }
        }
    }

    private func groupBinding(for repository: RepositoryConfig) -> Binding<UUID> {
        Binding {
            repository.groupID
        } set: { newGroupID in
            store.moveRepository(repository.id, toGroup: newGroupID)
        }
    }

    private func includedBinding(for repository: RepositoryConfig) -> Binding<Bool> {
        Binding {
            !repository.isHidden
        } set: { newValue in
            store.setHidden(repository.id, isHidden: !newValue)
        }
    }
}

private struct FileSectionView: View {
    let title: String
    let files: [ChangedFileSummary]
    let repository: RepositoryConfig
    let diffColors: DiffColors

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 0.5)
            }

            if files.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 1) {
                    ForEach(files) { file in
                        Button {
                            EditorLauncher.open(file: file, in: repository)
                        } label: {
                            FileRowView(file: file, diffColors: diffColors)
                        }
                        .buttonStyle(.plain)
                        .disabled(!file.isOpenableFromWorkingTree)
                        .help(file.isOpenableFromWorkingTree ? "Open file" : "Deleted files cannot be opened from the working tree.")
                    }
                }
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct FileRowView: View {
    let file: ChangedFileSummary
    let diffColors: DiffColors

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(file.path)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text(file.displayStatus)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            if file.isBinary {
                Text("binary")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
            } else if file.isTooLarge {
                Text("large")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
            } else {
                HStack(spacing: 4) {
                    Text("+\(file.addedLines)")
                        .foregroundStyle(AppColor.swiftUIColor(hex: diffColors.additionHex))
                    Text("/")
                        .foregroundStyle(.secondary)
                    Text("-\(file.removedLines)")
                        .foregroundStyle(AppColor.swiftUIColor(hex: diffColors.removalHex))
                }
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .frame(width: 72, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color.primary.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private enum EditorChoice: Hashable {
    case systemDefault
    case xcode
    case cursor
    case vsCode
    case zed
    case custom

    private static let xcodeBundleID = "com.apple.dt.Xcode"
    private static let cursorBundleID = "com.todesktop.230313mzl4w4u92"
    private static let vsCodeBundleID = "com.microsoft.VSCode"
    private static let zedBundleID = "dev.zed.Zed"
    static let defaultCustomCommand = "open {path}"

    init(editor: EditorPreference) {
        switch editor {
        case .systemDefault:
            self = .systemDefault
        case .appBundleIdentifier(Self.xcodeBundleID):
            self = .xcode
        case .appBundleIdentifier(Self.cursorBundleID):
            self = .cursor
        case .appBundleIdentifier(Self.vsCodeBundleID):
            self = .vsCode
        case .appBundleIdentifier(Self.zedBundleID):
            self = .zed
        case .appBundleIdentifier:
            self = .systemDefault
        case .command:
            self = .custom
        }
    }

    var editor: EditorPreference {
        switch self {
        case .systemDefault: .systemDefault
        case .xcode: .appBundleIdentifier(Self.xcodeBundleID)
        case .cursor: .appBundleIdentifier(Self.cursorBundleID)
        case .vsCode: .appBundleIdentifier(Self.vsCodeBundleID)
        case .zed: .appBundleIdentifier(Self.zedBundleID)
        case .custom: .command(Self.defaultCustomCommand)
        }
    }
}
