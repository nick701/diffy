import Foundation

public enum GitClientError: Error, LocalizedError, Sendable {
    case commandFailed(String)
    case invalidRepository(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message): message
        case .invalidRepository(let path): "Not a readable git repository: \(path)"
        }
    }
}

public protocol GitProcessRunning: Sendable {
    func run(_ command: GitCommand) throws -> String
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    func snapshot() -> Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}

public struct GitProcessRunner: GitProcessRunning, Sendable {
    public init() {}

    public func run(_ command: GitCommand) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { _, new in new }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputData = DataBox()
        let errorData = DataBox()
        let group = DispatchGroup()

        func attach(_ handle: FileHandle, into sink: @escaping @Sendable (Data) -> Void) {
            group.enter()
            handle.readabilityHandler = { fh in
                let chunk = fh.availableData
                if chunk.isEmpty {
                    fh.readabilityHandler = nil
                    group.leave()
                } else {
                    sink(chunk)
                }
            }
        }

        attach(outputPipe.fileHandleForReading) { chunk in
            outputData.append(chunk)
        }
        attach(errorPipe.fileHandleForReading) { chunk in
            errorData.append(chunk)
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            group.leave(); group.leave()
            throw error
        }

        process.waitUntilExit()
        group.wait()

        let output = String(data: outputData.snapshot(), encoding: .utf8) ?? ""
        let error = String(data: errorData.snapshot(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw GitClientError.commandFailed(error.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }
}

public struct GitClient: @unchecked Sendable {
    private let runner: GitProcessRunning
    private let fileManager: FileManager
    private let maxUntrackedBytes: UInt64

    public init(
        runner: GitProcessRunning = GitProcessRunner(),
        fileManager: FileManager = .default,
        maxUntrackedBytes: UInt64 = 1_000_000
    ) {
        self.runner = runner
        self.fileManager = fileManager
        self.maxUntrackedBytes = maxUntrackedBytes
    }

    public func summarize(_ repository: RepositoryConfig, branch: BranchInfo? = nil) throws -> RepoDiffSummary {
        guard fileManager.fileExists(atPath: repository.path) else {
            throw GitClientError.invalidRepository(repository.path)
        }

        let staged = try runner.run(GitCommandFactory.command(for: .stagedNumstat, repositoryPath: repository.path))
        let unstaged = try runner.run(GitCommandFactory.command(for: .unstagedNumstat, repositoryPath: repository.path))
        let status = try runner.run(GitCommandFactory.command(for: .porcelainStatus, repositoryPath: repository.path))

        let statuses = GitStatusParser.parsePorcelainV1Z(status)
        let untrackedStats = statuses
            .filter { $0.value.unstagedStatus == .untracked }
            .reduce(into: [String: FileLineStat]()) { result, entry in
                result[entry.key] = statForUntrackedFile(repositoryPath: repository.path, relativePath: entry.key)
            }

        return RepoDiffBuilder.build(
            repository: repository,
            stagedStats: GitNumstatParser.parse(staged),
            unstagedStats: GitNumstatParser.parse(unstaged),
            statuses: statuses,
            untrackedStats: untrackedStats,
            branch: branch
        )
    }

    /// Run `git worktree list --porcelain` from `parentPath` and parse the output.
    public func discoverWorktrees(parentPath: String) throws -> [WorktreeEntry] {
        guard fileManager.fileExists(atPath: parentPath) else {
            throw GitClientError.invalidRepository(parentPath)
        }
        let output = try runner.run(GitCommandFactory.command(for: .worktreeListPorcelain, repositoryPath: parentPath))
        return GitWorktreeParser.parse(output)
    }

    private func statForUntrackedFile(repositoryPath: String, relativePath: String) -> FileLineStat {
        let url = URL(fileURLWithPath: repositoryPath).appendingPathComponent(relativePath)

        guard
            let attributes = try? fileManager.attributesOfItem(atPath: url.path),
            let type = attributes[.type] as? FileAttributeType,
            type == .typeRegular
        else {
            return FileLineStat(addedLines: 0, removedLines: 0, isBinary: true)
        }

        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard fileSize <= maxUntrackedBytes else {
            return FileLineStat(addedLines: 0, removedLines: 0, isBinary: false, isTooLarge: true)
        }

        guard let data = try? Data(contentsOf: url) else {
            return FileLineStat(addedLines: 0, removedLines: 0, isBinary: true)
        }

        if data.contains(0) {
            return FileLineStat(addedLines: 0, removedLines: 0, isBinary: true)
        }

        let lineCount = countLines(in: data)
        return FileLineStat(addedLines: lineCount, removedLines: 0, isBinary: false)
    }

    private func countLines(in data: Data) -> Int {
        guard !data.isEmpty else { return 0 }
        let newline = UInt8(ascii: "\n")
        let newlineCount = data.reduce(0) { $0 + ($1 == newline ? 1 : 0) }
        return data.last == newline ? newlineCount : newlineCount + 1
    }
}
