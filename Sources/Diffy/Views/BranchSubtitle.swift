import DiffyCore
import SwiftUI

/// A small one-line label showing the current branch (or detached SHA, or "bare").
/// Renders nothing for `.unknown` or `nil` so callers can drop it in unconditionally.
struct BranchSubtitle: View {
    let branch: BranchInfo?

    var body: some View {
        switch branch {
        case .some(.branch(let name)):
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.branch")
                Text(name)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        case .some(.detached(let sha)):
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.branch")
                Text(sha).italic()
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        case .some(.bare):
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.branch")
                Text("(bare)").italic()
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        case .some(.unknown), .none:
            EmptyView()
        }
    }
}
