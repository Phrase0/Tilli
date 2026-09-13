//
//  MoneyAggregationTests.swift
//  TilliTests
//
//  Created by Peiyun on 2026/9/13.
//
//  對應 FEATURE_PLAN_V1.md 第 1 批的 1.8（A4）與測試清單 U5。
//

import XCTest
@testable import Tilli

final class MoneyAggregationTests: XCTestCase {

    // MARK: - [SummaryItemModel].subtotal

    func testEmptyItemsSubtotalIsZero() {
        XCTAssertEqual([SummaryItemModel]().subtotal, 0)
    }

    func testItemsSubtotalMultipliesPriceByQuantity() {
        let items = [
            SummaryItemModel.mock(price: 100, quantity: 2),   // 200
            SummaryItemModel.mock(price: 50, quantity: 3)     // 150
        ]
        XCTAssertEqual(items.subtotal, 350)
    }

    func testItemsSubtotalKeepsDecimalPrecision() {
        let items = [
            SummaryItemModel.mock(price: Decimal(string: "0.1")!, quantity: 1),
            SummaryItemModel.mock(price: Decimal(string: "0.2")!, quantity: 1)
        ]
        XCTAssertEqual(items.subtotal, Decimal(string: "0.3")!,
                       "用 Decimal 累加不該出現浮點誤差")
    }

    func testTransactionSubtotalUsesSameImplementation() {
        let items = [
            SummaryItemModel.mock(price: 100, quantity: 2),
            SummaryItemModel.mock(price: 50, quantity: 3)
        ]
        let transaction = TransactionModel.mock(items: items)

        XCTAssertEqual(transaction.subtotal, items.subtotal)
    }

    // MARK: - [TransactionModel].summary / .total（A4／U5）

    func testEmptyTransactionsSummaryIsZero() {
        let summary = [TransactionModel]().summary
        XCTAssertEqual(summary.count, 0)
        XCTAssertEqual(summary.total, 0)
    }

    func testSummaryCountsTransactionsAndSumsTotalAmount() {
        let transactions = [
            TransactionModel.mock(totalAmount: 100),
            TransactionModel.mock(totalAmount: 250),
            TransactionModel.mock(totalAmount: 75)
        ]
        let summary = transactions.summary

        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.total, 425)
        XCTAssertEqual(summary.total, transactions.total)
    }

    /// ⭐ A4：場次列表與日曆頁原本一個用原生 `+`、一個用 `MoneyHelper.add`。
    /// 現在只有一份實作，這條確認它走的是 `MoneyHelper`，不是原生運算。
    func testTotalMatchesMoneyHelperAccumulation() {
        let amounts: [Decimal] = [
            Decimal(string: "19.99")!,
            Decimal(string: "0.01")!,
            Decimal(string: "123.456")!
        ]
        let transactions = amounts.map { TransactionModel.mock(totalAmount: $0) }

        let expected = amounts.reduce(Decimal(0)) { MoneyHelper.add($0, $1) }
        XCTAssertEqual(transactions.total, expected)
    }

    func testSummaryIgnoresItemsAndUsesTotalAmount() {
        // totalAmount 是折扣後的實收金額，不該用 items 反推
        let transaction = TransactionModel.mock(
            items: [.mock(price: 100, quantity: 2)],   // 小計 200
            totalAmount: 160                           // 折後 160
        )
        XCTAssertEqual([transaction].summary.total, 160)
        XCTAssertEqual(transaction.subtotal, 200)
    }
}
