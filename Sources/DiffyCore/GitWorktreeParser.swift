import Foundation

/// One worktree as reported by `git worktree list --porcelain`.
public struct WorktreeEntry: Equatable, Sendable {
    public var path: String
    public var headSHA: String?
    public var branch: BranchInfo
    public var isLocked: Bool
    public var isPrunable: Bool

    public init(
        path: String,
        headSHA: String? = nil,
        branch: BranchInfo = .unknown,
        isLocked: Bool = false,
        isPrunable: Bool = false
    ) {
        self.path = path
        self.headSHA = headSHA
        self.branch = branch
        self.isLocked = isLocked
        self.isPrunable = isPrunable
    }
}

public enum GitWorktreeParser {
    /// Parses `git worktree list --porcelain` output. Records are separated by a blank line.
    /// Each record contains at least `worktree <abs path>`; optional lines include
    /// `HEAD <sha>`, `branch refs/heads/<name>`, `detached`, `bare`, `locked [<reason>]`,
    /// `prunable [<reason>]`. The `branch refs/heads/...` prefix is stripped.
    public static func parse(_ output: String) -> [WorktreeEntry] {
        var entries: [WorktreeEntry] = []
        var current: PartialEntry?

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.isEmpty {
                if let entry = current?.finalized() {
                    entries.append(entry)
                }
                current = nil
                continue
            }

            if line.hasPrefix("worktree ") {
                if let entry = current?.finalized() {
                    entries.append(entry)
                }
                current = PartialEntry(path: String(line.dropFirst("worktree ".count)))
                continue
            }

            guard current != nil else { continue }

            if line.hasPrefix("HEAD ") {
                current?.headSHA = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                let name = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
                current?.branchOverride = .branch(name)
            } else if line == "detached" {
                current?.isDetached = true
            } else if line == "bare" {
                current?.branchOverride = .bare
            } else if line == "locked" || line.hasPrefix("locked ") {
                current?.isLocked = true
            } else if line == "prunable" || line.hasPrefix("prunable ") {
                current?.isPrunable = true
            }
        }

        if let entry = current?.finalized() {
            entries.append(entry)
        }

        return entries
    }

    private struct PartialEntry {
        var path: String
        var headSHA: String?
        var branchOverride: BranchInfo?
        var isDetached: Bool = false
        var isLocked: Bool = false
        var isPrunable: Bool = false

        func finalized() -> WorktreeEntry? {
            guard !path.isEmpty else { return nil }
            let branch: BranchInfo
            if let override = branchOverride {
                branch = override
            } else if isDetached, let sha = headSHA, !sha.isEmpty {
                branch = .detached(shortSHA: String(sha.prefix(7)))
            } else if isDetached {
                branch = .unknown
            } else {
                branch = .unknown
            }
            return WorktreeEntry(
                path: path,
                headSHA: headSHA,
                branch: branch,
                isLocked: isLocked,
                isPrunable: isPrunable
            )
        }
    }
}
