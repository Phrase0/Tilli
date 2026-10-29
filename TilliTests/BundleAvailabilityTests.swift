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

    // MARK: - 單點商品超量

    func testInvalidProductLinesDetectUnavailableDeletedAndOverStock() {
        let soldOut = product("大福", stock: 0)
        let low = product("抹茶", stock: 2)
        let offSale = product("紅豆", stock: 5, disabled: true)
        let fine = product("草莓", stock: 5)
        let deletedId = UUID()

        var cart = Cart()
        cart.productQuantities[soldOut.id] = 2
        cart.productQuantities[low.id] = 3
        cart.productQuantities[offSale.id] = 1
        cart.productQuantities[fine.id] = 5
        cart.productQuantities[deletedId] = 1

        let result = BundleAvailability.invalidProductLines(
            in: cart,
            removingBundleLines: [],
            products: index([soldOut, low, offSale, fine]),
            categories: [category],
            previousNames: [deletedId: "已刪商品"]
        )
        let byId = Dictionary(uniqueKeysWithValues: result.map { ($0.productId, $0) })

        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(byId[soldOut.id], InvalidProductLine(productId: soldOut.id, name: "大福", reason: .insufficientStock(remaining: 0)))
        XCTAssertEqual(byId[low.id]?.reason, .insufficientStock(remaining: 2))
        XCTAssertEqual(byId[offSale.id]?.reason, .unavailable)
        XCTAssertEqual(byId[deletedId], InvalidProductLine(productId: deletedId, name: "已刪商品", reason: .deleted))
        XCTAssertNil(byId[fine.id], "剛好等於庫存不算超量")
    }

    func testInvalidProductLinesCountOnlyBundleLinesThatStay() {
        let a = product("大福", stock: 2), b = product("抹茶", stock: 5)
        let kept = BundleModel.fixedMock(name: "保留", productIds: [a.id, b.id])
        let removed = BundleModel.fixedMock(name: "失效", productIds: [a.id, b.id])
        var cart = Cart()
        cart.bundleLines[kept.id] = line(kept)
        cart.bundleLines[removed.id] = line(removed)
        cart.productQuantities[a.id] = 1

        // 失效的套餐行會被移除，不佔庫存：大福剩 2 − 1（保留的套餐）= 1，單點 1 個不超量
        let withRemoval = BundleAvailability.invalidProductLines(
            in: cart, removingBundleLines: [removed.id], products: index([a, b]), categories: [category]
        )
        XCTAssertTrue(withRemoval.isEmpty)

        // 兩個套餐行都留著：大福 2 個都被套餐佔走，單點只能剩 0
        let withoutRemoval = BundleAvailability.invalidProductLines(
            in: cart, removingBundleLines: [], products: index([a, b]), categories: [category]
        )
        XCTAssertEqual(withoutRemoval.map(\.reason), [.insufficientStock(remaining: 0)])
    }

    // MARK: - 組合（管理頁 ⚠️）

    func testComboOffSaleCandidateGivesNoWarningWhenOthersSuffice() {
        let a = product("大福", stock: 2), b = product("抹茶", stock: 5, disabled: true), c = product("紅豆", stock: 1)
        let combo = BundleModel.comboMock(count: 3, productIds: [a.id, b.id, c.id])
        XCTAssertNil(BundleAvailability.comboWarning(combo, products: index([a, b, c]), categories: [category]))
    }

    func testComboWarnsWhenSellableCandidateStockBelowCount() {
        let a = product("大福", stock: 2)
        let combo = BundleModel.comboMock(count: 3, productIds: [a.id])
        XCTAssertEqual(
            BundleAvailability.comboWarning(combo, products: index([a]), categories: [category]),
            ComboWarning(availableStock: 2, required: 3)
        )
    }

    func testComboStockExactlyCountGivesNoWarning() {
        let a = product("大福", stock: 3)
        let combo = BundleModel.comboMock(count: 3, productIds: [a.id])
        XCTAssertNil(BundleAvailability.comboWarning(combo, products: index([a]), categories: [category]))
    }

    func testComboWithOnlyOffSaleCandidatesWarns() {
        let a = product("大福", stock: 10, disabled: true)
        let combo = BundleModel.comboMock(count: 2, productIds: [a.id])
        XCTAssertEqual(
            BundleAvailability.comboWarning(combo, products: index([a]), categories: [category]),
            ComboWarning(availableStock: 0, required: 2)
        )
    }
}
