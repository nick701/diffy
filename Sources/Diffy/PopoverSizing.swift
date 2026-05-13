import AppKit
import DiffyCore

enum PopoverSizing {
    static func size(for summary: RepoDiffSummary) -> NSSize {
        let fileCount = summary.stagedFiles.count + summary.unstagedFiles.count

        if fileCount == 0 && summary.errorMessage == nil {
            return NSSize(width: 360, height: 220)
        }

        let rowHeight: CGFloat = 34
        let baseHeight: CGFloat = 170
        let errorHeight: CGFloat = summary.errorMessage == nil ? 0 : 46
        let calculatedHeight = baseHeight + errorHeight + CGFloat(max(fileCount, 1)) * rowHeight
        let cappedHeight = min(max(calculatedHeight, 260), 560)
        let width: CGFloat = fileCount > 8 ? 520 : 440

        return NSSize(width: width, height: cappedHeight)
    }
}
