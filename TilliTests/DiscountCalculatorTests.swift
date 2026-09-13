//
//  DiscountCalculatorTests.swift
//  TilliTests
//
//  Created by Peiyun on 2026/9/13.
//
//  對應 FEATURE_PLAN_V1.md §2.3（B1、B4）、§6.2/§6.3，與測試清單 F1–F5。
//

import XCTest
@testable import Tilli

final class DiscountCalculatorTests: XCTestCase {

    // MARK: - 單一折扣金額（F1／F2）

    func testPercentageAmount() {
        // 200 的 10%（打九折）= 20
        XCTAssertEqual(
            DiscountCalculator.amount(type: .percentage, value: 10, subtotal: 200),
            20
        )
    }

    func testFixedAmount() {
        XCTAssertEqual(
            DiscountCalculator.amount(type: .amount, value: 20, subtotal: 200),
            20
        )
    }

    // MARK: - 計算順序：先百分比、後定額（F3，§6.2）

    func testPercentageAppliedBeforeFixedAmount() {
        let total = DiscountCalculator.total(
            subtotal: 200,
            discounts: [.percentage(10), .amount(20)]
        )

        // 200 → 九折 180 → −20 = 160
        // 若順序寫反（先 −20 再九折）會得到 162，這條就是用來擋那個 bug
        XCTAssertEqual(total, 160)
    }

    func testDiscountOrderIsIndependentOfArrayOrder() {
        let a = DiscountCalculator.total(subtotal: 200, discounts: [.percentage(10), .amount(20)])
        let b = DiscountCalculator.total(subtotal: 200, discounts: [.amount(20), .percentage(10)])

        XCTAssertEqual(a, b, "順序由型別決定，不該受陣列排列影響")
        XCTAssertEqual(a, 160)
    }

    func testCombinedAmountEqualsSubtotalMinusTotal() {
        let discounts: [DiscountModel] = [.percentage(10), .amount(20)]
        let amount = DiscountCalculator.amount(for: discounts, subtotal: 200)

        XCTAssertEqual(amount, 40)
        XCTAssertEqual(
            DiscountCalculator.total(subtotal: 200, discounts: discounts),
            200 - amount
        )
    }

    // MARK: - Clamp 上界（F4：報表不可出現負營收）

    func testFixedAmountIsClampedToSubtotal() {
        // 小計 50、折抵 100 → 只能折 50
        XCTAssertEqual(
            DiscountCalculator.amount(type: .amount, value: 100, subtotal: 50),
            50
        )
        XCTAssertEqual(
            DiscountCalculator.total(subtotal: 50, discounts: [.amount(100)]),
            0,
            "總額不可為負"
        )
    }

    func testPercentageOverHundredIsClampedToHundred() {
        XCTAssertEqual(
            DiscountCalculator.amount(type: .percentage, value: 150, subtotal: 200),
            200
        )
        XCTAssertEqual(
            DiscountCalculator.total(subtotal: 200, discounts: [.percentage(150)]),
            0
        )
    }

    // MARK: - Clamp 下界

    func testNegativeDiscountValueIsClampedToZero() {
        XCTAssertEqual(DiscountCalculator.amount(type: .amount, value: -50, subtotal: 200), 0)
        XCTAssertEqual(DiscountCalculator.amount(type: .percentage, value: -10, subtotal: 200), 0)
        XCTAssertEqual(DiscountCalculator.total(subtotal: 200, discounts: [.amount(-50)]), 200)
    }

    // MARK: - 邊界

    func testZeroSubtotalNeverDividesByZero() {
        XCTAssertEqual(DiscountCalculator.amount(type: .percentage, value: 10, subtotal: 0), 0)
        XCTAssertEqual(DiscountCalculator.amount(type: .amount, value: 10, subtotal: 0), 0)
        XCTAssertEqual(DiscountCalculator.amount(for: [.percentage(10)], subtotal: 0), 0)
        XCTAssertEqual(DiscountCalculator.total(subtotal: 0, discounts: [.amount(10)]), 0)
    }

    func testEmptyDiscountsLeaveSubtotalUnchanged() {
        XCTAssertEqual(DiscountCalculator.amount(for: [], subtotal: 200), 0)
        XCTAssertEqual(DiscountCalculator.total(subtotal: 200, discounts: []), 200)
        XCTAssertEqual(DiscountCalculator.total(subtotal: 200, discount: nil), 200)
    }

    func testTwoPercentageDiscountsApplySequentially() {
        // UI 不允許同時選兩個百分比，但資料層要可預測、不能爆
        // 200 → 九折 180 → 再九折 162
        XCTAssertEqual(
            DiscountCalculator.total(subtotal: 200, discounts: [.percentage(10), .percentage(10)]),
            162
        )
    }

    // MARK: - effective：寫進流水帳前的收斂（F5）

    func testEffectiveClampsFixedAmountButKeepsIdentity() {
        let id = UUID()
        let original = DiscountModel.amount(100, id: id)

        let effective = DiscountCalculator.effective(original, subtotal: 50)

        XCTAssertEqual(effective?.value, 50, "超過小計的部分被 clamp 掉")
        XCTAssertEqual(effective?.id, id, "id 必須保留，否則對不回 event.discounts 的設定")
        XCTAssertEqual(effective?.type, .amount)
    }

    func testEffectiveReturnsUnchangedWhenWithinLimit() {
        let original = DiscountModel.amount(20)
        XCTAssertEqual(DiscountCalculator.effective(original, subtotal: 200), original)

        let percentage = DiscountModel.percentage(10)
        XCTAssertEqual(DiscountCalculator.effective(percentage, subtotal: 200), percentage)
    }

    func testEffectiveClampsPercentageOverHundred() {
        let effective = DiscountCalculator.effective(.percentage(150), subtotal: 200)
        XCTAssertEqual(effective?.value, 100)
    }

    func testEffectiveOfNilIsNil() {
        XCTAssertNil(DiscountCalculator.effective(nil, subtotal: 200))
    }

    /// ⭐ F5：即使呼叫端傳進未 clamp 的折扣，寫進流水帳的金額仍然不會讓營收變負。
    func testUnclampedDiscountCannotProduceNegativeRevenue() {
        let subtotal: Decimal = 50
        let effective = DiscountCalculator.effective(.amount(9999), subtotal: subtotal)
        let total = DiscountCalculator.total(subtotal: subtotal, discount: effective)

        XCTAssertEqual(total, 0)
        XCTAssertGreaterThanOrEqual(total, 0)
    }

    // MARK: - exceedsSubtotal（UI 提示用）

    func testExceedsSubtotal() {
        XCTAssertTrue(DiscountCalculator.exceedsSubtotal(.amount(100), subtotal: 50))
        XCTAssertFalse(DiscountCalculator.exceedsSubtotal(.amount(50), subtotal: 50))
        XCTAssertFalse(DiscountCalculator.exceedsSubtotal(.amount(10), subtotal: 50))

        // 百分比只有 > 100 才算超過
        XCTAssertFalse(DiscountCalculator.exceedsSubtotal(.percentage(100), subtotal: 50))
        XCTAssertTrue(DiscountCalculator.exceedsSubtotal(.percentage(101), subtotal: 50))

        // 沒折扣或小計為 0 → 不算超過
        XCTAssertFalse(DiscountCalculator.exceedsSubtotal(nil, subtotal: 50))
        XCTAssertFalse(DiscountCalculator.exceedsSubtotal(.amount(100), subtotal: 0))
    }

    // MARK: - 流水帳

    func testAmountForTransactionUsesItemsSubtotal() {
        let transaction = TransactionModel.mock(
            items: [.mock(price: 100, quantity: 2)],   // 小計 200
            discountType: .percentage,
            discountValue: 10
        )

        XCTAssertEqual(transaction.subtotal, 200)
        XCTAssertEqual(DiscountCalculator.amount(for: transaction), 20)
    }

    func testAmountForTransactionWithoutDiscountIsZero() {
        let transaction = TransactionModel.mock(items: [.mock(price: 100, quantity: 2)])
        XCTAssertEqual(DiscountCalculator.amount(for: transaction), 0)
    }

    func testAmountForTransactionIsClamped() {
        // 流水帳裡萬一存進超過小計的折扣，報表端仍然不會算出負營收
        let transaction = TransactionModel.mock(
            items: [.mock(price: 10, quantity: 1)],    // 小計 10
            discountType: .amount,
            discountValue: 999
        )

        XCTAssertEqual(DiscountCalculator.amount(for: transaction), 10)
    }

    // MARK: - 顯示文字

    func testDeductionText() {
        XCTAssertEqual(DiscountCalculator.deductionText(type: .percentage, value: 5), "5%")
        XCTAssertEqual(DiscountCalculator.deductionText(type: .amount, value: 5), "-5")
    }

    func testDeductionTextForTransaction() {
        let withDiscount = TransactionModel.mock(discountType: .amount, discountValue: 5)
        XCTAssertEqual(DiscountCalculator.deductionText(for: withDiscount), "-5")

        let withoutDiscount = TransactionModel.mock()
        XCTAssertNil(DiscountCalculator.deductionText(for: withoutDiscount))
    }

    func testDisplayTextUsesCurrencySymbol() {
        XCTAssertEqual(DiscountCalculator.displayText(type: .percentage, value: 5), "5%")
        XCTAssertEqual(DiscountCalculator.displayText(type: .amount, value: 5, currency: "TWD"), "NT$5")
        XCTAssertEqual(DiscountCalculator.displayText(type: .amount, value: 5, currency: "JPY"), "¥5")
        XCTAssertEqual(DiscountCalculator.displayText(type: .amount, value: 5, currency: "USD"), "$5")
    }

    func testDiscountModelDisplayTextDelegatesToCalculator() {
        // DiscountModel.displayText 已改成委派，兩者必須一致
        let discount = DiscountModel.amount(5)
        XCTAssertEqual(
            discount.displayText(currency: "TWD"),
            DiscountCalculator.displayText(type: .amount, value: 5, currency: "TWD")
        )
    }
}
