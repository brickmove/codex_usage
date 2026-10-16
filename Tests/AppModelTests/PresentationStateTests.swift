import XCTest
import UsageCore
@testable import CodexUsage

@MainActor
final class PresentationStateTests: XCTestCase {
    func testRejectedRangePreservesAppliedDataAndDoesNotBecomeSourceError() async throws {
        let model = AppModel.previewModel()
        let settings = model.settings
        let requests = model.statistics?.totalRequests
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        model.setCustomRange(start: start, end: start.addingTimeInterval(-1))
        XCTAssertEqual(model.settings, settings)
        XCTAssertEqual(model.statistics?.totalRequests, requests)
        XCTAssertNil(model.statisticsError, "日期输入错误由输入处解释，不冒充数据库错误")
    }

    func testEqualCustomDatesCanBeApplied() async throws {
        let model = AppModel.previewModel()
        let point = Date(timeIntervalSince1970: 1_800_000_000)
        model.setCustomRange(start: point, end: point)
        XCTAssertEqual(model.settings.range, .custom)
        XCTAssertEqual(model.settings.customStart, point)
        XCTAssertEqual(model.settings.customEnd, point)
        XCTAssertNil(model.statisticsError)
    }

    func testAnalysisDoesNotConsumeUnreadNewsBeforeNewsPageIsVisible() async throws {
        let model = AppModel.previewModel()
        let unread = model.unreadNewsCount
        XCTAssertGreaterThan(unread, 0)
        model.setPanelVisible(true)
        model.selectedTab = .analysis
        XCTAssertEqual(model.unreadNewsCount, unread)
        model.selectedTab = .resetNews
        XCTAssertEqual(model.unreadNewsCount, 0)
    }
}
