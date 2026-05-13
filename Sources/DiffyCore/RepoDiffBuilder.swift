import Foundation

public enum RepoDiffBuilder {
    public static func build(
        repository: RepositoryConfig,
        stagedStats: [String: FileLineStat],
        unstagedStats: [String: FileLineStat],
        statuses: [String: GitPathStatus],
        untrackedStats: [String: FileLineStat],
        refreshedAt: Date = Date()
    ) -> RepoDiffSummary {
        let stagedFiles = stagedStats.keys.sorted().map { path in
            makeFile(
                path: path,
                status: statuses[path]?.stagedStatus ?? .modified,
                stat: stagedStats[path] ?? FileLineStat(addedLines: 0, removedLines: 0, isBinary: false),
                section: .staged
            )
        }

        var unstagedPaths = Set(unstagedStats.keys)
        unstagedPaths.formUnion(untrackedStats.keys)

        let unstagedFiles = unstagedPaths.sorted().map { path in
            let status = statuses[path]?.unstagedStatus ?? (untrackedStats[path] == nil ? .modified : .untracked)
            let stat = unstagedStats[path] ?? untrackedStats[path] ?? FileLineStat(addedLines: 0, removedLines: 0, isBinary: false)
            return makeFile(path: path, status: status, stat: stat, section: .unstaged)
        }

        let added = stagedFiles.reduce(0) { $0 + $1.addedLines } + unstagedFiles.reduce(0) { $0 + $1.addedLines }
        let removed = stagedFiles.reduce(0) { $0 + $1.removedLines } + unstagedFiles.reduce(0) { $0 + $1.removedLines }

        return RepoDiffSummary(
            repository: repository,
            addedLines: added,
            removedLines: removed,
            stagedFiles: stagedFiles,
            unstagedFiles: unstagedFiles,
            refreshedAt: refreshedAt
        )
    }

    private static func makeFile(
        path: String,
        status: GitChangeStatus,
        stat: FileLineStat,
        section: DiffSection
    ) -> ChangedFileSummary {
        ChangedFileSummary(
            path: path,
            displayStatus: status.displayStatus,
            addedLines: stat.addedLines,
            removedLines: stat.removedLines,
            section: section,
            isBinary: stat.isBinary,
            isTooLarge: stat.isTooLarge
        )
    }
}
