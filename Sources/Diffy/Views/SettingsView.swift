import DiffyCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: DiffyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repositories")
                        .font(.title2.weight(.semibold))
                    Text("Diffy watches local working trees and never writes to them.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    RepositoryPicker.addRepository(to: store)
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }

            if store.repositories.isEmpty {
                ContentUnavailableView("No Repositories", systemImage: "folder.badge.plus", description: Text("Add a local git repository to create its menu bar badge."))
            } else {
                List {
                    ForEach(store.repositories) { repository in
                        RepositorySettingsRow(store: store, repository: repository)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(width: 640, height: 420)
    }
}

private struct RepositorySettingsRow: View {
    @ObservedObject var store: DiffyStore
    let repository: RepositoryConfig
    @State private var customCommand = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(repository.displayName)
                        .font(.headline)
                    Text(repository.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button(role: .destructive) {
                    store.removeRepository(repository)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove repository")
            }

            HStack {
                Text("Open in")
                    .foregroundStyle(.secondary)

                Picker("", selection: editorBinding) {
                    Text("System Default").tag(EditorChoice.systemDefault)
                    Text("Xcode").tag(EditorChoice.xcode)
                    Text("Cursor").tag(EditorChoice.cursor)
                    Text("VS Code").tag(EditorChoice.vsCode)
                    Text("Zed").tag(EditorChoice.zed)
                    Text("Custom Command").tag(EditorChoice.custom)
                }
                .labelsHidden()
                .frame(width: 180)

                if editorChoice == .custom {
                    TextField("open -a Cursor {path}", text: $customCommand)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            store.updateEditor(for: repository, editor: .command(customCommand))
                        }
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            if case .command(let command) = repository.editor {
                customCommand = command
            }
        }
    }

    private var editorChoice: EditorChoice {
        EditorChoice(editor: repository.editor)
    }

    private var editorBinding: Binding<EditorChoice> {
        Binding {
            editorChoice
        } set: { choice in
            if choice == .custom {
                let command = customCommand.isEmpty ? "open {path}" : customCommand
                customCommand = command
                store.updateEditor(for: repository, editor: .command(command))
            } else {
                store.updateEditor(for: repository, editor: choice.editor)
            }
        }
    }
}

private enum EditorChoice: Hashable {
    case systemDefault
    case xcode
    case cursor
    case vsCode
    case zed
    case custom

    init(editor: EditorPreference) {
        switch editor {
        case .systemDefault:
            self = .systemDefault
        case .appBundleIdentifier("com.apple.dt.Xcode"):
            self = .xcode
        case .appBundleIdentifier("com.todesktop.230313mzl4w4u92"):
            self = .cursor
        case .appBundleIdentifier("com.microsoft.VSCode"):
            self = .vsCode
        case .appBundleIdentifier("dev.zed.Zed"):
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
        case .xcode: .appBundleIdentifier("com.apple.dt.Xcode")
        case .cursor: .appBundleIdentifier("com.todesktop.230313mzl4w4u92")
        case .vsCode: .appBundleIdentifier("com.microsoft.VSCode")
        case .zed: .appBundleIdentifier("dev.zed.Zed")
        case .custom: .command("open {path}")
        }
    }
}
