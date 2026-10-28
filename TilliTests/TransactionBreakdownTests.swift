//
//  TransactionBreakdownTests.swift
//  TilliTests
//
//  交易明細頁的還原規則（設計 §7、§7.0）：只讀交易快照，不讀場次設定。
//

import XCTest
@testable import Tilli

final class TransactionBreakdownTests: XCTestCase {

    // MARK: - Fixtures

    private let bundleId = UUID()
    private let comboId = UUID()
    private let productA = UUID()
    private let productB = UUID()

    /// 套餐「早午餐」：成員 40/60/20，份數 1，套餐差額 20 → 套餐價 100
    private func bundleMembers(servings: Int = 1) -> [SummaryItemModel] {
        let prices: [(String, Decimal, Decimal)] = [("鬆餅", 40, 7), ("拿鐵", 60, 10), ("沙拉", 20, 3)]
        return prices.map { name, price, discount in
            SummaryItemModel.mock(
                name: name,
                price: price,
                quantity: servings,
                bundleId: bundleId,
                bundleName: "早午餐",
                bundleDiscount: MoneyHelper.multiply(discount, Decimal(servings)),
                bundleKind: .fixed
            )
        }
    }

    /// 設計範例：套餐 100 + 珍奶 60 × 3（其中 2 杯含組合）+ 紅茶 60（含組合）= 340；
    /// 組合「任選 3 件」折 40；九折 −30；減額 −25 → 245
    private func designExampleTransaction() -> TransactionModel {
        let items = bundleMembers() + [
            .mock(productId: productA, name: "珍奶", price: 60, quantity: 2,
                  bundleId: comboId, bundleName: "任選 3 件", bundleDiscount: 27, bundleKind: .chooseAny),
            .mock(productId: productB, name: "紅茶", price: 60, quantity: 1,
                  bundleId: comboId, bundleName: "任選 3 件", bundleDiscount: 13, bundleKind: .chooseAny),
            .mock(productId: productA, name: "珍奶", price: 60, quantity: 1)
        ]
        return .mock(
            items: items,
            totalAmount: 245,
            appliedDiscounts: [
                .mock(type: .percentage, value: 10, amount: 30),
                .mock(type: .amount, value: 25, amount: 25)
            ]
        )
    }

    // MARK: - 套餐

    func testBundleRowShowsBundlePriceFromSnapshot() {
        let transaction = TransactionModel.mock(items: bundleMembers(), totalAmount: 100)

        let breakdown = TransactionBreakdown(transaction: transaction)

        XCTAssertEqual(breakdown.rows, [
            .bundle(bundleId: bundleId, name: "早午餐", quantity: 1, lineTotal: 100,
                    memberNames: ["鬆餅", "拿鐵", "沙拉"])
        ])
        XCTAssertEqual(breakdown.subtotal, 100)
        XCTAssertTrue(breakdown.comboLines.isEmpty)
    }

    func testBundleRowQuantityIsServingsAndLineTotalCoversAllServings() {
        let transaction = TransactionModel.mock(items: bundleMembers(servings: 2), totalAmount: 200)

        let breakdown = TransactionBreakdown(transaction: transaction)

        guard case let .bundle(_, _, quantity, lineTotal, _) = breakdown.rows.first else {
            return XCTFail("應該是一列套餐")
        }
        XCTAssertEqual(quantity, 2)
        XCTAssertEqual(lineTotal, 200)
    }

    // MARK: - 恆等式

    func testSubtotalMinusCombosMinusDiscountsEqualsTotal() {
        let breakdown = TransactionBreakdown(transaction: designExampleTransaction())

        XCTAssertEqual(breakdown.subtotal, 340)
        XCTAssertEqual(breakdown.comboLines, [.init(bundleId: comboId, name: "任選 3 件", amount: 40)])
        XCTAssertEqual(breakdown.discounts.map(\.amount), [30, 25])
        XCTAssertEqual(breakdown.total, 245)

        let deductions = MoneyHelper.add(
            MoneyHelper.sum(breakdown.comboLines.map(\.amount)),
            MoneyHelper.sum(breakdown.discounts.map(\.amount))
        )
        XCTAssertEqual(MoneyHelper.subtract(breakdown.subtotal, deductions), breakdown.total)
        XCTAssertEqual(breakdown.savings, 95)
    }

    // MARK: - 項數

    func testItemCountCountsBundleAsOne() {
        let breakdown = TransactionBreakdown(transaction: designExampleTransaction())

        // 套餐 1 + 珍奶 1 + 紅茶 1
        XCTAssertEqual(breakdown.itemCount, 3)
    }

    // MARK: - 拆列合併

    func testSplitRowsOfSameProductAreMergedForDisplay() {
        let breakdown = TransactionBreakdown(transaction: designExampleTransaction())

        let productRows: [(SummaryItemModel, Bool)] = breakdown.rows.compactMap {
            if case let .product(item, isInCombo) = $0 { return (item, isInCombo) }
            return nil
        }
        XCTAssertEqual(productRows.map(\.0.name), ["珍奶", "紅茶"])
        XCTAssertEqual(productRows.map(\.0.quantity), [3, 1])
        XCTAssertEqual(productRows.map(\.0.total), [180, 60])
        XCTAssertEqual(productRows.map(\.1), [true, true])
    }

    // MARK: - 舊資料與已刪除套餐

    func testLegacyTransactionWithoutBundleFieldsStillReconciles() throws {
        // 第 5 批之前的 itemsData：沒有 bundleKind / bundleDiscount
        let legacyJSON = """
        [{"id":"\(UUID().uuidString)","productId":"\(productA.uuidString)","name":"珍奶","price":60,
          "categoryId":"\(UUID().uuidString)","category":"飲料","quantity":2,"timestamp":0,"allocatedDiscount":12}]
        """
        let items = try JSONDecoder().decode([SummaryItemModel].self, from: Data(legacyJSON.utf8))
        let transaction = TransactionModel.mock(
            items: items,
            totalAmount: 108,
            appliedDiscounts: [.mock(type: .percentage, value: 10, amount: 12)]
        )

        let breakdown = TransactionBreakdown(transaction: transaction)

        XCTAssertEqual(breakdown.rows.count, 1)
        guard case let .product(item, isInCombo) = breakdown.rows[0] else {
            return XCTFail("舊交易應顯示成商品列")
        }
        XCTAssertEqual(item.quantity, 2)
        XCTAssertFalse(isInCombo)
        XCTAssertEqual(breakdown.subtotal, 120)
        XCTAssertTrue(breakdown.comboLines.isEmpty)
        XCTAssertEqual(
            MoneyHelper.subtract(breakdown.subtotal, MoneyHelper.sum(breakdown.discounts.map(\.amount))),
            breakdown.total
        )
    }

    func testDeletedBundleStillRendersFromSnapshot() {
        // 只靠交易快照（名稱、bundleKind、bundleDiscount），不需要場次裡還有這個套餐或組合
        let breakdown = TransactionBreakdown(transaction: designExampleTransaction())

        XCTAssertEqual(breakdown.rows.first, .bundle(
            bundleId: bundleId, name: "早午餐", quantity: 1, lineTotal: 100,
            memberNames: ["鬆餅", "拿鐵", "沙拉"]
        ))
        XCTAssertEqual(breakdown.comboLines.first?.name, "任選 3 件")
    }
}
