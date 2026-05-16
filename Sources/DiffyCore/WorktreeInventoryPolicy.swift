import Foundation

public struct WorktreeChildCandidate: Equatable, Sendable {
    public var canonicalPath: String
    public var entry: WorktreeEntry

    public init(canonicalPath: String, entry: WorktreeEntry) {
        self.canonicalPath = canonicalPath
        self.entry = entry
    }
}

public enum WorktreeInventoryPolicy {
    public static func familyOwnerID(repositories: [RepositoryConfig], entries: [WorktreeEntry]) -> UUID? {
        let worktreePaths = Set(entries.map { canonicalPath($0.path) })
        return repositories.first { repo in
            !repo.isAutoManaged && worktreePaths.contains(canonicalPath(repo.path))
        }?.id
    }

    public static func desiredAutoManagedChildren(
        parent: RepositoryConfig,
        repositories: [RepositoryConfig],
        entries: [WorktreeEntry]
    ) -> [WorktreeChildCandidate] {
        guard familyOwnerID(repositories: repositories, entries: entries) == parent.id else { return [] }

        let userManagedPaths = Set(
            repositories
                .filter { !$0.isAutoManaged }
                .map { canonicalPath($0.path) }
        )

        var seen = Set<String>()
        var result: [WorktreeChildCandidate] = []
        result.reserveCapacity(entries.count)

        for entry in entries {
            if entry.isPrunable { continue }
            if case .bare = entry.branch { continue }

            let canonical = canonicalPath(entry.path)
            if userManagedPaths.contains(canonical) { continue }
            guard seen.insert(canonical).inserted else { continue }

            result.append(WorktreeChildCandidate(canonicalPath: canonical, entry: entry))
        }

        return result
    }

    public static func duplicateRepositoryIDsToRemove(repositories: [RepositoryConfig]) -> [UUID] {
        var buckets: [String: [RepositoryConfig]] = [:]
        for repo in repositories {
            buckets[canonicalPath(repo.path), default: []].append(repo)
        }

        var remove = Set<UUID>()
        for bucket in buckets.values where bucket.count > 1 {
            let keep = bucket.first { !$0.isAutoManaged } ?? bucket[0]
            for repo in bucket where repo.id != keep.id {
                remove.insert(repo.id)
            }
        }

        return repositories.map(\.id).filter { remove.contains($0) }
    }
}
