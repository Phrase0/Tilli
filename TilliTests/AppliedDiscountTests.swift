//
//  AppliedDiscountTests.swift
//  TilliTests
//
//  Created by Peiyun on 2026/9/15.
//
//  對應 FEATURE_PLAN_V1.md §6.1–§6.3 與 §11 第 3 批的 3.1／3.4。
//

import XCTest
@testable import Tilli

final class AppliedDiscountTests: XCTestCase {

    // MARK: - applied：產生流水帳快照

    func testAppliedRecordsEachDiscountDeduction() {
        let percentage = DiscountModel.percentage(10)
        let amount = DiscountModel.amount(20)

        let applied = DiscountCalculator.applied(for: [percentage, amount], subtotal: 200)

        XCTAssertEqual(applied.count, 2)
        // 先百分比：200 的 10% = 20
        XCTAssertEqual(applied[0].type, .percentage)
        XCTAssertEqual(applied[0].discountId, percentage.id)
        XCTAssertEqual(applied[0].value, 10)
        XCTAssertEqual(applied[0].amount, 20)
        // 後定額：從剩下的 180 扣 20
        XCTAssertEqual(applied[1].type, .amount)
        XCTAssertEqual(applied[1].discountId, amount.id)
        XCTAssertEqual(applied[1].amount, 20)
    }

    func testAppliedAlwaysPutsPercentageFirstRegardlessOfInputOrder() {
        let applied = DiscountCalculator.applied(
            for: [.amount(20), .percentage(10)],
            subtotal: 200
        )

        XCTAssertEqual(applied.map(\.type), [.percentage, .amount])
    }

    /// ⭐ 核心不變式：快照加總必須等於「小計 − 實收總額」。
    /// 第 4 批的攤提會依賴這條（§7.3）。
    func testAppliedAmountsSumToSubtotalMinusTotal() {
        let cases: [(Decimal, [DiscountModel])] = [
            (200, [.percentage(10), .amount(20)]),
            (200, [.percentage(10)]),
            (200, [.amount(20)]),
            (50,  [.amount(100)]),                  // clamp
            (200, [.percentage(150)]),              // clamp
            (99,  [.percentage(33), .amount(7)]),   // 除不盡
            (1,   [.percentage(50), .amount(1)])
        ]

        for (subtotal, discounts) in cases {
            let applied = DiscountCalculator.applied(for: discounts, subtotal: subtotal)
            let total = DiscountCalculator.total(subtotal: subtotal, discounts: discounts)
            let sum = applied.reduce(Decimal(0)) { MoneyHelper.add($0, $1.amount) }

            XCTAssertEqual(sum, MoneyHelper.subtract(subtotal, total),
                           "小計 \(subtotal) 折扣 \(discounts.map(\.value)) 對不起來")
        }
    }

    func testAppliedClampsFixedAmountToRemainingAfterPercentage() {
        // 200 → 九折剩 180 → 定額 500 只能折 180
        let applied = DiscountCalculator.applied(
            for: [.percentage(10), .amount(500)],
            subtotal: 200
        )

        XCTAssertEqual(applied[0].amount, 20)
        XCTAssertEqual(applied[1].amount, 180)
        XCTAssertEqual(DiscountCalculator.total(subtotal: 200, discounts: [.percentage(10), .amount(500)]), 0)
    }

    func testAppliedIsEmptyWhenNothingToDiscount() {
        XCTAssertTrue(DiscountCalculator.applied(for: [], subtotal: 200).isEmpty)
        XCTAssertTrue(DiscountCalculator.applied(for: [.amount(10)], subtotal: 0).isEmpty)
    }

    func testAppliedKeepsDiscountIdForTraceability() {
        let discount = DiscountModel.percentage(10)
        let applied = DiscountCalculator.applied(for: [discount], subtotal: 200)

        XCTAssertEqual(applied.first?.discountId, discount.id,
                       "設定被刪除後仍要能追溯是哪一個折扣")
    }

    // MARK: - sanitized：寫入邊界的保護

    func testSanitizedLeavesValidSnapshotsUntouched() {
        let valid: [AppliedDiscount] = [
            .mock(type: .percentage, value: 10, amount: 20),
            .mock(type: .amount, value: 20, amount: 20)
        ]

        XCTAssertEqual(DiscountCalculator.sanitized(valid, subtotal: 200), valid)
    }

    func testSanitizedClampsRunningTotalAcrossMultipleDiscounts() {
        // 兩筆各 80，但小計只有 100 → 第一筆 80、第二筆只剩 20
        let dirty: [AppliedDiscount] = [
            .mock(type: .percentage, value: 80, amount: 80),
            .mock(type: .amount, value: 80, amount: 80)
        ]

        let clean = DiscountCalculator.sanitized(dirty, subtotal: 100)

        XCTAssertEqual(clean[0].amount, 80)
        XCTAssertEqual(clean[1].amount, 20)
        let sum = clean.reduce(Decimal(0)) { MoneyHelper.add($0, $1.amount) }
        XCTAssertEqual(sum, 100, "總折抵不可超過小計")
    }

    func testSanitizedClampsNegativeAmountToZero() {
        let dirty: [AppliedDiscount] = [.mock(type: .amount, value: -50, amount: -50)]

        XCTAssertEqual(DiscountCalculator.sanitized(dirty, subtotal: 200).first?.amount, 0)
    }

    func testSanitizedReturnsEmptyForZeroSubtotal() {
        let dirty: [AppliedDiscount] = [.mock(amount: 10)]
        XCTAssertTrue(DiscountCalculator.sanitized(dirty, subtotal: 0).isEmpty)
    }

    // MARK: - 編碼往返（3.1）

    func testAppliedDiscountRoundTripsThroughJSON() throws {
        let original: [AppliedDiscount] = [
            .mock(type: .percentage, value: Decimal(string: "12.5")!, amount: Decimal(string: "25.75")!),
            .mock(type: .amount, value: 20, amount: 20)
        ]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([AppliedDiscount].self, from: data)

        XCTAssertEqual(decoded, original, "Decimal 精度不可在往返中丟失")
    }

    func testTransactionWithoutDiscountDataDecodesToEmpty() {
        // 舊資料（appliedDiscountsData == nil）不可以 crash
        let transaction = TransactionModel.mock(appliedDiscounts: [])

        XCTAssertTrue(transaction.appliedDiscounts.isEmpty)
        XCTAssertEqual(DiscountCalculator.amount(for: transaction), 0)
        XCTAssertNil(DiscountCalculator.deductionText(for: transaction))
    }

    // MARK: - 顯示

    func testDeductionTextJoinsMultipleDiscounts() {
        let transaction = TransactionModel.mock(appliedDiscounts: [
            .mock(type: .percentage, value: 10, amount: 20),
            .mock(type: .amount, value: 20, amount: 20)
        ])

        XCTAssertEqual(DiscountCalculator.deductionText(for: transaction), "10% -20")
    }
}
