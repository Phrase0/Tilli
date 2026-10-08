//
//  RevenueAllocatorTests.swift
//  TilliTests
//
//  Created by Peiyun on 2026/10/8.
//
//  對應 FEATURE_PLAN_V1.md §7.3 與 §11 第 4 批的 4.1／4.2。
//  這批是金額正確性的關鍵 —— 捨入處理錯了會讓兩張報表對不起來（A6／R2）。
//

import XCTest
@testable import Tilli

final class RevenueAllocatorTests: XCTestCase {

    // MARK: - Helpers

    /// 走跟 POS 結帳一模一樣的路徑：場次折扣設定 → 快照 → 總額 → 攤提
    private func checkout(
        _ items: [SummaryItemModel],
        discounts: [DiscountModel],
        currency: String = "TWD"
    ) -> (items: [SummaryItemModel], totalAmount: Decimal) {
        let subtotal = items.subtotal
        let applied = DiscountCalculator.applied(for: discounts, subtotal: subtotal)
        let total = DiscountCalculator.total(subtotal: subtotal, discounts: discounts)
        let allocated = RevenueAllocator.allocate(items, discounts: applied, currency: currency)
        return (allocated, total)
    }

    private func revenueSum(_ items: [SummaryItemModel]) -> Decimal {
        items.reduce(Decimal(0)) { MoneyHelper.add($0, $1.actualRevenue) }
    }

    // MARK: - ⭐ 恆等式（R2）

    /// ⭐ A6 的定義：Σ actualRevenue == totalAmount，對任意輸入都成立。
    /// 兩張報表口徑相等不是靠巧合，而是這條恆等式。
    func testRevenueSumEqualsTotalForRandomInputs() {
        var rng = SeededGenerator(seed: 20261008)

        for iteration in 0..<1000 {
            let currency = iteration.isMultiple(of: 2) ? "TWD" : "USD"
            let itemCount = Int.random(in: 1...10, using: &rng)
            let items = (0..<itemCount).map { _ -> SummaryItemModel in
                // TWD 整數單價、USD 兩位小數；偶爾出現 0 元贈品
                let cents = Int.random(in: 0...50_000, using: &rng)
                let price: Decimal = currency == "TWD"
                    ? Decimal(cents / 100)
                    : MoneyHelper.divide(Decimal(cents), 100)
                return .mock(price: price, quantity: Int.random(in: 1...5, using: &rng))
            }

            var discounts: [DiscountModel] = []
            if Bool.random(using: &rng) {
                discounts.append(.percentage(Decimal(Int.random(in: 1...100, using: &rng))))
            }
            if Bool.random(using: &rng) {
                discounts.append(.amount(Decimal(Int.random(in: 1...3_000, using: &rng))))
            }

            let result = checkout(items, discounts: discounts, currency: currency)

            XCTAssertEqual(revenueSum(result.items), result.totalAmount,
                           "iteration \(iteration): Σ actualRevenue ≠ totalAmount")
            for item in result.items {
                XCTAssertGreaterThanOrEqual(item.actualRevenue, 0, "iteration \(iteration): 負營收")
                XCTAssertGreaterThanOrEqual(item.allocatedDiscount, 0, "iteration \(iteration): 負折扣")
            }
        }
    }

    // MARK: - 攤提順序（§7.3）

    /// ② 套餐差額只攤給成員，③ 整筆折扣再按「② 之後」的金額攤給所有項目。
    /// 順序對調（整筆折扣按原價攤）會得到不同的數字 —— 這個測試要能抓到。
    func testBundleDeductionAllocatedBeforeTransactionDiscount() {
        let bundleId = UUID()
        let items: [SummaryItemModel] = [
            .mock(price: 100, bundleId: bundleId),   // 套餐成員
            .mock(price: 100, bundleId: bundleId),   // 套餐成員
            .mock(price: 100)                        // 單買
        ]
        // 套餐 200 → 150，差額 50；剩 250 再打九折，折 25
        let result = RevenueAllocator.allocate(
            items,
            bundles: [.init(bundleId: bundleId, amount: 50)],
            discounts: [.mock(type: .percentage, value: 10, amount: 25)],
            currency: "TWD"
        )

        // 成員：100 − 25（套餐）= 75，再按 75/250 分 25 → 7.5 → 捨去成 7
        // 單買：100，按 100/250 分 25 → 10
        // 餘額 1 給剩餘空間最大的單買那項
        XCTAssertEqual(result.map(\.allocatedDiscount), [32, 32, 11])
        XCTAssertEqual(revenueSum(result), 225)

        // 對照：若整筆折扣按原價攤（順序錯），三項會各分到相同的折扣
        XCTAssertNotEqual(result[0].allocatedDiscount - 25, result[2].allocatedDiscount)
    }

    func testPercentageThenAmountAllocatedSequentially() {
        let items: [SummaryItemModel] = [.mock(price: 300), .mock(price: 100)]
        // 400 九折 → 折 40，剩 360；再 −36
        let result = checkout(items, discounts: [.percentage(10), .amount(36)])

        XCTAssertEqual(result.totalAmount, 324)
        XCTAssertEqual(result.items.map(\.allocatedDiscount), [57, 19])
        XCTAssertEqual(result.items.map(\.actualRevenue), [243, 81])
    }

    // MARK: - 捨入差額

    /// 小計 100 分成 3 項（各 33.33…）配 10% 折扣 → 加總剛好等於總額。
    func testRoundingRemainderKeepsExactSum() {
        let items: [SummaryItemModel] = [
            .mock(price: Decimal(string: "33.34")!),
            .mock(price: Decimal(string: "33.33")!),
            .mock(price: Decimal(string: "33.33")!)
        ]
        let result = checkout(items, discounts: [.percentage(10)], currency: "USD")

        XCTAssertEqual(result.totalAmount, 90)
        XCTAssertEqual(revenueSum(result.items), 90)
        // 每一項的折扣都是幣別最小單位的整數倍（不會出現 3.3333… 這種殘渣）
        for item in result.items {
            XCTAssertEqual(MoneyHelper.roundDown(item.allocatedDiscount, scale: 2), item.allocatedDiscount)
        }
    }

    /// ⭐ 原計畫「最後一項吃掉差額」在最後一項是贈品時會吃出負數。
    /// 改成由剩餘空間最大的那一項吃 —— 贈品永遠不會分到折扣。
    func testRemainderNeverGoesToZeroPriceItem() {
        let items: [SummaryItemModel] = [
            .mock(price: 10),
            .mock(price: 10),
            .mock(price: 10),
            .mock(price: 0)   // 贈品排在最後
        ]
        let result = checkout(items, discounts: [.amount(10)])

        XCTAssertEqual(result.items[3].allocatedDiscount, 0)
        XCTAssertEqual(result.items[3].actualRevenue, 0)
        XCTAssertEqual(revenueSum(result.items), 20)
        XCTAssertTrue(result.items.allSatisfy { $0.actualRevenue >= 0 })
    }

    /// TWD 沒有小數，但打折後的總額可能有（33 打九折 = 29.7）。
    /// 小數部分也要攤進去，加總才會等於流水帳的 totalAmount。
    func testFractionalTotalInZeroDecimalCurrency() {
        let items: [SummaryItemModel] = [.mock(price: 11), .mock(price: 22)]
        let result = checkout(items, discounts: [.percentage(10)])

        XCTAssertEqual(result.totalAmount, Decimal(string: "29.7")!)
        XCTAssertEqual(revenueSum(result.items), Decimal(string: "29.7")!)
    }

    // MARK: - 邊界

    func testSingleItemTakesWholeDiscount() {
        let result = checkout([.mock(price: 150, quantity: 2)], discounts: [.percentage(20), .amount(15)])

        XCTAssertEqual(result.items[0].allocatedDiscount, 75)
        XCTAssertEqual(result.items[0].actualRevenue, result.totalAmount)
    }

    func testNoDiscountLeavesRevenueEqualToOriginal() {
        let items: [SummaryItemModel] = [.mock(price: 120, quantity: 3), .mock(price: 45)]
        let result = checkout(items, discounts: [])

        for item in result.items {
            XCTAssertEqual(item.allocatedDiscount, 0)
            XCTAssertEqual(item.actualRevenue, item.total)
        }
    }

    /// 折扣 clamp 到等於小計 → 全部歸零，沒有任何一項是負數
    func testDiscountEqualToSubtotalZeroesEveryItem() {
        let items: [SummaryItemModel] = [.mock(price: 33), .mock(price: 34), .mock(price: 0)]
        let result = checkout(items, discounts: [.amount(500)])

        XCTAssertEqual(result.totalAmount, 0)
        XCTAssertEqual(result.items.map(\.actualRevenue), [0, 0, 0])
        XCTAssertEqual(result.items.map(\.allocatedDiscount), [33, 34, 0])
    }

    /// 理論上不該存在，但不可以除以零或產生 NaN
    func testZeroQuantityAndAllZeroPricesDoNotCrash() {
        let zeroQty = RevenueAllocator.allocate(
            [.mock(price: 100, quantity: 0)],
            discounts: [.mock(amount: 10)],
            currency: "TWD"
        )
        XCTAssertEqual(zeroQty[0].allocatedDiscount, 0)

        let allFree = checkout([.mock(price: 0), .mock(price: 0)], discounts: [.percentage(50)])
        XCTAssertEqual(allFree.items.map(\.allocatedDiscount), [0, 0])
    }

    /// 寫入前的折扣若超過可攤金額（呼叫端算錯），攤提仍不會讓任何一項變負數
    func testOversizedDiscountIsClampedPerItem() {
        let result = RevenueAllocator.allocate(
            [.mock(price: 10), .mock(price: 20)],
            discounts: [.mock(amount: 999)],
            currency: "TWD"
        )
        XCTAssertEqual(result.map(\.actualRevenue), [0, 0])
    }

    // MARK: - SummaryItemModel 新欄位（4.1）

    func testNewFieldsSurviveJSONRoundTrip() throws {
        var item = SummaryItemModel.mock(price: Decimal(string: "33.33")!, quantity: 3, bundleId: UUID(), bundleName: "早餐組")
        item.allocatedDiscount = Decimal(string: "9.99")!

        let decoded = try JSONDecoder().decode(SummaryItemModel.self, from: JSONEncoder().encode(item))

        XCTAssertEqual(decoded, item)
        XCTAssertEqual(decoded.actualRevenue, Decimal(string: "90")!)
    }

    /// 第 4 批之前寫入的 itemsData 沒有新欄位 → 解碼成「沒有攤提」，不 crash
    func testLegacyItemWithoutNewFieldsDecodes() throws {
        let legacy = """
        {"id":"\(UUID())","productId":"\(UUID())","name":"大福","price":50,
         "categoryId":"\(UUID())","category":"甜點","quantity":2,"timestamp":0}
        """
        let decoded = try JSONDecoder().decode(SummaryItemModel.self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded.allocatedDiscount, 0)
        XCTAssertEqual(decoded.actualRevenue, 100)
        XCTAssertNil(decoded.bundleId)
        XCTAssertNil(decoded.bundleName)
    }
}

// MARK: - 可重現的亂數

/// 固定 seed 的亂數產生器 —— 隨機測試失敗時要能重現同一組輸入（SplitMix64）
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
