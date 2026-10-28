import XCTest
@testable import Tilli

final class BundleValidatorTests: XCTestCase {
    private let daifuku = ProductModel.mock(name: "大福", price: 40)
    private let matcha = ProductModel.mock(name: "抹茶", price: 60)
    private let redBean = ProductModel.mock(name: "紅豆", price: 20)

    private var products: [UUID: ProductModel] {
        Dictionary(uniqueKeysWithValues: [daifuku, matcha, redBean].map { ($0.id, $0) })
    }

    private func fixed(price: Decimal, name: String = "下午茶套餐") -> BundleModel {
        .fixedMock(name: name, price: price, productIds: [daifuku.id, matcha.id, redBean.id])
    }

    private func combo(price: Decimal, count: Int = 3, ids: [UUID]? = nil) -> BundleModel {
        .comboMock(price: price, count: count, productIds: ids ?? [daifuku.id, matcha.id])
    }

    func testFixedLimitIsSumOfMemberPrices() {
        XCTAssertEqual(BundleValidator.priceLimit(for: fixed(price: 100), products: products), 120)
    }

    func testChooseAnyLimitIsCountTimesCheapestCandidate() {
        XCTAssertEqual(BundleValidator.priceLimit(for: combo(price: 100), products: products), 120)
    }

    func testFixedPriceAboveMemberTotalIsRejected() {
        let errors = BundleValidator.validate(fixed(price: 121), existing: [], products: products)
        XCTAssertEqual(errors, [.priceAboveLimit(limit: 120)])
    }

    func testPriceEqualToLimitIsAllowedButFlaggedNoDiscount() {
        let bundle = fixed(price: 120)
        XCTAssertEqual(BundleValidator.validate(bundle, existing: [], products: products), [])
        XCTAssertTrue(BundleValidator.hasNoDiscount(bundle, products: products))
        XCTAssertFalse(BundleValidator.hasNoDiscount(fixed(price: 100), products: products))
    }

    func testComboPriceAboveCountTimesCheapestIsRejected() {
        let errors = BundleValidator.validate(combo(price: 121), existing: [], products: products)
        XCTAssertEqual(errors, [.priceAboveLimit(limit: 120)])
    }

    func testSingleCandidateComboIsValid() {
        let bundle = combo(price: 100, ids: [daifuku.id])
        XCTAssertEqual(BundleValidator.validate(bundle, existing: [], products: products), [])
    }

    func testDuplicateNameIsRejectedIgnoringSelfAndWhitespace() {
        let existing = fixed(price: 100)
        let other = fixed(price: 100, name: " 下午茶套餐 ")
        XCTAssertEqual(BundleValidator.validate(other, existing: [existing], products: products), [.duplicateName])
        XCTAssertEqual(BundleValidator.validate(existing, existing: [existing], products: products), [])
    }

    func testFixedNeedsTwoMembersAndComboNeedsCountTwo() {
        let one = BundleModel.fixedMock(price: 30, productIds: [daifuku.id])
        XCTAssertEqual(BundleValidator.validate(one, existing: [], products: products), [.tooFewMembers])
        XCTAssertEqual(BundleValidator.validate(combo(price: 30, count: 1), existing: [], products: products), [.countTooSmall])
        let none = combo(price: 50, ids: [])
        XCTAssertEqual(BundleValidator.validate(none, existing: [], products: products), [.noCandidates])
    }

    func testEmptyNameAndNonPositivePriceAreRejected() {
        let bundle = fixed(price: 0, name: "  ")
        XCTAssertEqual(BundleValidator.validate(bundle, existing: [], products: products), [.emptyName, .nonPositivePrice])
    }

    func testUnknownProductIsRejected() {
        let bundle = BundleModel.fixedMock(price: 50, productIds: [daifuku.id, UUID()])
        XCTAssertEqual(BundleValidator.validate(bundle, existing: [], products: products), [.unknownProduct])
        XCTAssertNil(BundleValidator.priceLimit(for: bundle, products: products))
    }

    func testDisabledProductsStillValidate() {
        var disabled = matcha
        disabled.isDisabled = true
        var map = products
        map[disabled.id] = disabled
        XCTAssertEqual(BundleValidator.validate(fixed(price: 100), existing: [], products: map), [])
    }

    func testPriceChangeThatBreaksFixedBundleIsReported() {
        let bundle = fixed(price: 100)   // 40 + 60 + 20 = 120
        let list = [bundle]
        XCTAssertEqual(BundleValidator.bundlesViolated(byPrice: 39, of: matcha.id, bundles: list, products: products), [bundle])
        XCTAssertEqual(BundleValidator.bundlesViolated(byPrice: 40, of: matcha.id, bundles: list, products: products), [])
    }

    func testPriceChangeThatBreaksComboIsReported() {
        let bundle = combo(price: 100, ids: [daifuku.id])
        XCTAssertEqual(BundleValidator.bundlesViolated(byPrice: 33, of: daifuku.id, bundles: [bundle], products: products), [bundle])
        XCTAssertEqual(BundleValidator.bundlesViolated(byPrice: 34, of: daifuku.id, bundles: [bundle], products: products), [])
    }

    func testBundlesReferencingProductFindsMembersAndCandidates() {
        let a = fixed(price: 100)
        let b = combo(price: 100, ids: [matcha.id])
        let c = combo(price: 100, ids: [redBean.id])
        let found = BundleValidator.bundles(referencing: matcha.id, in: [a, b, c])
        XCTAssertEqual(found.map(\.id), [a.id, b.id])
    }
}
