import XCTest
import SwiftUI
@testable import Tilli

/// 時間範圍選擇器選「自訂」時不可比螢幕寬（中文長日期並排約需 415pt，超出會撐寬整頁、清單左右溢出）
@MainActor
final class ReportTimeRangeSelectorLayoutTests: XCTestCase {

    func testCustomRangeFitsPhoneWidths() {
        let event = EventModel.mock(dateType: .permanent)
        let selector = ReportTimeRangeSelector(
            event: event,
            selectedRange: .constant(ReportTimeRange(event: event, type: .custom))
        )
        .padding(.horizontal, DesignSystem.Spacing.md)
        let host = UIHostingController(rootView: selector)

        for width in [375.0, 393.0, 402.0, 440.0] {
            let size = host.sizeThatFits(in: CGSize(width: width, height: 2000))
            XCTAssertLessThanOrEqual(size.width, width, "寬度 \(width) 時超出")
        }
    }
}
