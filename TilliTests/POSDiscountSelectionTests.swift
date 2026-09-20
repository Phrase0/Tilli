//
//  POSDiscountSelectionTests.swift
//  TilliTests
//
//  Created by Peiyun on 2026/9/15.
//
//  對應 FEATURE_PLAN_V1.md §6.4 與 §11 第 3 批的 3.2。
//

import XCTest
@testable import Tilli

@MainActor
final class POSDiscountSelectionTests: XCTestCase {

    private let p5 = DiscountModel.percentage(5)
    private let p10 = DiscountModel.percentage(10)
    private let a20 = DiscountModel.amount(20)
    private let a50 = DiscountModel.amount(50)

    private func makeViewModel() -> POSViewModel {
        // 刻意用亂序建立，驗證 chip 會自己升冪排
        let event = EventModel.mock(discounts: [a50, p10, a20, p5])
        return POSViewModel(dataSource: EventDataSource(event: event))
    }

    // MARK: - 分區與排序（§6.4）

    func testDiscountsAreSplitByTypeAndSortedAscending() {
        let vm = makeViewModel()

        XCTAssertEqual(vm.percentageDiscounts.map(\.value), [5, 10])
        XCTAssertEqual(vm.amountDiscounts.map(\.value), [20, 50])
    }

    // MARK: - 兩區各自單選

    func testSelectingWithinOneTypeReplacesPreviousSelection() {
        let vm = makeViewModel()

        vm.toggleDiscount(p5)
        XCTAssertTrue(vm.isSelected(p5))

        vm.toggleDiscount(p10)
        XCTAssertTrue(vm.isSelected(p10))
        XCTAssertFalse(vm.isSelected(p5), "同一區只能選一個")
    }

    func testTappingSelectedChipAgainDeselectsIt() {
        let vm = makeViewModel()

        vm.toggleDiscount(p10)
        vm.toggleDiscount(p10)

        XCTAssertFalse(vm.isSelected(p10))
        XCTAssertTrue(vm.selectedDiscounts.isEmpty)
    }

    /// ⭐ §6.1：可同時一個百分比 + 一個定額
    func testPercentageAndAmountCanBeSelectedTogether() {
        let vm = makeViewModel()

        vm.toggleDiscount(p10)
        vm.toggleDiscount(a20)

        XCTAssertTrue(vm.isSelected(p10))
        XCTAssertTrue(vm.isSelected(a20))
        XCTAssertEqual(vm.selectedDiscounts.count, 2)
    }

    func testSelectedDiscountsAlwaysPutPercentageFirst() {
        let vm = makeViewModel()

        // 刻意先選定額再選百分比
        vm.toggleDiscount(a20)
        vm.toggleDiscount(p10)

        XCTAssertEqual(vm.selectedDiscounts.map(\.type), [.percentage, .amount],
                       "順序要與 DiscountCalculator 的套用順序一致")
    }

    func testClearAllQuantitiesAlsoClearsDiscounts() {
        let vm = makeViewModel()

        vm.toggleDiscount(p10)
        vm.toggleDiscount(a20)
        vm.clearAllQuantities()

        XCTAssertTrue(vm.selectedDiscounts.isEmpty)
    }

    // MARK: - 超額提示

    func testExceedsLimitComparesAgainstAmountAfterPercentage() {
        // 沒有商品時小計為 0，用 DiscountCalculator 直接驗證同一條規則：
        // 小計 200 → 九折剩 180 → 定額 200 超過 180，應該要提示
        let afterPercentage = DiscountCalculator.total(subtotal: 200, discounts: [p10])
        XCTAssertEqual(afterPercentage, 180)
        XCTAssertTrue(DiscountCalculator.exceedsSubtotal(.amount(200), subtotal: afterPercentage),
                      "比的是折後金額，不是原始小計")
        XCTAssertFalse(DiscountCalculator.exceedsSubtotal(.amount(180), subtotal: afterPercentage))
    }

    // MARK: - 寫進流水帳的快照

    func testAppliedDiscountsAreEmptyWithoutSelection() {
        XCTAssertTrue(makeViewModel().appliedDiscounts().isEmpty)
    }
}
