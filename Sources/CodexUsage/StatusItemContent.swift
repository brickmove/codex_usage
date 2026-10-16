import AppKit
import SwiftUI
import UsageCore

/// Both the real status item and settings preview use this native symbol/text renderer.
enum StatusItemContent {
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    static func title(items: [MenuDisplayItem], leadingSpace: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        if leadingSpace && !items.isEmpty { result.append(NSAttributedString(string: " ", attributes: attributes)) }
        for (index, item) in items.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\u{2002}\u{2002}", attributes: attributes)) }
            if let image = NSImage(systemSymbolName: item.metric.symbolName, accessibilityDescription: item.metric.title)?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .medium)) {
                image.isTemplate = true
                let attachment = NSTextAttachment()
                attachment.image = image
                let height: CGFloat = 12
                let width = image.size.height > 0 ? image.size.width * height / image.size.height : height
                attachment.bounds = NSRect(x: 0, y: -2, width: width, height: height)
                result.append(NSAttributedString(attachment: attachment))
                result.append(NSAttributedString(string: " ", attributes: attributes))
            }
            result.append(NSAttributedString(string: item.value, attributes: attributes))
        }
        return result
    }
}

struct MenuBarValuesPreview: NSViewRepresentable {
    let items: [MenuDisplayItem]

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byClipping
        field.setContentHuggingPriority(.required, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.attributedStringValue = StatusItemContent.title(items: items)
        field.setAccessibilityLabel(items.map(\.label).joined(separator: "，"))
        field.toolTip = items.map(\.label).joined(separator: "\n")
    }
}
