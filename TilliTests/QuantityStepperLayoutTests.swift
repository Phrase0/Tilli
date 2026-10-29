import XCTest
import SwiftUI
@testable import Tilli

/// 增減元件要能疊在格狀卡片的圖片上（三欄時圖片寬約 110pt），任何狀態都不能撐破
@MainActor
final class QuantityStepperLayoutTests: XCTestCase {

    private func size(quantity: Int, isExpanded: Bool, trashAtOne: Bool = false) -> CGSize {
        let stepper = QuantityStepper(
            quantity: quantity,
            isExpanded: isExpanded,
            canIncrement: true,
            trashAtOne: trashAtOne,
            onIncrement: {},
            onDecrement: {},
            onExpand: {}
        )
        return UIHostingController(rootView: stepper).sizeThatFits(in: CGSize(width: 400, height: 400))
    }

    func testStepperStaysCompactInEveryState() {
        let states: [(Int, Bool, Bool)] = [(0, false, false), (3, false, false), (1, true, false), (1, true, true), (99, true, false)]
        for (quantity, expanded, trash) in states {
            let s = size(quantity: quantity, isExpanded: expanded, trashAtOne: trash)
            XCTAssertLessThanOrEqual(s.height, 32, "數量 \(quantity) 展開 \(expanded) 高度超過")
            XCTAssertLessThanOrEqual(s.width, 120, "數量 \(quantity) 展開 \(expanded) 寬度超過")
        }
    }

    func testCollapsedStatesAreSingleCircle() {
        XCTAssertEqual(size(quantity: 0, isExpanded: false).width, 28, accuracy: 0.5)
        XCTAssertEqual(size(quantity: 3, isExpanded: false).width, 28, accuracy: 0.5)
    }
}
