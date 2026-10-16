import XCTest
@testable import UsageCore

final class AppearanceSettingsTests: XCTestCase {
    func testMetricIconsAreIndependentAndSurvivePersistenceAndReordering() throws {
        var settings = AppSettings()
        var credits = MenuMetricIcon(); credits.style = .bolt; credits.size = .large
        var tokens = MenuMetricIcon(); tokens.style = .custom; tokens.imageData = Data([1, 2, 3]); tokens.rendering = .original
        settings.setIcon(credits, for: .credits); settings.setIcon(tokens, for: .tokens)
        settings.menuMetrics = [.credits, .tokens]
        settings.moveMenuMetric(.tokens, to: 0)
        let loaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(loaded.icon(for: .credits), credits)
        XCTAssertEqual(loaded.icon(for: .tokens), tokens)
        XCTAssertEqual(loaded.icon(for: .quotaRemaining).style, .automatic)
        XCTAssertEqual(loaded.menuMetrics, [.tokens, .credits])
    }

    func testSelectingGroupReplacesOverridesButKeepsDistinctMetricMeanings() throws {
        var settings = AppSettings()
        var custom = MenuMetricIcon(); custom.style = .bolt
        settings.setIcon(custom, for: .credits)
        for set in MenuIconSet.allCases {
            settings.selectIconSet(set)
            XCTAssertTrue(settings.metricIcons.isEmpty)
            XCTAssertEqual(Set(MenuMetric.allCases.map { set.symbolName(for: $0) }).count, MenuMetric.allCases.count,
                           "整套图标必须保留每个指标的独立语义，不能全变成同一图标")
            let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
            XCTAssertEqual(restored.menuIconSet, set)
        }
    }

    func testLegacyPrefixIconIsNotCopiedOntoEveryMetric() throws {
        let data = Data(#"{"menuIcon":"bolt","menuIconSize":20,"menuMetrics":["tokens","credits"],"databasePath":"/keep.db","menuIconSet":"future"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.menuIconSet, .standard)
        XCTAssertEqual(settings.menuIcon, .bolt, "仅图标模式保留旧配置")
        XCTAssertEqual(settings.icon(for: .tokens).style, .automatic)
        XCTAssertEqual(settings.icon(for: .credits).size, .large)
        XCTAssertEqual(settings.databasePath, "/keep.db")
        XCTAssertEqual(settings.menuMetrics, [.tokens, .credits])
    }

    func testBadMetricEntryDoesNotDiscardOtherIconsOrPreferences() throws {
        let data = Data(#"{"metricIcons":{"credits":{"style":"bolt"},"tokens":false,"unknown":{"style":"chart"}},"range":"month"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.icon(for: .credits).style, .bolt)
        XCTAssertEqual(settings.icon(for: .tokens).style, .automatic)
        XCTAssertNil(settings.metricIcons["unknown"])
        XCTAssertEqual(settings.range, .month)
    }

    func testDraggingMovesAcrossMultiplePositionsWithoutSwappingOtherMetrics() throws {
        var settings = AppSettings()
        settings.menuMetrics = [.credits, .requests, .cost, .tokens]
        settings.moveMenuMetric(.credits, to: 3)
        XCTAssertEqual(settings.menuMetrics, [.requests, .cost, .tokens, .credits])
        settings.moveMenuMetric(.credits, to: 0)
        XCTAssertEqual(settings.menuMetrics, [.credits, .requests, .cost, .tokens])
        let before = settings
        settings.moveMenuMetric(.credits, to: -1)
        settings.moveMenuMetric(.tokens, to: 4)
        settings.moveMenuMetric(.quotaRemaining, to: 0)
        settings.moveMenuMetric(.requests, to: 1)
        XCTAssertEqual(settings, before, "无效拖动与原位释放不修改已选项目")
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.menuMetrics, settings.menuMetrics)
    }

    func testExistingPreferencesKeepPathsAndMetricsWithDefaultAppearance() throws {
        let old = Data(#"{"databasePath":"/custom/usage.db","menuMetrics":["tokens","credits"],"range":"month"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertEqual(settings.databasePath, "/custom/usage.db")
        XCTAssertEqual(settings.menuMetrics, [.tokens, .credits])
        XCTAssertEqual(settings.range, .month)
        XCTAssertEqual(settings.theme, .teal)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.menuIcon, .automatic)
        XCTAssertEqual(settings.menuIconSize, .regular)
    }

    func testUnknownAppearanceAndDamagedIconDoNotResetOtherPreferences() throws {
        let json = Data(#"{"theme":"future","appearance":"future","menuIcon":"future","menuIconSize":99,"menuIconRendering":"future","customMenuIcon":"not base64!","databasePath":"/keep.db","menuMetrics":[]}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.theme, .teal)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.menuIcon, .automatic)
        XCTAssertEqual(settings.menuIconSize, .regular)
        XCTAssertEqual(settings.menuIconRendering, .template)
        XCTAssertNil(settings.customMenuIcon)
        XCTAssertEqual(settings.databasePath, "/keep.db")
        XCTAssertTrue(settings.menuMetrics.isEmpty)
    }

    func testAppearanceAndEmbeddedIconSurviveRelaunch() throws {
        let domain = "CodexUsageAppearanceTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        for theme in AppTheme.allCases {
            var settings = AppSettings()
            settings.theme = theme; settings.appearance = .dark
            settings.menuIcon = .custom; settings.menuIconSize = .large; settings.menuIconRendering = .original
            settings.customMenuIcon = Data([1, 2, 3]); settings.customMenuIconName = "sample.png"
            settings.save(to: defaults)
            XCTAssertEqual(AppSettings.load(from: defaults), settings)
        }
    }
}
