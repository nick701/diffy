import DiffyCore
import SwiftUI

struct RepoPopoverView: View {
    @ObservedObject var store: DiffyStore
    let repositoryID: UUID

    private var repository: RepositoryConfig? {
        store.repositories.first { $0.id == repositoryID }
    }

    private var summary: RepoDiffSummary? {
        store.summaries[repositoryID]
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()

                if let repository, let summary {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let error = summary.errorMessage {
                                ErrorBanner(message: error)
                            }

                            FileSectionView(
                                title: "Staged",
                                files: summary.stagedFiles,
                                repository: repository,
                                diffColors: repository.diffColors
                            )
                            FileSectionView(
                                title: "Unstaged",
                                files: summary.unstagedFiles,
                                repository: repository,
                                diffColors: repository.diffColors
                            )

                            if summary.stagedFiles.isEmpty && summary.unstagedFiles.isEmpty && summary.errorMessage == nil {
                                EmptyStateView(message: "No local changes")
                            }
                        }
                        .padding(12)
                    }
                } else {
                    EmptyStateView(message: "Repository not found")
                        .padding()
                }
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(repository?.displayName ?? "Diffy")
                    .font(.headline)
                    .lineLimit(1)
                Text(repository?.path ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                store.refresh(repositoryID: repositoryID)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(12)
    }
}

private struct FileSectionView: View {
    let title: String
    let files: [ChangedFileSummary]
    let repository: RepositoryConfig
    let diffColors: DiffColors

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if files.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 1) {
                    ForEach(files) { file in
                        Button {
                            EditorLauncher.open(file: file, in: repository)
                        } label: {
                            FileRowView(file: file, diffColors: diffColors)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct FileRowView: View {
    let file: ChangedFileSummary
    let diffColors: DiffColors

    var body: some View {
        HStack(spacing: 10) {
            Text(file.path)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text(file.displayStatus)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            if file.isBinary {
                Text("binary")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
            } else if file.isTooLarge {
                Text("large")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
            } else {
                HStack(spacing: 4) {
                    Text("+\(file.addedLines)")
                        .foregroundStyle(AppColor.swiftUIColor(hex: diffColors.additionHex))
                    Text("/")
                        .foregroundStyle(.secondary)
                    Text("-\(file.removedLines)")
                        .foregroundStyle(AppColor.swiftUIColor(hex: diffColors.removalHex))
                }
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .frame(width: 72, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct EmptyStateView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}
