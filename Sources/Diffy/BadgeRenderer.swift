import AppKit
import DiffyCore

enum BadgeRenderer {
    static func image(added: Int, removed: Int, colors: DiffColors) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let additionColor = AppColor.nsColor(hex: colors.additionHex) ?? .systemGreen
        let removalColor = AppColor.nsColor(hex: colors.removalHex) ?? .systemRed
        let separatorColor = NSColor.secondaryLabelColor

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "+\(added)", attributes: [.foregroundColor: additionColor, .font: font]))
        text.append(NSAttributedString(string: " / ", attributes: [.foregroundColor: separatorColor, .font: font]))
        text.append(NSAttributedString(string: "-\(removed)", attributes: [.foregroundColor: removalColor, .font: font]))

        let textSize = text.size()
        let horizontalPadding: CGFloat = colors.badgeBackgroundHex == nil ? 1 : 8
        let verticalPadding: CGFloat = colors.badgeBackgroundHex == nil ? 0 : 3
        let size = NSSize(
            width: ceil(textSize.width + horizontalPadding * 2),
            height: ceil(max(18, textSize.height + verticalPadding * 2))
        )

        let image = NSImage(size: size)
        image.lockFocus()

        if let backgroundHex = colors.badgeBackgroundHex, let background = AppColor.nsColor(hex: backgroundHex) {
            let rect = NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 1)
            let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            background.withAlphaComponent(0.82).setFill()
            path.fill()
        }

        let textRect = NSRect(
            x: horizontalPadding,
            y: floor((size.height - textSize.height) / 2),
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
