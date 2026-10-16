import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
import UsageCore
@testable import CodexUsage

@MainActor
final class AppearanceTests: XCTestCase {
    func testDragTargetsOnlySelectedRowsAndRejectsOutsideRelease() async {
        let frames: [MenuMetric: CGRect] = [.credits: CGRect(x: 0, y: 0, width: 400, height: 30),
                                           .requests: CGRect(x: 0, y: 40, width: 400, height: 30),
                                           .tokens: CGRect(x: 0, y: 80, width: 400, height: 30)]
        XCTAssertEqual(MenuOrderDrag.target(at: CGPoint(x: 100, y: 45), frames: frames, selected: [.credits, .requests]), .requests)
        XCTAssertNotNil(MenuOrderDrag.target(at: CGPoint(x: 100, y: 35), frames: frames, selected: [.credits, .requests]))
        XCTAssertNil(MenuOrderDrag.target(at: CGPoint(x: 100, y: 45), frames: frames, selected: [.credits, .requests],
                                         viewport: CGRect(x: 0, y: 0, width: 400, height: 40)))
        for point in [CGPoint(x: 100, y: 90), CGPoint(x: -1, y: 10), CGPoint(x: 401, y: 10)] {
            XCTAssertNil(MenuOrderDrag.target(at: point, frames: frames, selected: [.credits, .requests]))
        }
    }

    private func image(width: Int = 128, height: Int = 128, transparent: Bool = true) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.systemTeal.cgColor)
        context.fill(CGRect(x: transparent ? width / 4 : 0, y: 0, width: transparent ? width / 2 : width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func encode(_ image: CGImage, type: UTType = .png) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "无法生成 \(type.identifier) 测试图片")
        return data as Data
    }

    func testCommonRasterFormatsAndRetinaSizesNormalizeToPortablePNG() async throws {
        for edge in [16, 32, 36, 40, 64, 128, 256, 512, 1024] {
            let imported = try MenuIconImporter.normalize(encode(image(width: edge, height: edge)))
            let source = try XCTUnwrap(CGImageSourceCreateWithData(imported.pngData as CFData, nil))
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(decoded.width, 128); XCTAssertEqual(decoded.height, 128)
            XCTAssertTrue(imported.hasTransparency)
        }
        for type in [UTType.jpeg, .tiff, .heic, .icns] {
            let imported = try MenuIconImporter.normalize(encode(image(transparent: false), type: type))
            XCTAssertFalse(imported.hasTransparency, "不透明图应默认保留原色：\(type.identifier)")
            XCTAssertNotNil(NSImage(data: imported.pngData))
        }
    }

    func testNonSquareImageFitsWithoutStretching() async throws {
        let imported = try MenuIconImporter.normalize(encode(image(width: 256, height: 128, transparent: false)))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: imported.pngData))
        XCTAssertEqual(rep.colorAt(x: 64, y: 0)?.alphaComponent, 0)
        XCTAssertGreaterThan(try XCTUnwrap(rep.colorAt(x: 64, y: 64)?.alphaComponent), 0.99)
        XCTAssertTrue(imported.hasTransparency)
    }

    func testPDFRendersFirstPageIntoBoundedPNG() async throws {
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var rect = CGRect(x: 0, y: 0, width: 64, height: 32)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &rect, nil))
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.systemBlue.cgColor); context.fill(rect)
        context.endPDFPage(); context.closePDF()
        let imported = try MenuIconImporter.normalize(data as Data)
        XCTAssertTrue(imported.hasTransparency)
        XCTAssertNotNil(NSImage(data: imported.pngData))
    }

    func testInvalidOversizedAndUnsupportedFilesAreRejected() async throws {
        XCTAssertThrowsError(try MenuIconImporter.normalize(Data()))
        XCTAssertThrowsError(try MenuIconImporter.normalize(Data("not an image".utf8)))
        XCTAssertThrowsError(try MenuIconImporter.normalize(Data(repeating: 1, count: MenuIconImporter.maximumFileBytes + 1)))
        XCTAssertThrowsError(try MenuIconImporter.normalize(encode(image(width: 4097, height: 1))))
        XCTAssertThrowsError(try MenuIconImporter.normalize(Data("%PDF-invalid".utf8)))
        XCTAssertThrowsError(try MenuIconImporter.normalize(encode(image(), type: .gif)))
        let blank = try XCTUnwrap(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
                                            bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        blank.clear(CGRect(x: 0, y: 0, width: 32, height: 32))
        XCTAssertThrowsError(try MenuIconImporter.normalize(encode(XCTUnwrap(blank.makeImage()))))
    }

    func testImportedIconWorksAfterSourceFileIsRemovedAndPreferencesReloaded() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("source.png")
        try encode(image()).write(to: file)
        var settings = AppSettings()
        settings.customMenuIcon = try MenuIconImporter.read(file).pngData; settings.menuIcon = .custom
        let encoded = try JSONEncoder().encode(settings)
        try FileManager.default.removeItem(at: file)
        let restored = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertNotNil(MenuBarIcon.image(settings: restored, unread: false, notice: nil, hasMetrics: true))
    }

    func testCustomIconSizeRenderingAndAlertPriority() async throws {
        var settings = AppSettings()
        XCTAssertNil(MenuBarIcon.image(settings: settings, unread: false, notice: nil, hasMetrics: true))
        settings.menuIcon = .custom
        settings.customMenuIcon = try MenuIconImporter.normalize(encode(image())).pngData
        for size in MenuIconSize.allCases {
            settings.menuIconSize = size
            for rendering in MenuIconRendering.allCases {
                settings.menuIconRendering = rendering
                let icon = try XCTUnwrap(MenuBarIcon.image(settings: settings, unread: false, notice: nil, hasMetrics: true))
                XCTAssertEqual(icon.size, NSSize(width: size.rawValue, height: size.rawValue))
                XCTAssertEqual(icon.isTemplate, rendering == .template)
            }
        }
        let unread = try XCTUnwrap(MenuBarIcon.image(settings: settings, unread: true, notice: "等待同步", hasMetrics: true))
        XCTAssertTrue(unread.isTemplate)
        XCTAssertEqual(unread.accessibilityDescription, "有新的重置动态")
        let notice = try XCTUnwrap(MenuBarIcon.image(settings: settings, unread: false, notice: "等待同步", hasMetrics: true))
        XCTAssertEqual(notice.accessibilityDescription, "等待同步")
        settings.customMenuIcon = Data([0, 1])
        XCTAssertNotNil(MenuBarIcon.image(settings: settings, unread: false, notice: nil, hasMetrics: true), "损坏图标回退到内置图标")
        for icon in MenuIconStyle.allCases where icon != .custom {
            settings.menuIcon = icon
            XCTAssertNotNil(MenuBarIcon.image(settings: settings, unread: false, notice: nil, hasMetrics: false))
        }
    }

    func testAllThemesMeetTextContrastOnBothSurfaces() async {
        func luminance(_ hex: UInt32) -> Double {
            let channels = [Double((hex >> 16) & 255), Double((hex >> 8) & 255), Double(hex & 255)].map { value -> Double in
                let v = value / 255
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        for theme in AppTheme.allCases {
            for dark in [false, true] {
                let palette = ThemePalette(theme: theme, dark: dark)
                for foreground in [palette.textHex, palette.secondaryHex, palette.accentHex] {
                    for background in [palette.backgroundHex, palette.cardHex] {
                        let a = luminance(foreground), b = luminance(background)
                        XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5,
                                                    "\(theme.rawValue) dark=\(dark) 文本/强调色对比度不足")
                    }
                }
            }
        }
    }
}
