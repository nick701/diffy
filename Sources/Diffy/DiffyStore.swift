import Combine
import DiffyCore
import Foundation

@MainActor
final class DiffyStore: ObservableObject {
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
        repositories = (try? JSONDecoder().decode([RepositoryConfig].self, from: data)) ?? []
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(repositories)
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

    func addRepository(path: String) {
        let url = URL(fileURLWithPath: path)
        guard repositories.contains(where: { $0.path == url.path }) == false else { return }

        let config = RepositoryConfig(displayName: url.lastPathComponent, path: url.path)
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
        if var summary = summaries[repository.id] {
            summary.repository = repositories[index]
            summaries[repository.id] = summary
        }
        save()
    }

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
}

private extension RepoDiffSummary {
    func withError(_ message: String) -> RepoDiffSummary {
        var copy = self
        copy.errorMessage = message
        return copy
    }
}
