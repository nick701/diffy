import Foundation

public enum GitNumstatParser {
    public static func parse(_ output: String) -> [String: FileLineStat] {
        var stats: [String: FileLineStat] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }

            let path = String(parts[2])
            let isBinary = parts[0] == "-" || parts[1] == "-"
            let added = Int(parts[0]) ?? 0
            let removed = Int(parts[1]) ?? 0
            stats[path] = FileLineStat(addedLines: added, removedLines: removed, isBinary: isBinary)
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
