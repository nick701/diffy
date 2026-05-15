import Foundation

/// Resolve a filesystem path to its canonical form via `realpath(3)`.
/// On macOS this crosses `/var → /private/var` and `/tmp → /private/tmp` symlinks
/// that `URL.resolvingSymlinksInPath()` leaves alone, so it's the safest way to
/// match a user-supplied path against `git worktree list --porcelain` output.
/// Falls back to the input on failure.
public func canonicalPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(validatingCString: resolved) ?? path
}

/// Resolve the actual git metadata directory for a linked worktree.
///
/// Linked worktrees have a regular file named `.git` whose contents are a single
/// line `gitdir: <absolute path>`. The pointed-at path lives inside the parent's
/// `.git/worktrees/<name>/` and is where `HEAD`, `index`, and refs actually live —
/// so FSEvents watchers must watch this resolved path, not the `.git` file itself.
///
/// Returns nil for main worktrees (where `.git` is a directory) or any read failure.
public func resolveLinkedWorktreeGitdir(at worktreePath: String) -> String? {
    let gitPath = URL(fileURLWithPath: worktreePath).appendingPathComponent(".git").path

    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDir), !isDir.boolValue else {
        return nil
    }

    guard let contents = try? String(contentsOfFile: gitPath, encoding: .utf8) else {
        return nil
    }

    for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("gitdir: ") else { continue }
        let value = String(trimmed.dropFirst("gitdir: ".count)).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { continue }
        return value
    }

    return nil
}
