import AppKit
import DiffyCore
import SwiftUI

struct RepositorySettingsView: View {
    @ObservedObject var store: DiffyStore
    let repositoryID: UUID
    let onClose: () -> Void

    @State private var customCommand = ""
    @State private var pendingWorktreeRemoval: UUID?
    @State private var showingRemoveConfirmation = false
    @FocusState private var isCustomCommandFocused: Bool

    private var repository: RepositoryConfig? {
        store.repositories.first { $0.id == repositoryID }
    }

    private var parentRepository: RepositoryConfig? {
        guard let repository, let parentID = repository.parentRepositoryID else { return nil }
        return store.repositories.first { $0.id == parentID }
    }

    var body: some View {
        if let repository {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(repository.displayName)
                                .font(.title3.weight(.semibold))
                            BranchSubtitle(branch: store.summaries[repository.id]?.branch)
                            Text(repository.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Close settings")
                        .accessibilityLabel("Close settings")
                    }

                    Divider()

                    settings(for: repository)
                }
                .padding(20)
            }
            .frame(width: 560, height: 390)
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
                if case .command(let command) = repository.editor {
                    customCommand = command
                }
            }
            .onDisappear {
                commitCustomCommand(for: repository)
            }
        } else {
            ContentUnavailableView("Repository unavailable", systemImage: "questionmark.folder")
                .frame(width: 400, height: 240)
        }
    }

    private func settings(for repository: RepositoryConfig) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Open in")
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .leading)
                Picker("", selection: editorBinding(for: repository)) {
                    ForEach(EditorChoice.allCases, id: \.self) { choice in
                        HStack(spacing: 6) {
                            Image(nsImage: choice.icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(choice.title)
                        }
                        .tag(choice)
                    }
                }
                .labelsHidden()
                .frame(width: 200)

                if editorChoice(for: repository) == .custom {
                    TextField("open {path}", text: $customCommand)
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
                Text("Supports {path} and {repo} placeholders.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !repository.isAutoManaged {
                HStack(spacing: 12) {
                    Text("Group")
                        .foregroundStyle(.secondary)
                        .frame(width: 96, alignment: .leading)
                    Picker("", selection: groupBinding(for: repository)) {
                        ForEach(store.groups) { group in
                            Text(group.name.isEmpty ? "Unnamed group" : group.name).tag(group.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)

                    Button("Move to New Group") {
                        let group = store.addGroup(name: repository.displayName)
                        store.moveRepository(repository.id, toGroup: group.id)
                    }
                }
            }

            HStack(spacing: 12) {
                Text("Recent commits")
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .leading)
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

            Toggle("Count toward group totals", isOn: inclusionBinding(for: repository))
                .toggleStyle(.switch)

            if repository.isAutoManaged {
                worktreeRemovalControls(for: repository)
            } else {
                Button("Remove Repository", role: .destructive) {
                    showingRemoveConfirmation = true
                }
                .confirmationDialog(
                    "Remove \"\(repository.displayName)\"?",
                    isPresented: $showingRemoveConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive) {
                        store.removeRepository(repository)
                        onClose()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes the repository from Diffy. Its files on disk are not affected.")
                }
            }
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
        return "This deletes the directory at \(child.path) and removes it from \(parentName). \(branchName) itself is preserved and can be checked out elsewhere."
    }

    private var worktreeRemovalDialogPresented: Binding<Bool> {
        Binding {
            pendingWorktreeRemoval != nil
        } set: { newValue in
            if !newValue { pendingWorktreeRemoval = nil }
        }
    }

    private func worktreeRemovalControls(for repository: RepositoryConfig) -> some View {
        let isMain = store.isGitMainWorktree(repositoryID: repository.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Remove worktree…", role: .destructive) {
                    pendingWorktreeRemoval = repository.id
                }
                .disabled(isMain)
                .help(isMain ? "Diffy can't remove this repository's main worktree." : "Remove this worktree from disk")

                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: repository.path)])
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            if let error = store.lastWorktreeRemovalError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
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

    private func recentCommitLimitBinding(for repository: RepositoryConfig) -> Binding<Int> {
        Binding {
            store.repositories.first(where: { $0.id == repository.id })?.recentCommitLimit
                ?? RepositoryConfig.defaultRecentCommitLimit
        } set: { newValue in
            store.updateRecentCommitLimit(for: repository.id, limit: newValue)
        }
    }

    private func inclusionBinding(for repository: RepositoryConfig) -> Binding<Bool> {
        Binding {
            !repository.isHidden
        } set: { isIncluded in
            store.setHidden(repository.id, isHidden: !isIncluded)
        }
    }
}

private enum EditorChoice: CaseIterable, Hashable {
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

    var title: String {
        switch self {
        case .systemDefault: "System Default"
        case .xcode: "Xcode"
        case .cursor: "Cursor"
        case .vsCode: "VS Code"
        case .zed: "Zed"
        case .custom: "Custom Command"
        }
    }

    var icon: NSImage {
        switch self {
        case .systemDefault:
            return systemIcon("macwindow")
        case .custom:
            return systemIcon("terminal")
        case .xcode:
            return bundledIcon(named: "Xcode", fallback: "hammer")
        case .cursor:
            return bundledIcon(named: "Cursor", fallback: "cursorarrow")
        case .vsCode:
            return bundledIcon(named: "Code", fallback: "chevron.left.forwardslash.chevron.right")
        case .zed:
            return bundledIcon(named: "Zed", fallback: "text.cursor")
        }
    }

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

    private func bundledIcon(named name: String, fallback: String) -> NSImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "icns", subdirectory: "EditorIcons"),
              let image = NSImage(contentsOf: url)
        else {
            return systemIcon(fallback)
        }
        return image
    }

    private func systemIcon(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }
}
