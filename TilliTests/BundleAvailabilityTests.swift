import XCTest
@testable import Tilli

final class BundleAvailabilityTests: XCTestCase {

    private let category = CategoryModel.mock()

    private func product(_ name: String, stock: Int, disabled: Bool = false, categoryId: UUID? = nil) -> ProductModel {
        ProductModel.mock(name: name, stock: stock, categoryId: categoryId ?? category.id, isDisabled: disabled)
    }

    private func index(_ ps: [ProductModel]) -> [UUID: ProductModel] {
        Dictionary(uniqueKeysWithValues: ps.map { ($0.id, $0) })
    }

    private func line(_ bundle: BundleModel, qty: Int = 1) -> BundleCartLine {
        BundleCartLine(quantity: qty, nameAtAdd: bundle.name, priceAtAdd: bundle.price, productIdsAtAdd: bundle.productIds)
    }

    func testFixedBundlePortionsLimitedByScarcestMember() {
        let a = product("大福", stock: 1), b = product("抹茶", stock: 5), c = product("紅豆", stock: 5)
        let bundle = BundleModel.fixedMock(productIds: [a.id, b.id, c.id])
        let r = BundleAvailability.check(bundle, products: index([a, b, c]), categories: [category], cart: Cart())
        XCTAssertEqual(r, .success(1))
    }

    func testSingleItemInCartReducesBundlePortions() {
        let a = product("大福", stock: 1), b = product("抹茶", stock: 5)
        let bundle = BundleModel.fixedMock(productIds: [a.id, b.id])
        var cart = Cart(); cart.productQuantities[a.id] = 1
        let r = BundleAvailability.check(bundle, products: index([a, b]), categories: [category], cart: cart)
        XCTAssertEqual(r, .failure(.memberOutOfStock(productName: "大福")))
    }

    func testBundleInCartReducesSingleItemRemainingStock() {
        let a = product("大福", stock: 1), b = product("抹茶", stock: 5)
        let bundle = BundleModel.fixedMock(productIds: [a.id, b.id])
        var cart = Cart(); cart.bundleLines[bundle.id] = line(bundle)
        XCTAssertEqual(BundleAvailability.remainingStock(of: a, cart: cart), 0)
        XCTAssertEqual(BundleAvailability.remainingStock(of: b, cart: cart), 4)
    }

    func testDisabledMemberMakesBundleUnavailableWithReason() {
        let a = product("大福", stock: 5, disabled: true), b = product("抹茶", stock: 5)
        let bundle = BundleModel.fixedMock(productIds: [a.id, b.id])
        let r = BundleAvailability.check(bundle, products: index([a, b]), categories: [category], cart: Cart())
        XCTAssertEqual(r, .failure(.memberUnavailable(productName: "大福")))
    }

    func testFixedBundleUnavailableWhenMemberCategoryDisabled() {
        let disabledCategory = CategoryModel.mock(isDisabled: true)
        let a = product("大福", stock: 5, categoryId: disabledCategory.id), b = product("抹茶", stock: 5)
        let bundle = BundleModel.fixedMock(productIds: [a.id, b.id])
        let r = BundleAvailability.check(bundle, products: index([a, b]), categories: [category, disabledCategory], cart: Cart())
        XCTAssertEqual(r, .failure(.memberUnavailable(productName: "大福")))
    }

    func testDisabledBundleIsUnavailable() {
        let a = product("大福", stock: 5)
        var bundle = BundleModel.fixedMock(productIds: [a.id])
        bundle.isDisabled = true
        let r = BundleAvailability.check(bundle, products: index([a]), categories: [category], cart: Cart())
        XCTAssertEqual(r, .failure(.bundleDisabled))
    }

    func testInvalidLinesDetectDeletedDisabledPriceChangedAndStock() {
        let a = product("大福", stock: 5), b = product("抹茶", stock: 1)
        let products = index([a, b])

        let deleted = BundleModel.fixedMock(name: "已刪", productIds: [a.id])
        let disabledOrig = BundleModel.fixedMock(name: "停用前", productIds: [a.id])
        var disabledNow = disabledOrig; disabledNow.isDisabled = true
        let priceOrig = BundleModel.fixedMock(name: "舊價", price: 100, productIds: [a.id])
        var priceNow = priceOrig; priceNow.price = 90
        let membersOrig = BundleModel.fixedMock(name: "舊成員", productIds: [a.id])
        var membersNow = membersOrig; membersNow.productIds = [a.id, b.id]
        let stockBundle = BundleModel.fixedMock(name: "缺貨", productIds: [b.id])

        var cart = Cart()
        cart.bundleLines[deleted.id] = line(deleted)
        cart.bundleLines[disabledOrig.id] = line(disabledOrig)
        cart.bundleLines[priceOrig.id] = line(priceOrig)
        cart.bundleLines[membersOrig.id] = line(membersOrig)
        cart.bundleLines[stockBundle.id] = line(stockBundle, qty: 2)   // 2 > stock 1

        let bundles = [disabledNow.id: disabledNow, priceNow.id: priceNow,
                       membersNow.id: membersNow, stockBundle.id: stockBundle]
        let result = BundleAvailability.invalidLines(in: cart, bundles: bundles, products: products, categories: [category])
        let byId = Dictionary(uniqueKeysWithValues: result.map { ($0.bundleId, $0) })

        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(byId[deleted.id], InvalidBundleLine(bundleId: deleted.id, name: "已刪", reason: .deleted))
        XCTAssertEqual(byId[disabledOrig.id]?.reason, .disabled)
        XCTAssertEqual(byId[priceOrig.id]?.reason, .priceChanged)
        XCTAssertEqual(byId[priceOrig.id]?.name, "舊價")
        XCTAssertEqual(byId[membersOrig.id]?.reason, .membersChanged)
        XCTAssertEqual(byId[stockBundle.id]?.reason, .insufficientStock)
    }

    func testValidCartHasNoInvalidLines() {
        let a = product("大福", stock: 5), b = product("抹茶", stock: 5)
        let bundle = BundleModel.fixedMock(productIds: [a.id, b.id])
        var cart = Cart()
        cart.bundleLines[bundle.id] = line(bundle, qty: 2)
        cart.productQuantities[a.id] = 3
        let result = BundleAvailability.invalidLines(in: cart, bundles: [bundle.id: bundle], products: index([a, b]), categories: [category])
        XCTAssertTrue(result.isEmpty)
    }
}
