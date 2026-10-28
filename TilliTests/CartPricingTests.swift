//
//  CartPricingTests.swift
//  TilliTests
//
//  購物車定價明細與結帳寫入的拆列／攤提。
//  數字取自 docs/superpowers/specs/2026-10-27-bundles-design.md §5.1、§5.5。
//

import XCTest
@testable import Tilli

final class CartPricingTests: XCTestCase {

    // MARK: - Fixture（設計 §5.5：小計 340）

    private let category = CategoryModel.mock(name: "甜點")

    private lazy var daifuku = product("大福", price: 40)
    private lazy var matcha = product("抹茶", price: 60)
    private lazy var redBean = product("紅豆", price: 20)
    private lazy var strawberry = product("草莓", price: 30)
    private lazy var mango = product("芒果", price: 60)

    /// 下午茶套餐：大福 40 + 抹茶 60 + 紅豆 20 = 120，賣 100（差額 20）
    private lazy var teaSet = BundleModel.fixedMock(
        name: "下午茶套餐", price: 100, productIds: [daifuku.id, matcha.id, redBean.id]
    )
    /// 草莓三個 50：3 × 30 = 90 → 50（差額 40）
    private lazy var strawberryCombo = BundleModel.comboMock(
        name: "草莓三個", price: 50, count: 3, productIds: [strawberry.id]
    )

    private func product(_ name: String, price: Decimal) -> ProductModel {
        ProductModel.mock(name: name, price: price, categoryId: category.id)
    }

    /// 套餐 1 + 草莓 4 + 芒果 2
    private var mockupCart: Cart {
        Cart(
            productQuantities: [strawberry.id: 4, mango.id: 2],
            bundleLines: [teaSet.id: line(for: teaSet, quantity: 1)]
        )
    }

    private func line(for bundle: BundleModel, quantity: Int) -> BundleCartLine {
        BundleCartLine(quantity: quantity, nameAtAdd: bundle.name, priceAtAdd: bundle.price, productIdsAtAdd: bundle.productIds)
    }

    private func price(
        _ cart: Cart,
        products: [ProductModel]? = nil,
        bundles: [BundleModel]? = nil,
        discounts: [DiscountModel] = []
    ) -> CartPricing {
        let products = products ?? [daifuku, matcha, redBean, strawberry, mango]
        let bundles = bundles ?? [teaSet, strawberryCombo]
        return CartPricing.price(
            cart: cart,
            products: Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) }),
            bundles: Dictionary(uniqueKeysWithValues: bundles.map { ($0.id, $0) }),
            categories: [category],
            selectedDiscounts: discounts
        )
    }

    private func checkout(_ pricing: CartPricing, currency: String = "TWD") -> [SummaryItemModel] {
        let (items, deductions) = pricing.summaryItems(categoryName: { _ in "甜點" }, timestamp: Date())
        return RevenueAllocator.allocate(items, bundles: deductions, discounts: pricing.discounts, currency: currency)
    }

    private func sum(_ values: [Decimal]) -> Decimal {
        MoneyHelper.sum(values)
    }

    // MARK: - 定價明細

    func testSubtotalCountsBundleAtBundlePrice() {
        let pricing = price(mockupCart)

        // 套餐 100 + 草莓 4 × 30 + 芒果 2 × 60
        XCTAssertEqual(pricing.subtotal, 340)
        XCTAssertEqual(pricing.bundleRows.map(\.lineTotal), [100])
        XCTAssertEqual(pricing.combos.map(\.deduction), [40])
    }

    func testComboThenPercentageThenAmountGives245() {
        let pricing = price(mockupCart, discounts: [.percentage(10), .amount(25)])

        // 340 − 40（組合）= 300 → 10% −30 → −25 → 245
        XCTAssertEqual(pricing.discounts.map(\.amount), [30, 25])
        XCTAssertEqual(pricing.total, 245)
        XCTAssertEqual(pricing.savings, 95)
    }

    func testCancellingComboRecomputesDiscountsTo281() {
        var cart = mockupCart
        cart.cancelledComboIds = [strawberryCombo.id]

        let pricing = price(cart, discounts: [.percentage(10), .amount(25)])

        XCTAssertTrue(pricing.combos.isEmpty)
        XCTAssertEqual(pricing.discounts.map(\.amount), [34, 25])
        XCTAssertEqual(pricing.total, 281)
        XCTAssertTrue(pricing.productRows.allSatisfy { !$0.isInCombo })
    }

    func testProductRowIsMarkedInComboWhenCovered() {
        let pricing = price(mockupCart)

        let rows = Dictionary(uniqueKeysWithValues: pricing.productRows.map { ($0.product.id, $0) })
        XCTAssertEqual(rows[strawberry.id]?.isInCombo, true)
        XCTAssertEqual(rows[strawberry.id]?.lineTotal, 120)
        XCTAssertEqual(rows[mango.id]?.isInCombo, false)
    }

    func testBundleLineMissingFromBundlesIsSkipped() {
        let pricing = price(mockupCart, bundles: [strawberryCombo])

        XCTAssertTrue(pricing.bundleRows.isEmpty)
        XCTAssertEqual(pricing.subtotal, 240)
    }

    func testBundleWithMissingMemberIsSkippedAndStillReconciles() {
        // 抹茶不在 products 裡 → 下午茶套餐整行略過
        let pricing = price(
            mockupCart,
            products: [daifuku, redBean, strawberry, mango],
            discounts: [.percentage(10), .amount(25)]
        )

        XCTAssertTrue(pricing.bundleRows.isEmpty)
        XCTAssertEqual(pricing.subtotal, 240)

        let items = checkout(pricing)
        XCTAssertFalse(items.contains { $0.bundleId == teaSet.id })
        XCTAssertEqual(sum(items.map(\.actualRevenue)), pricing.total)
        XCTAssertTrue(items.allSatisfy { $0.bundleDiscount >= 0 && $0.actualRevenue >= 0 })
    }

    // MARK: - 結帳寫入

    func testSummaryItemsReconcileToTotal() {
        let pricing = price(mockupCart, discounts: [.percentage(10), .amount(25)])

        let items = checkout(pricing)

        XCTAssertEqual(sum(items.map(\.actualRevenue)), pricing.total)
        XCTAssertEqual(sum(items.map(\.bundleDiscount)), 60)
        XCTAssertTrue(items.allSatisfy { $0.actualRevenue >= 0 })
    }

    func testBundleExpandsToMembersTaggedFixed() {
        var cart = mockupCart
        cart.bundleLines[teaSet.id]?.quantity = 2
        let pricing = price(cart)

        let (items, deductions) = pricing.summaryItems(categoryName: { _ in "甜點" }, timestamp: Date())

        let members = items.filter { $0.bundleId == teaSet.id }
        XCTAssertEqual(Set(members.map(\.productId)), [daifuku.id, matcha.id, redBean.id])
        XCTAssertTrue(members.allSatisfy { $0.quantity == 2 && $0.bundleKind == .fixed && $0.bundleName == "下午茶套餐" })
        // (120 − 100) × 2
        XCTAssertEqual(deductions.first { $0.bundleId == teaSet.id }?.amount, 40)
        XCTAssertEqual(deductions.first { $0.bundleId == strawberryCombo.id }?.amount, 40)
    }

    func testPartiallyCoveredProductIsSplitIntoTwoRows() {
        let pricing = price(mockupCart)

        let (items, _) = pricing.summaryItems(categoryName: { _ in "甜點" }, timestamp: Date())

        let strawberryRows = items.filter { $0.productId == strawberry.id }
        XCTAssertEqual(strawberryRows.count, 2)
        let covered = strawberryRows.first { $0.bundleKind == .chooseAny }
        XCTAssertEqual(covered?.quantity, 3)
        XCTAssertEqual(covered?.bundleId, strawberryCombo.id)
        XCTAssertEqual(covered?.bundleName, "草莓三個")
        let uncovered = strawberryRows.first { $0.bundleKind == nil }
        XCTAssertEqual(uncovered?.quantity, 1)
        XCTAssertNil(uncovered?.bundleId)
    }

    func testProductCoveredByTwoCombosGetsOneRowPerCombo() {
        // 五個 100（20/件）先套用，剩 2 個再被兩個 50（25/件）涵蓋，最後 1 個單點
        let five = BundleModel.comboMock(name: "草莓五個", price: 100, count: 5, productIds: [strawberry.id])
        let two = BundleModel.comboMock(name: "草莓兩個", price: 50, count: 2, productIds: [strawberry.id])
        let cart = Cart(productQuantities: [strawberry.id: 8])
        let pricing = price(cart, bundles: [five, two], discounts: [.percentage(10)])

        let (items, deductions) = pricing.summaryItems(categoryName: { _ in "甜點" }, timestamp: Date())

        XCTAssertEqual(items.map(\.quantity), [5, 2, 1])
        XCTAssertEqual(items.map(\.bundleId), [five.id, two.id, nil])
        XCTAssertEqual(deductions.map(\.amount), [50, 10])

        let allocated = RevenueAllocator.allocate(items, bundles: deductions, discounts: pricing.discounts, currency: "TWD")
        XCTAssertEqual(sum(allocated.map(\.actualRevenue)), pricing.total)
        XCTAssertEqual(sum(allocated.map(\.bundleDiscount)), 60)
    }

    func testUSDBundleAndComboStillReconcileToTotal() {
        let a = product("A", price: Decimal(string: "3.50")!)
        let b = product("B", price: Decimal(string: "2.25")!)
        // 成員 A、B、A、B = 11.50 → 9.99
        let set = BundleModel.fixedMock(name: "Set", price: Decimal(string: "9.99")!, productIds: [a.id, b.id, a.id, b.id])
        // 任三個 6.00（≤ 3 × 2.25）
        let combo = BundleModel.comboMock(name: "Any 3", price: Decimal(string: "6.00")!, count: 3, productIds: [a.id, b.id])
        let cart = Cart(
            productQuantities: [a.id: 2, b.id: 2],
            bundleLines: [set.id: line(for: set, quantity: 1)]
        )

        let pricing = price(cart, products: [a, b], bundles: [set, combo], discounts: [.percentage(10), .amount(1)])
        let items = checkout(pricing, currency: "USD")

        XCTAssertEqual(pricing.subtotal, Decimal(string: "21.49")!)
        XCTAssertEqual(sum(items.map(\.actualRevenue)), pricing.total)
        // 套餐差額 1.51 + 組合差額（3.50 + 3.50 + 2.25 − 6.00 = 3.25）
        XCTAssertEqual(sum(items.map(\.bundleDiscount)), Decimal(string: "4.76")!)
        // 重複成員合併成一列，數量 = 出現次數 × 份數
        XCTAssertEqual(items.filter { $0.bundleId == set.id }.map(\.quantity), [2, 2])
        XCTAssertTrue(items.allSatisfy { $0.actualRevenue >= 0 })
    }
}
