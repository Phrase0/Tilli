import XCTest
import SwiftUI
@testable import Tilli

/// 優惠明細（交易明細與訂單摘要共用）：含已取消組合與兩種折扣時不可比手機寬
@MainActor
final class DiscountBreakdownViewLayoutTests: XCTestCase {

    func testBreakdownWithCancelledComboFitsPhoneWidth() {
        let view = DiscountBreakdownView(
            subtotal: 290,
            comboLines: [
                .init(id: UUID(), name: "大福三個 100", amount: 20, isCancelled: false),
                .init(id: UUID(), name: "任選兩個非常長的組合名稱測試用", amount: 0, isCancelled: true),
            ],
            discounts: [
                AppliedDiscount(discountId: UUID(), type: .percentage, value: 10, amount: 27),
                AppliedDiscount(discountId: UUID(), type: .amount, value: 25, amount: 25),
            ],
            total: 218,
            savings: 72,
            currency: "TWD",
            onToggleCombo: { _ in }
        )
        .padding(.horizontal, DesignSystem.Spacing.md)
        let host = UIHostingController(rootView: view)

        for width in [375.0, 393.0] {
            let size = host.sizeThatFits(in: CGSize(width: width, height: 2000))
            XCTAssertLessThanOrEqual(size.width, width, "寬度 \(width) 時超出")
            XCTAssertGreaterThan(size.height, 0)
        }
    }
}
