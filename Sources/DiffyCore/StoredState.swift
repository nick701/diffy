import Foundation

public struct StoredState: Codable, Sendable {
    public var groups: [RepositoryGroup]
    public var repositories: [RepositoryConfig]

    public init(groups: [RepositoryGroup], repositories: [RepositoryConfig]) {
        self.groups = groups
        self.repositories = repositories
    }
}

public enum StoredStateMigration {
    /// A pre-groups `RepositoryConfig` record. Carries the legacy `diffColors` field
    /// and tolerates the absence of `groupID` / `isHidden`.
    private struct LegacyRepositoryConfig: Decodable {
        let id: UUID
        let displayName: String
        let path: String
        let editor: EditorPreference?
        let diffColors: DiffColors?
    }

    /// Decode the on-disk repositories file, preferring the current envelope shape
    /// and falling back to the legacy `[RepositoryConfig]` array on first decode failure.
    public static func decode(_ data: Data) throws -> StoredState {
        if let envelope = try? JSONDecoder().decode(StoredState.self, from: data) {
            return envelope
        }

        let legacy = try JSONDecoder().decode([LegacyRepositoryConfig].self, from: data)
        return migrate(legacy: legacy)
    }

    private static func migrate(legacy: [LegacyRepositoryConfig]) -> StoredState {
        var groups: [RepositoryGroup] = []
        var repositories: [RepositoryConfig] = []
        groups.reserveCapacity(legacy.count)
        repositories.reserveCapacity(legacy.count)

        for old in legacy {
            let group = RepositoryGroup(
                name: old.displayName,
                diffColors: old.diffColors ?? .default
            )
            groups.append(group)
            repositories.append(
                RepositoryConfig(
                    id: old.id,
                    displayName: old.displayName,
                    path: old.path,
                    editor: old.editor ?? .systemDefault,
                    groupID: group.id,
                    isHidden: false
                )
            )
        }

        return StoredState(groups: groups, repositories: repositories)
    }
}
