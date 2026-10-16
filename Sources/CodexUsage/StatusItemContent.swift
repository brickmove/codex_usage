import AppKit
import SwiftUI
import UsageCore

/// Both the real status item and settings preview use this native symbol/text renderer.
enum StatusItemContent {
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    static func title(items: [MenuDisplayItem], settings: AppSettings, leadingSpace: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        if leadingSpace && !items.isEmpty { result.append(NSAttributedString(string: " ", attributes: attributes)) }
        for (index, item) in items.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\u{2002}\u{2002}", attributes: attributes)) }
            if let image = MenuBarIcon.metricImage(for: item.metric, settings: settings) {
                let attachment = NSTextAttachment()
                attachment.image = image
                let height = image.size.height
                let width = image.size.height > 0 ? image.size.width * height / image.size.height : height
                attachment.bounds = NSRect(x: 0, y: (font.capHeight - height) / 2, width: width, height: height)
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
    let settings: AppSettings

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byClipping
        field.setContentHuggingPriority(.required, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.attributedStringValue = StatusItemContent.title(items: items, settings: settings)
        field.setAccessibilityLabel(items.map(\.label).joined(separator: "，"))
        field.toolTip = items.map(\.label).joined(separator: "\n")
    }
}
