import Combine
import DiffyCore
import Foundation

enum GroupRemovalMode {
    case dissolveIntoStandalone
    case deleteRepos
}

@MainActor
final class DiffyStore: ObservableObject {
    @Published private(set) var groups: [RepositoryGroup] = []
    @Published private(set) var repositories: [RepositoryConfig] = []
    @Published private(set) var summaries: [UUID: RepoDiffSummary] = [:]
    /// Latest porcelain output keyed by parent (user-added) repo UUID. Transient — not persisted.
    /// Read by the UI via `isGitMainWorktree(repositoryID:)`.
    @Published private(set) var lastWorktreeEntries: [UUID: [WorktreeEntry]] = [:]
    @Published private(set) var lastAddError: String?
    @Published private(set) var lastWorktreeRemovalError: String?

    private let gitClient = GitClient()
    private let worktreeMutator = GitWorktreeMutator()
    private var watchers: [UUID: RepositoryWatcher] = [:]
    private var pollingTask: Task<Void, Never>?
    private let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let state = try? StoredStateMigration.decode(data) else { return }
        groups = state.groups
        repositories = state.repositories
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let state = StoredState(groups: groups, repositories: repositories)
            let data = try JSONEncoder().encode(state)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("Diffy failed to save repositories: \(error.localizedDescription)")
        }
    }

    func start() {
        sweepOrphanedAutoManagedRows()
        rebuildWatchers()
        refreshAll()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                self?.refreshAll()
            }
        }
    }

    /// Defensive cleanup for auto-managed rows whose parent isn't in `repositories`
    /// (hand-edited JSON, or a future bug in the cascade).
    private func sweepOrphanedAutoManagedRows() {
        let parentIDs = Set(repositories.filter { !$0.isAutoManaged }.map(\.id))
        let orphanIDs = repositories
            .filter { repo in
                guard repo.isAutoManaged, let pid = repo.parentRepositoryID else { return false }
                return !parentIDs.contains(pid)
            }
            .map(\.id)
        guard !orphanIDs.isEmpty else { return }
        for id in orphanIDs {
            tearDownRow(id: id)
        }
        save()
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        watchers.values.forEach { $0.stop() }
        watchers.removeAll()
    }

    // MARK: - Repositories

    func addRepository(path: String) {
        let url = URL(fileURLWithPath: path)
        let canonical = canonicalPath(url.path)

        if let existing = repositories.first(where: { canonicalPath($0.path) == canonical }) {
            if let parentID = existing.parentRepositoryID,
               let parent = repositories.first(where: { $0.id == parentID }) {
                lastAddError = "This path is already tracked as a worktree of \"\(parent.displayName)\"."
            } else {
                lastAddError = "This path is already tracked."
            }
            return
        }

        let group = RepositoryGroup(name: url.lastPathComponent)
        groups.append(group)

        let config = RepositoryConfig(
            displayName: url.lastPathComponent,
            path: url.path,
            groupID: group.id
        )
        repositories.append(config)
        lastAddError = nil
        save()
        seedRow(config)
    }

    func clearAddError() {
        lastAddError = nil
    }

    func removeRepository(_ repository: RepositoryConfig) {
        let cascadeIDs: [UUID] = [repository.id]
            + repositories.filter { $0.parentRepositoryID == repository.id }.map(\.id)
        for id in cascadeIDs {
            tearDownRow(id: id)
        }
        if repository.parentRepositoryID == nil {
            lastWorktreeEntries.removeValue(forKey: repository.id)
        }
        save()
    }

    func updateEditor(for repository: RepositoryConfig, editor: EditorPreference) {
        guard let index = repositories.firstIndex(where: { $0.id == repository.id }) else { return }
        repositories[index].editor = editor
        updateSummaryRepository(repositories[index])
        save()
    }

    func setHidden(_ repositoryID: UUID, isHidden: Bool) {
        guard let index = repositories.firstIndex(where: { $0.id == repositoryID }) else { return }
        guard repositories[index].isHidden != isHidden else { return }
        repositories[index].isHidden = isHidden
        updateSummaryRepository(repositories[index])
        save()
    }

    func moveRepository(_ repositoryID: UUID, toGroup groupID: UUID) {
        guard let index = repositories.firstIndex(where: { $0.id == repositoryID }) else { return }
        guard groups.contains(where: { $0.id == groupID }) else { return }
        guard repositories[index].groupID != groupID else { return }
        guard repositories[index].parentRepositoryID == nil else { return }

        repositories[index].groupID = groupID
        updateSummaryRepository(repositories[index])

        for childIndex in repositories.indices where repositories[childIndex].parentRepositoryID == repositoryID {
            repositories[childIndex].groupID = groupID
            updateSummaryRepository(repositories[childIndex])
        }

        save()
    }

    // MARK: - Groups

    @discardableResult
    func addGroup(name: String = "", diffColors: DiffColors = .default) -> RepositoryGroup {
        let group = RepositoryGroup(name: name, diffColors: diffColors)
        groups.append(group)
        save()
        return group
    }

    func renameGroup(_ groupID: UUID, to newName: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard groups[index].name != newName else { return }
        groups[index].name = newName
        save()
    }

    func updateGroupColors(_ groupID: UUID, diffColors: DiffColors) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard groups[index].diffColors != diffColors else { return }
        groups[index].diffColors = diffColors
        save()
    }

    func updateGroupBadgeLabel(_ groupID: UUID, badgeLabel: BadgeLabel?) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard groups[index].badgeLabel != badgeLabel else { return }
        groups[index].badgeLabel = badgeLabel
        save()
    }

    func setGroupHidden(_ groupID: UUID, isHidden: Bool) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard groups[index].isHidden != isHidden else { return }
        groups[index].isHidden = isHidden
        save()
    }

    func reorderGroups(_ orderedIDs: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        var reordered: [RepositoryGroup] = []
        reordered.reserveCapacity(groups.count)
        for id in orderedIDs {
            if let group = byID[id] {
                reordered.append(group)
            }
        }
        for group in groups where !orderedIDs.contains(group.id) {
            reordered.append(group)
        }
        guard reordered.count == groups.count else { return }
        groups = reordered
        save()
    }

    func removeGroup(_ groupID: UUID, mode: GroupRemovalMode) {
        let parents = repositories.filter { $0.groupID == groupID && $0.parentRepositoryID == nil }

        switch mode {
        case .dissolveIntoStandalone:
            for parent in parents {
                let newGroup = RepositoryGroup(name: parent.displayName)
                groups.append(newGroup)
                if let index = repositories.firstIndex(where: { $0.id == parent.id }) {
                    repositories[index].groupID = newGroup.id
                    updateSummaryRepository(repositories[index])
                }
                for childIndex in repositories.indices where repositories[childIndex].parentRepositoryID == parent.id {
                    repositories[childIndex].groupID = newGroup.id
                    updateSummaryRepository(repositories[childIndex])
                }
            }
        case .deleteRepos:
            // Two-pass to avoid mutating `repositories` while iterating it.
            var idsToRemove: [UUID] = []
            for parent in parents {
                idsToRemove.append(parent.id)
                idsToRemove.append(contentsOf: repositories.filter { $0.parentRepositoryID == parent.id }.map(\.id))
            }
            for id in idsToRemove {
                tearDownRow(id: id)
            }
            for parent in parents {
                lastWorktreeEntries.removeValue(forKey: parent.id)
            }
        }
        groups.removeAll { $0.id == groupID }
        save()
    }

    // MARK: - Worktree-specific public surface

    /// True when the auto-managed row is the git-main worktree of its repo family
    /// (which `git worktree remove` cannot remove). Detected from the first entry in
    /// the parent's most-recent porcelain output.
    func isGitMainWorktree(repositoryID: UUID) -> Bool {
        guard let repo = repositories.first(where: { $0.id == repositoryID }),
              let parentID = repo.parentRepositoryID,
              let entries = lastWorktreeEntries[parentID],
              let first = entries.first
        else { return false }
        return canonicalPath(first.path) == canonicalPath(repo.path)
    }

    /// Returns rows in a group with each parent immediately followed by its auto-managed children.
    /// When `includeHidden` is true, hidden parents (and their children) sink to the bottom.
    /// When false, hidden rows are filtered out.
    func orderedRepositories(in groupID: UUID, includeHidden: Bool) -> [RepositoryConfig] {
        let inGroup = repositories.filter { $0.groupID == groupID }
        let parents = inGroup.filter { $0.parentRepositoryID == nil }
        let orderedParents: [RepositoryConfig]
        if includeHidden {
            orderedParents = parents.filter { !$0.isHidden } + parents.filter { $0.isHidden }
        } else {
            orderedParents = parents.filter { !$0.isHidden }
        }

        var result: [RepositoryConfig] = []
        result.reserveCapacity(inGroup.count)
        for parent in orderedParents {
            result.append(parent)
            let children = repositories.filter { $0.parentRepositoryID == parent.id }
            result.append(contentsOf: includeHidden ? children : children.filter { !$0.isHidden })
        }
        return result
    }

    func clearWorktreeRemovalError() {
        lastWorktreeRemovalError = nil
    }

    func removeWorktree(repositoryID: UUID) {
        guard let child = repositories.first(where: { $0.id == repositoryID }) else { return }
        guard let parentID = child.parentRepositoryID,
              let parent = repositories.first(where: { $0.id == parentID }) else { return }

        let childPath = child.path
        let parentPath = parent.path
        let mutator = self.worktreeMutator

        Task.detached(priority: .userInitiated) {
            do {
                try mutator.remove(parentPath: parentPath, worktreePath: childPath)
                await MainActor.run {
                    self.lastWorktreeRemovalError = nil
                    // FSEvents on the parent's .git/worktrees/ will drive natural reconcile; trigger
                    // an immediate refresh too so the row drops without waiting on the debounce.
                    self.refresh(repositoryID: parentID)
                }
            } catch {
                await MainActor.run {
                    self.lastWorktreeRemovalError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Refresh plumbing

    func refreshAll() {
        repositories.forEach(refresh)
    }

    func refresh(repositoryID: UUID) {
        guard let repository = repositories.first(where: { $0.id == repositoryID }) else { return }
        refresh(repository)
    }

    private func refresh(_ repository: RepositoryConfig) {
        let isParentRefresh = (repository.parentRepositoryID == nil)
        let parentPath: String
        let parentID: UUID

        if let pid = repository.parentRepositoryID,
           let parent = repositories.first(where: { $0.id == pid }) {
            parentPath = parent.path
            parentID = parent.id
        } else {
            parentPath = repository.path
            parentID = repository.id
        }

        // Children that have a cached parent porcelain output skip their own porcelain call
        // (saves N+1 git subprocesses per parent refresh wave). Branch info may be up to one
        // refresh cycle stale, which is acceptable.
        let cachedBranch: BranchInfo?
        if !isParentRefresh, let cached = lastWorktreeEntries[parentID] {
            let canonicalSelf = canonicalPath(repository.path)
            cachedBranch = cached.first(where: { canonicalPath($0.path) == canonicalSelf })?.branch
        } else {
            cachedBranch = nil
        }
        let useCachedBranchOnly = !isParentRefresh && cachedBranch != nil

        Task.detached(priority: .utility) { [gitClient] in
            do {
                let branch: BranchInfo?
                var entries: [WorktreeEntry]? = nil

                if useCachedBranchOnly {
                    branch = cachedBranch
                } else {
                    let fetched = try gitClient.discoverWorktrees(parentPath: parentPath)
                    entries = fetched
                    let canonicalSelf = canonicalPath(repository.path)
                    branch = fetched.first(where: { canonicalPath($0.path) == canonicalSelf })?.branch
                }
                let summary = try gitClient.summarize(repository, branch: branch)

                await MainActor.run {
                    guard self.repositories.contains(where: { $0.id == repository.id }) else { return }
                    if self.summaries[repository.id] != summary {
                        self.summaries[repository.id] = summary
                    }
                    if isParentRefresh, let entries {
                        if self.lastWorktreeEntries[parentID] != entries {
                            self.lastWorktreeEntries[parentID] = entries
                        }
                        self.reconcileChildren(parentID: parentID, entries: entries)
                    }
                }
            } catch {
                let result = RepoDiffSummary.empty(for: repository).withError(error.localizedDescription)
                await MainActor.run {
                    guard self.repositories.contains(where: { $0.id == repository.id }) else { return }
                    if self.summaries[repository.id] != result {
                        self.summaries[repository.id] = result
                    }
                }
            }
        }
    }

    /// Add/remove auto-managed child rows so they mirror porcelain output. Skips prunable + bare
    /// entries, and skips the parent's own row.
    private func reconcileChildren(parentID: UUID, entries: [WorktreeEntry]) {
        guard let parent = repositories.first(where: { $0.id == parentID }) else { return }
        let canonicalParent = canonicalPath(parent.path)

        let expected: [(canonical: String, entry: WorktreeEntry)] = entries.compactMap { entry in
            if entry.isPrunable { return nil }
            if case .bare = entry.branch { return nil }
            let canonical = canonicalPath(entry.path)
            if canonical == canonicalParent { return nil }
            return (canonical, entry)
        }
        let expectedCanonicalSet = Set(expected.map(\.canonical))

        let currentChildren = repositories.filter { $0.parentRepositoryID == parentID }
        let currentByCanonical = Dictionary(
            uniqueKeysWithValues: currentChildren.map { (canonicalPath($0.path), $0) }
        )
        let currentCanonicalSet = Set(currentByCanonical.keys)

        var mutated = false

        let gone = currentCanonicalSet.subtracting(expectedCanonicalSet)
        if !gone.isEmpty {
            for canonical in gone {
                guard let child = currentByCanonical[canonical] else { continue }
                tearDownRow(id: child.id)
            }
            mutated = true
        }

        let toAdd = expected.filter { !currentCanonicalSet.contains($0.canonical) }
        for (_, entry) in toAdd {
            let displayName: String
            switch entry.branch {
            case .branch(let name): displayName = name
            default: displayName = URL(fileURLWithPath: entry.path).lastPathComponent
            }
            let child = RepositoryConfig(
                displayName: displayName,
                path: entry.path,
                groupID: parent.groupID,
                parentRepositoryID: parent.id,
                isAutoManaged: true
            )
            repositories.append(child)
            seedRow(child)
            mutated = true
        }

        if mutated {
            save()
        }
    }

    // MARK: - Row lifecycle helpers

    /// Install a freshly-created `RepositoryConfig` that's already in `repositories`:
    /// seed an empty summary, start a watcher, and trigger a first refresh.
    private func seedRow(_ config: RepositoryConfig) {
        summaries[config.id] = .empty(for: config)
        startWatcher(for: config)
        refresh(config)
    }

    /// Remove every trace of a row from `repositories`, `summaries`, and `watchers`.
    /// Idempotent — missing entries are no-ops.
    private func tearDownRow(id: UUID) {
        repositories.removeAll { $0.id == id }
        summaries.removeValue(forKey: id)
        watchers[id]?.stop()
        watchers.removeValue(forKey: id)
    }

    private func rebuildWatchers() {
        watchers.values.forEach { $0.stop() }
        watchers.removeAll()
        repositories.forEach(startWatcher)
    }

    private func startWatcher(for repository: RepositoryConfig) {
        let gitdir: String? = repository.parentRepositoryID == nil
            ? nil
            : resolveLinkedWorktreeGitdir(at: repository.path)

        let watcher = RepositoryWatcher(repositoryPath: repository.path, gitdirPath: gitdir) { [weak self] in
            Task { @MainActor in
                self?.refresh(repositoryID: repository.id)
            }
        }

        if watcher.start() {
            watchers[repository.id] = watcher
        }
    }

    private static func defaultStorageURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diffy", isDirectory: true)
            .appendingPathComponent("repositories.json")
    }

    private func updateSummaryRepository(_ repository: RepositoryConfig) {
        if var summary = summaries[repository.id] {
            summary.repository = repository
            summaries[repository.id] = summary
        }
    }
}

private extension RepoDiffSummary {
    func withError(_ message: String) -> RepoDiffSummary {
        var copy = self
        copy.errorMessage = message
        return copy
    }
}
