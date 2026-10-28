//
//  ComboApplierTests.swift
//  TilliTests
//

import XCTest
@testable import Tilli

final class ComboApplierTests: XCTestCase {

    private let category = CategoryModel.mock(name: "大福")

    private func product(_ name: String, price: Decimal = 40, isDisabled: Bool = false) -> ProductModel {
        ProductModel.mock(name: name, price: price, categoryId: category.id, isDisabled: isDisabled)
    }

    private func apply(_ cart: Cart, _ combos: [BundleModel], _ products: [ProductModel]) -> [ComboApplication] {
        ComboApplier.apply(
            cart: cart,
            combos: combos,
            products: Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) }),
            categories: [category]
        )
    }

    func testThreeForHundredAppliesTwiceToSixUnits() {
        let strawberry = product("草莓"), mango = product("芒果")
        let combo = BundleModel.comboMock(price: 100, count: 3, productIds: [strawberry.id, mango.id])
        let cart = Cart(productQuantities: [strawberry.id: 4, mango.id: 2])

        let result = apply(cart, [combo], [strawberry, mango])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].groupCount, 2)
        XCTAssertEqual(result[0].deduction, 40)
        XCTAssertEqual(result[0].coveredQuantities.values.reduce(0, +), 6)
    }

    func testRemainderBelowCountStaysAtOriginalPrice() {
        let strawberry = product("草莓")
        let combo = BundleModel.comboMock(price: 100, count: 3, productIds: [strawberry.id])
        let cart = Cart(productQuantities: [strawberry.id: 5])

        let result = apply(cart, [combo], [strawberry])

        XCTAssertEqual(result[0].groupCount, 1)
        XCTAssertEqual(result[0].coveredQuantities[strawberry.id], 3)
    }

    func testLowerAveragePriceComboAppliesFirst() {
        let a = product("草莓")
        let three = BundleModel.comboMock(name: "三個", price: 100, count: 3, productIds: [a.id])
        let five = BundleModel.comboMock(name: "五個", price: 150, count: 5, productIds: [a.id])
        let cart = Cart(productQuantities: [a.id: 5])

        let result = apply(cart, [three, five], [a])

        XCTAssertEqual(result.map(\.bundleId), [five.id])
        XCTAssertEqual(result[0].deduction, 50)
    }

    func testTieOnAveragePriceAppliesLargerCountFirst() {
        let a = product("草莓")
        let three = BundleModel.comboMock(name: "三個", price: 90, count: 3, productIds: [a.id])
        let six = BundleModel.comboMock(name: "六個", price: 180, count: 6, productIds: [a.id])
        let cart = Cart(productQuantities: [a.id: 6])

        let result = apply(cart, [three, six], [a])

        XCTAssertEqual(result.map(\.bundleId), [six.id])
    }

    func testHighestPricedUnitsAreGroupedFirst() {
        let pricey = product("貴", price: 60), cheap = product("便宜", price: 40)
        let combo = BundleModel.comboMock(price: 100, count: 3, productIds: [pricey.id, cheap.id])
        let cart = Cart(productQuantities: [pricey.id: 1, cheap.id: 3])

        let result = apply(cart, [combo], [pricey, cheap])

        XCTAssertEqual(result[0].coveredQuantities[pricey.id], 1)
        XCTAssertEqual(result[0].coveredQuantities[cheap.id], 2)
        XCTAssertEqual(result[0].deduction, 40)
    }

    func testCancelledComboIsSkippedAndUnitsGoToNextCombo() {
        let a = product("草莓")
        let three = BundleModel.comboMock(price: 100, count: 3, productIds: [a.id])
        let five = BundleModel.comboMock(price: 150, count: 5, productIds: [a.id])
        let cart = Cart(productQuantities: [a.id: 5], cancelledComboIds: [five.id])

        let result = apply(cart, [three, five], [a])

        XCTAssertEqual(result.map(\.bundleId), [three.id])
        XCTAssertEqual(result[0].groupCount, 1)
    }

    func testDisabledCandidateDoesNotCount() {
        let on = product("草莓"), off = product("芒果", isDisabled: true)
        let combo = BundleModel.comboMock(price: 100, count: 3, productIds: [on.id, off.id])
        let cart = Cart(productQuantities: [on.id: 2, off.id: 1])

        XCTAssertTrue(apply(cart, [combo], [on, off]).isEmpty)
    }

    func testDisabledComboIsIgnored() {
        let a = product("草莓")
        var combo = BundleModel.comboMock(price: 100, count: 3, productIds: [a.id])
        combo.isDisabled = true
        let cart = Cart(productQuantities: [a.id: 3])

        XCTAssertTrue(apply(cart, [combo], [a]).isEmpty)
    }

    func testBundleMembersInCartDoNotCountTowardCombo() {
        let a = product("草莓")
        let combo = BundleModel.comboMock(price: 100, count: 3, productIds: [a.id])
        let line = BundleCartLine(quantity: 1, nameAtAdd: "套餐", priceAtAdd: 50, productIdsAtAdd: [a.id])
        let cart = Cart(productQuantities: [a.id: 2], bundleLines: [UUID(): line])

        XCTAssertTrue(apply(cart, [combo], [a]).isEmpty)
    }
}
