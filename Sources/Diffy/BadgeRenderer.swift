import AppKit
import DiffyCore

enum BadgeRenderer {
    static func image(
        added: Int,
        removed: Int,
        colors: DiffColors,
        badgeLabel: BadgeLabel? = nil
    ) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let additionColor = AppColor.nsColor(hex: colors.additionHex) ?? .systemGreen
        let removalColor = AppColor.nsColor(hex: colors.removalHex) ?? .systemRed
        let separatorColor = NSColor.secondaryLabelColor

        let countsText = NSMutableAttributedString()
        countsText.append(NSAttributedString(string: "+\(added)", attributes: [.foregroundColor: additionColor, .font: font]))
        countsText.append(NSAttributedString(string: " / ", attributes: [.foregroundColor: separatorColor, .font: font]))
        countsText.append(NSAttributedString(string: "-\(removed)", attributes: [.foregroundColor: removalColor, .font: font]))

        let countsSize = countsText.size()
        let horizontalPadding: CGFloat = colors.badgeBackgroundHex == nil ? 1 : 8
        let verticalPadding: CGFloat = colors.badgeBackgroundHex == nil ? 0 : 3

        let labelText: NSAttributedString? = badgeLabel.flatMap { label -> NSAttributedString? in
            let trimmed = label.text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let labelFont = NSFont.monospacedDigitSystemFont(
                ofSize: max(NSFont.smallSystemFontSize, NSFont.systemFontSize - 2),
                weight: .semibold
            )
            return NSAttributedString(
                string: trimmed,
                attributes: [.foregroundColor: separatorColor, .font: labelFont]
            )
        }

        let labelSize = labelText?.size() ?? .zero
        let labelGap: CGFloat = 3

        var width = countsSize.width
        var height = countsSize.height
        if labelText != nil, let position = badgeLabel?.position {
            switch position {
            case .leading, .trailing:
                width += labelSize.width + labelGap
            case .above, .below:
                width = max(width, labelSize.width)
                height = countsSize.height + labelSize.height + labelGap
            }
        }

        let size = NSSize(
            width: ceil(width + horizontalPadding * 2),
            height: ceil(max(18, height + verticalPadding * 2))
        )

        let image = NSImage(size: size)
        image.lockFocus()

        if let backgroundHex = colors.badgeBackgroundHex, let background = AppColor.nsColor(hex: backgroundHex) {
            let rect = NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 1)
            let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            background.withAlphaComponent(0.82).setFill()
            path.fill()
        }

        let position = badgeLabel?.position
        if let labelText, let position {
            switch position {
            case .leading:
                let labelRect = NSRect(
                    x: horizontalPadding,
                    y: floor((size.height - labelSize.height) / 2),
                    width: labelSize.width,
                    height: labelSize.height
                )
                labelText.draw(in: labelRect)
                let countsRect = NSRect(
                    x: horizontalPadding + labelSize.width + labelGap,
                    y: floor((size.height - countsSize.height) / 2),
                    width: countsSize.width,
                    height: countsSize.height
                )
                countsText.draw(in: countsRect)

            case .trailing:
                let countsRect = NSRect(
                    x: horizontalPadding,
                    y: floor((size.height - countsSize.height) / 2),
                    width: countsSize.width,
                    height: countsSize.height
                )
                countsText.draw(in: countsRect)
                let labelRect = NSRect(
                    x: horizontalPadding + countsSize.width + labelGap,
                    y: floor((size.height - labelSize.height) / 2),
                    width: labelSize.width,
                    height: labelSize.height
                )
                labelText.draw(in: labelRect)

            case .above:
                let totalStackHeight = labelSize.height + labelGap + countsSize.height
                let stackTop = floor((size.height - totalStackHeight) / 2)
                let labelY = size.height - stackTop - labelSize.height
                let countsY = labelY - labelGap - countsSize.height
                let labelRect = NSRect(
                    x: floor((size.width - labelSize.width) / 2),
                    y: labelY,
                    width: labelSize.width,
                    height: labelSize.height
                )
                let countsRect = NSRect(
                    x: floor((size.width - countsSize.width) / 2),
                    y: countsY,
                    width: countsSize.width,
                    height: countsSize.height
                )
                labelText.draw(in: labelRect)
                countsText.draw(in: countsRect)

            case .below:
                let totalStackHeight = countsSize.height + labelGap + labelSize.height
                let stackTop = floor((size.height - totalStackHeight) / 2)
                let countsY = size.height - stackTop - countsSize.height
                let labelY = countsY - labelGap - labelSize.height
                let countsRect = NSRect(
                    x: floor((size.width - countsSize.width) / 2),
                    y: countsY,
                    width: countsSize.width,
                    height: countsSize.height
                )
                let labelRect = NSRect(
                    x: floor((size.width - labelSize.width) / 2),
                    y: labelY,
                    width: labelSize.width,
                    height: labelSize.height
                )
                countsText.draw(in: countsRect)
                labelText.draw(in: labelRect)
            }
        } else {
            let countsRect = NSRect(
                x: horizontalPadding,
                y: floor((size.height - countsSize.height) / 2),
                width: countsSize.width,
                height: countsSize.height
            )
            countsText.draw(in: countsRect)
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
