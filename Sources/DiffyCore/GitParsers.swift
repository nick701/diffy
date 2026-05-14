import Foundation

public enum GitNumstatParser {
    /// Parses `git diff --numstat -z` output. Records are NUL-terminated;
    /// renames take the form `<added>\t<removed>\t\0<oldpath>\0<newpath>\0`,
    /// normal records take `<added>\t<removed>\t<path>\0`.
    public static func parse(_ output: String) -> [String: FileLineStat] {
        var stats: [String: FileLineStat] = [:]
        var index = output.startIndex
        let end = output.endIndex

        while index < end {
            guard let firstTab = output[index..<end].firstIndex(of: "\t") else { break }
            let added = String(output[index..<firstTab])
            index = output.index(after: firstTab)

            guard let secondTab = output[index..<end].firstIndex(of: "\t") else { break }
            let removed = String(output[index..<secondTab])
            index = output.index(after: secondTab)

            guard index < end else { break }
            let path: String
            if output[index] == "\u{0}" {
                index = output.index(after: index)
                guard let oldEnd = output[index..<end].firstIndex(of: "\u{0}") else { break }
                index = output.index(after: oldEnd)
                guard let newEnd = output[index..<end].firstIndex(of: "\u{0}") else { break }
                path = String(output[index..<newEnd])
                index = output.index(after: newEnd)
            } else {
                guard let pathEnd = output[index..<end].firstIndex(of: "\u{0}") else { break }
                path = String(output[index..<pathEnd])
                index = output.index(after: pathEnd)
            }

            let isBinary = added == "-" || removed == "-"
            let addedLines = Int(added) ?? 0
            let removedLines = Int(removed) ?? 0
            stats[path] = FileLineStat(addedLines: addedLines, removedLines: removedLines, isBinary: isBinary)
        }

        return stats
    }
}

public enum GitStatusParser {
    private static let conflictPairs: Set<String> = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]

    public static func parsePorcelainV1Z(_ output: String) -> [String: GitPathStatus] {
        var statuses: [String: GitPathStatus] = [:]
        let records = output.split(separator: "\u{0}", omittingEmptySubsequences: true).map(String.init)
        var index = 0

        while index < records.count {
            let record = records[index]
            guard record.count >= 4 else {
                index += 1
                continue
            }

            let x = record[record.startIndex]
            let y = record[record.index(after: record.startIndex)]
            let pair = String([x, y])
            let pathStart = record.index(record.startIndex, offsetBy: 3)
            let path = String(record[pathStart...])

            if pair == "??" {
                statuses[path] = GitPathStatus(stagedStatus: nil, unstagedStatus: .untracked)
            } else if conflictPairs.contains(pair) {
                statuses[path] = GitPathStatus(stagedStatus: .conflicted, unstagedStatus: .conflicted)
            } else {
                statuses[path] = GitPathStatus(stagedStatus: status(for: x), unstagedStatus: status(for: y))
            }

            if x == "R" || x == "C" {
                index += 1
            }
            index += 1
        }

        return statuses
    }

    private static func status(for character: Character) -> GitChangeStatus? {
        switch character {
        case "M": .modified
        case "A": .added
        case "D": .deleted
        case "R": .renamed
        case "C": .copied
        default: nil
        }
    }
}
