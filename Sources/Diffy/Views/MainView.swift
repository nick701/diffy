import DiffyCore
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @ObservedObject var store: DiffyStore
    @ObservedObject var launchAtLoginController: LaunchAtLoginController
    let updaterController: UpdaterController

    @State private var selectedRepoID: UUID?
    @State private var pendingGroupRemoval: UUID?

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

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(store.groups.enumerated()), id: \.element.id) { index, group in
                        GroupSectionView(
                            store: store,
                            group: group,
                            isFirst: index == 0,
                            isLast: index == store.groups.count - 1,
                            selectedRepoID: $selectedRepoID,
                            onRemoveRequested: { pendingGroupRemoval = group.id }
                        )
                    }

                    NewGroupDropTarget(store: store)

                    if store.groups.isEmpty {
                        Text("No groups yet. Add a repository to get started.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 10)
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
        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        .confirmationDialog(
            confirmationTitle,
            isPresented: groupRemovalDialogPresented,
            titleVisibility: .visible
        ) {
            Button("Dissolve into standalone groups") {
                if let id = pendingGroupRemoval {
                    store.removeGroup(id, mode: .dissolveIntoStandalone)
                }
                pendingGroupRemoval = nil
            }
            Button("Delete group and its repositories", role: .destructive) {
                if let id = pendingGroupRemoval {
                    store.removeGroup(id, mode: .deleteRepos)
                }
                pendingGroupRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                pendingGroupRemoval = nil
            }
        } message: {
            Text("This group contains repositories. Choose whether to keep them as standalone groups or delete them entirely.")
        }
    }

    private var confirmationTitle: String {
        guard let id = pendingGroupRemoval,
              let group = store.groups.first(where: { $0.id == id })
        else { return "Remove group" }
        let displayName = group.name.isEmpty ? "this group" : "\"\(group.name)\""
        return "Remove \(displayName)?"
    }

    private var groupRemovalDialogPresented: Binding<Bool> {
        Binding {
            pendingGroupRemoval != nil
        } set: { newValue in
            if !newValue { pendingGroupRemoval = nil }
        }
    }

    // MARK: - Detail

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

    // MARK: - Helpers

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

// MARK: - Group section

private struct GroupSectionView: View {
    @ObservedObject var store: DiffyStore
    let group: RepositoryGroup
    let isFirst: Bool
    let isLast: Bool
    @Binding var selectedRepoID: UUID?
    let onRemoveRequested: () -> Void

    @State private var showingColorEditor = false
    @State private var showingBadgeEditor = false
    @State private var isDropTargeted = false
    @State private var nameDraft: String = ""

    private var groupRepos: [RepositoryConfig] {
        store.repositories.filter { $0.groupID == group.id }
    }

    private var visibleRepos: [RepositoryConfig] {
        groupRepos.filter { !$0.isHidden }
    }

    private var hiddenRepos: [RepositoryConfig] {
        groupRepos.filter { $0.isHidden }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            VStack(spacing: 1) {
                ForEach(visibleRepos) { repository in
                    RepoSidebarRow(
                        store: store,
                        repository: repository,
                        groupColors: group.diffColors,
                        isSelected: selectedRepoID == repository.id,
                        onSelect: { selectedRepoID = repository.id }
                    )
                }
                ForEach(hiddenRepos) { repository in
                    RepoSidebarRow(
                        store: store,
                        repository: repository,
                        groupColors: group.diffColors,
                        isSelected: selectedRepoID == repository.id,
                        onSelect: { selectedRepoID = repository.id }
                    )
                    .opacity(0.45)
                }
                if groupRepos.isEmpty {
                    Text("Empty group — drop a repository here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .dropDestination(for: String.self) { items, _ in
                guard let raw = items.first, let repoID = UUID(uuidString: raw) else { return false }
                store.moveRepository(repoID, toGroup: group.id)
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
        }
        .padding(.horizontal, 10)
        .onAppear {
            nameDraft = group.name
        }
        .onChange(of: group.name) { _, newValue in
            if nameDraft != newValue {
                nameDraft = newValue
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            TextField("Group name", text: $nameDraft)
                .textFieldStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .onSubmit {
                    store.renameGroup(group.id, to: nameDraft)
                }

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                Button {
                    showingColorEditor.toggle()
                } label: {
                    Image(systemName: "paintpalette")
                }
                .buttonStyle(.borderless)
                .help("Edit group colors")
                .popover(isPresented: $showingColorEditor, arrowEdge: .bottom) {
                    GroupColorEditor(store: store, groupID: group.id)
                        .padding(12)
                }

                Button {
                    showingBadgeEditor.toggle()
                } label: {
                    Image(systemName: "tag")
                }
                .buttonStyle(.borderless)
                .help("Configure menu-bar label")
                .popover(isPresented: $showingBadgeEditor, arrowEdge: .bottom) {
                    GroupBadgeLabelEditor(store: store, groupID: group.id)
                        .padding(12)
                        .frame(width: 320)
                }

                Button {
                    moveGroupUp()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(isFirst)
                .help("Move group up")

                Button {
                    moveGroupDown()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(isLast)
                .help("Move group down")

                Button {
                    if groupRepos.isEmpty {
                        store.removeGroup(group.id, mode: .dissolveIntoStandalone)
                    } else {
                        onRemoveRequested()
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove group")
            }
        }
    }

    private func moveGroupUp() {
        guard let index = store.groups.firstIndex(where: { $0.id == group.id }), index > 0 else { return }
        var order = store.groups.map { $0.id }
        order.swapAt(index, index - 1)
        store.reorderGroups(order)
    }

    private func moveGroupDown() {
        guard let index = store.groups.firstIndex(where: { $0.id == group.id }),
              index < store.groups.count - 1
        else { return }
        var order = store.groups.map { $0.id }
        order.swapAt(index, index + 1)
        store.reorderGroups(order)
    }
}

// MARK: - Repo row

private struct RepoSidebarRow: View {
    @ObservedObject var store: DiffyStore
    let repository: RepositoryConfig
    let groupColors: DiffColors
    let isSelected: Bool
    let onSelect: () -> Void

    private var summary: RepoDiffSummary? {
        store.summaries[repository.id]
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                store.setHidden(repository.id, isHidden: !repository.isHidden)
            } label: {
                Image(systemName: repository.isHidden ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(repository.isHidden ? "Show in menu bar" : "Hide from menu bar")

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(repository.displayName)
                        .lineLimit(1)
                    Text(repository.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let summary {
                HStack(spacing: 2) {
                    Text("+\(summary.addedLines)")
                        .foregroundStyle(AppColor.swiftUIColor(hex: groupColors.additionHex))
                    Text("-\(summary.removedLines)")
                        .foregroundStyle(AppColor.swiftUIColor(hex: groupColors.removalHex))
                }
                .font(.system(.caption2, design: .monospaced))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .draggable(repository.id.uuidString) {
            // Drag preview.
            Text(repository.displayName)
                .padding(6)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - New-group drop target

private struct NewGroupDropTarget: View {
    @ObservedObject var store: DiffyStore
    @State private var isDropTargeted = false

    var body: some View {
        HStack {
            Image(systemName: "plus.rectangle.on.rectangle")
                .foregroundStyle(.secondary)
            Text("Drop repo here to create a new group")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("New Group") {
                _ = store.addGroup()
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [4])
                )
        )
        .padding(.horizontal, 10)
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let repoID = UUID(uuidString: raw) else { return false }
            let newGroup = store.addGroup()
            store.moveRepository(repoID, toGroup: newGroup.id)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }
}
