import AppKit
import ImageIO
import UniformTypeIdentifiers
import UsageCore

struct ImportedMenuIcon {
    let pngData: Data
    let hasTransparency: Bool
}

enum MenuIconImporter {
    static let maximumFileBytes = 10 * 1024 * 1024
    static let maximumPixelDimension = 4096
    static let allowedTypes: [UTType] = [.png, .jpeg, .tiff, .heic, .heif, .pdf, .icns]

    static func read(_ url: URL) throws -> ImportedMenuIcon {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maximumFileBytes else {
            throw UsageError.message("请选择不超过 10 MB 的图标文件。")
        }
        return try normalize(Data(contentsOf: url))
    }

    /// Store a bounded PNG, never an external path. Rendering is identical after moving the original file.
    static func normalize(_ data: Data) throws -> ImportedMenuIcon {
        guard !data.isEmpty, data.count <= maximumFileBytes else {
            throw UsageError.message("图标文件为空或超过 10 MB。")
        }
        let edge = 128
        guard let context = CGContext(data: nil, width: edge, height: edge, bitsPerComponent: 8,
                                      bytesPerRow: edge * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw UsageError.message("无法创建图标，请重新选择图片。")
        }
        let target = CGRect(x: 0, y: 0, width: edge, height: edge)
        context.clear(target)
        context.interpolationQuality = .high
        if data.starts(with: Data("%PDF-".utf8)) {
            guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
                  !document.isEncrypted, let page = document.page(at: 1) else {
                throw UsageError.message("无法读取 PDF 图标，请选择未加密的文件。")
            }
            let bounds = page.getBoxRect(.cropBox)
            guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
                throw UsageError.message("PDF 图标的页面尺寸无效。")
            }
            context.concatenate(page.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
        } else {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let identifier = CGImageSourceGetType(source),
                  let type = UTType(identifier as String),
                  allowedTypes.filter({ $0 != .pdf }).contains(where: { type.conforms(to: $0) }) else {
                throw UsageError.message("无法读取图片。支持 PNG、JPEG、TIFF、HEIC/HEIF、PDF 和 ICNS。")
            }
            // ICNS contains multiple resolutions; use its largest representation. Other formats use the first frame/page.
            let count = CGImageSourceGetCount(source)
            guard count > 0, count <= 256 else { throw UsageError.message("图标不包含有效的图片。") }
            var index = 0
            var largest = 0
            for candidate in 0..<(type.conforms(to: .icns) ? count : 1) {
                guard let properties = CGImageSourceCopyPropertiesAtIndex(source, candidate, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      width > 0, height > 0, width <= maximumPixelDimension, height <= maximumPixelDimension else {
                    throw UsageError.message("图标尺寸无效，最长边不能超过 4096 像素。")
                }
                if max(width, height) > largest { largest = max(width, height); index = candidate }
            }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                          kCGImageSourceCreateThumbnailWithTransform: true,
                                          kCGImageSourceThumbnailMaxPixelSize: edge]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
                throw UsageError.message("图片内容损坏，请选择其他图标。")
            }
            let scale = min(CGFloat(edge) / CGFloat(image.width), CGFloat(edge) / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            context.draw(image, in: CGRect(x: (CGFloat(edge) - size.width) / 2, y: (CGFloat(edge) - size.height) / 2,
                                          width: size.width, height: size.height))
        }
        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else {
            throw UsageError.message("无法保存图标，请尝试另一张图片。")
        }
        let transparent = (0..<(edge * edge)).contains { pixels[$0 * 4 + 3] < 250 }
        guard (0..<(edge * edge)).contains(where: { pixels[$0 * 4 + 3] > 0 }) else {
            throw UsageError.message("图片完全透明，请选择包含可见内容的图标。")
        }
        return ImportedMenuIcon(pngData: png, hasTransparency: transparent)
    }
}

enum MenuBarIcon {
    static func image(settings: AppSettings, unread: Bool, notice: String?, hasMetrics: Bool) -> NSImage? {
        let symbol: String
        let description: String
        if unread { symbol = "bell.badge.fill"; description = "有新的重置动态" }
        else if let notice { symbol = "exclamationmark.circle"; description = notice }
        else {
            guard settings.menuIcon != .automatic || !hasMetrics else { return nil }
            if settings.menuIcon == .custom, let data = settings.customMenuIcon, let image = NSImage(data: data) {
                image.size = NSSize(width: settings.menuIconSize.rawValue, height: settings.menuIconSize.rawValue)
                image.isTemplate = settings.menuIconRendering == .template
                image.accessibilityDescription = "自定义 Codex 用量图标"
                return image
            }
            symbol = settings.menuIcon.symbolName; description = "Codex 用量"
        }
        let edge = CGFloat(settings.menuIconSize.rawValue)
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: edge - 2, weight: .medium)) else { return nil }
        // Keep wide symbols inside the same square footprint as custom icons.
        let scale = min(edge / max(1, image.size.width), edge / max(1, image.size.height))
        image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        image.isTemplate = true
        return image
    }
}
