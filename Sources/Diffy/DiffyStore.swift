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

    private let gitClient = GitClient()
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
        rebuildWatchers()
        refreshAll()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                self?.refreshAll()
            }
        }
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
        guard repositories.contains(where: { $0.path == url.path }) == false else { return }

        let group = RepositoryGroup(name: url.lastPathComponent)
        groups.append(group)

        let config = RepositoryConfig(
            displayName: url.lastPathComponent,
            path: url.path,
            groupID: group.id
        )
        repositories.append(config)
        summaries[config.id] = .empty(for: config)
        save()
        startWatcher(for: config)
        refresh(config)
    }

    func removeRepository(_ repository: RepositoryConfig) {
        repositories.removeAll { $0.id == repository.id }
        summaries.removeValue(forKey: repository.id)
        watchers[repository.id]?.stop()
        watchers.removeValue(forKey: repository.id)
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
        repositories[index].groupID = groupID
        updateSummaryRepository(repositories[index])
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
        // Append any groups missing from the ordered list at the end (defensive).
        for group in groups where !orderedIDs.contains(group.id) {
            reordered.append(group)
        }
        guard reordered.count == groups.count else { return }
        groups = reordered
        save()
    }

    func removeGroup(_ groupID: UUID, mode: GroupRemovalMode) {
        let members = repositories.filter { $0.groupID == groupID }

        switch mode {
        case .dissolveIntoStandalone:
            for member in members {
                let newGroup = RepositoryGroup(name: member.displayName)
                groups.append(newGroup)
                if let index = repositories.firstIndex(where: { $0.id == member.id }) {
                    repositories[index].groupID = newGroup.id
                    updateSummaryRepository(repositories[index])
                }
            }
        case .deleteRepos:
            for member in members {
                repositories.removeAll { $0.id == member.id }
                summaries.removeValue(forKey: member.id)
                watchers[member.id]?.stop()
                watchers.removeValue(forKey: member.id)
            }
        }
        groups.removeAll { $0.id == groupID }
        save()
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
        Task.detached(priority: .utility) { [gitClient] in
            let result: RepoDiffSummary
            do {
                result = try gitClient.summarize(repository)
            } catch {
                result = RepoDiffSummary.empty(for: repository).withError(error.localizedDescription)
            }

            await MainActor.run {
                guard self.repositories.contains(where: { $0.id == repository.id }) else { return }
                self.summaries[repository.id] = result
            }
        }
    }

    private func rebuildWatchers() {
        watchers.values.forEach { $0.stop() }
        watchers.removeAll()
        repositories.forEach(startWatcher)
    }

    private func startWatcher(for repository: RepositoryConfig) {
        let watcher = RepositoryWatcher(repositoryPath: repository.path) { [weak self] in
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
