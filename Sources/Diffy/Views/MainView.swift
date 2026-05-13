import DiffyCore
import SwiftUI

struct MainView: View {
    @ObservedObject var store: DiffyStore
    @ObservedObject var launchAtLoginController: LaunchAtLoginController
    let updaterController: UpdaterController

    @State private var selectedRepoID: UUID?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if selectedRepoID == nil {
                selectedRepoID = store.repositories.first?.id
            }
            launchAtLoginController.refresh()
        }
        .onChange(of: store.repositories) { _, repositories in
            if !repositories.contains(where: { $0.id == selectedRepoID }) {
                selectedRepoID = repositories.first?.id
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedRepoID) {
                Section("Repositories") {
                    ForEach(store.repositories) { repository in
                        sidebarRow(for: repository)
                            .tag(repository.id)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    RepositoryPicker.addRepository(to: store)
                } label: {
                    Label("Add Repository", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)

                Toggle(isOn: launchAtLoginBinding) {
                    Text("Launch at Login")
                }
                .toggleStyle(.switch)

                if let error = launchAtLoginController.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                HStack {
                    Button("Check for Updates…") {
                        updaterController.checkForUpdates()
                    }
                    Spacer()
                    Text(Self.versionString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
    }

    private func sidebarRow(for repository: RepositoryConfig) -> some View {
        let summary = store.summaries[repository.id]
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(repository.displayName)
                    .lineLimit(1)
                Text(repository.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if let summary {
                HStack(spacing: 2) {
                    Text("+\(summary.addedLines)")
                        .foregroundStyle(AppColor.swiftUIColor(hex: repository.diffColors.additionHex))
                    Text("-\(summary.removedLines)")
                        .foregroundStyle(AppColor.swiftUIColor(hex: repository.diffColors.removalHex))
                }
                .font(.system(.caption2, design: .monospaced))
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if store.repositories.isEmpty {
            ContentUnavailableView {
                Label("No Repositories", systemImage: "folder.badge.plus")
            } description: {
                Text("Add a local git repository to start watching its diff stats.")
            } actions: {
                Button("Add Repository") {
                    RepositoryPicker.addRepository(to: store)
                }
            }
        } else if let id = selectedRepoID {
            RepoDetailView(store: store, repositoryID: id)
                .id(id)
        } else {
            ContentUnavailableView("Select a Repository", systemImage: "sidebar.left")
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            launchAtLoginController.isEnabled
        } set: { newValue in
            launchAtLoginController.setEnabled(newValue)
        }
    }

    private static let versionString: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }()
}
