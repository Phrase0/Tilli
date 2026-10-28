import XCTest
@testable import Tilli

@MainActor
final class BundleFormViewModelTests: XCTestCase {
    private let daifuku = ProductModel.mock(name: "大福", price: 40)
    private let matcha = ProductModel.mock(name: "抹茶", price: 60)
    private let redBean = ProductModel.mock(name: "紅豆", price: 20)

    private var products: [ProductModel] { [daifuku, matcha, redBean] }

    private func event(bundles: [BundleModel] = []) -> EventModel {
        var event = EventModel.mock()
        event.bundles = bundles
        return event
    }

    func testNewFixedBundleAppendsWhenValid() {
        let existing = BundleModel.fixedMock(name: "早餐套餐", price: 50, productIds: [daifuku.id, redBean.id])
        let vm = BundleFormViewModel(kind: .fixed, editing: nil, event: event(bundles: [existing]), products: products)
        vm.name = "下午茶套餐"
        vm.priceText = "100"
        vm.selectedProductIds = [daifuku.id, matcha.id, redBean.id]

        let saved = vm.bundlesToSave()

        XCTAssertEqual(saved?.count, 2)
        XCTAssertEqual(saved?.first, existing)
        let added = saved?.last
        XCTAssertEqual(added?.name, "下午茶套餐")
        XCTAssertEqual(added?.price, 100)
        XCTAssertEqual(added?.mode, .fixed)
        XCTAssertEqual(added?.productIds, [daifuku.id, matcha.id, redBean.id])
        XCTAssertEqual(added?.isDisabled, false)
    }

    func testNewComboUsesChosenCount() {
        let vm = BundleFormViewModel(kind: .chooseAny, editing: nil, event: event(), products: products)
        XCTAssertEqual(vm.count, 3)
        vm.name = "大福兩個"
        vm.priceText = "70"
        vm.count = 2
        vm.selectedProductIds = [daifuku.id]

        XCTAssertEqual(vm.bundlesToSave()?.last?.mode, .chooseAny(count: 2))
    }

    func testEditReplacesBundleWithSameId() {
        let target = BundleModel.fixedMock(name: "下午茶套餐", price: 100, productIds: [daifuku.id, matcha.id])
        let other = BundleModel.comboMock(price: 100, count: 3, productIds: [daifuku.id])
        let vm = BundleFormViewModel(kind: .fixed, editing: target, event: event(bundles: [target, other]), products: products)

        XCTAssertEqual(vm.name, "下午茶套餐")
        XCTAssertEqual(vm.priceText, "100")
        XCTAssertEqual(vm.selectedProductIds, [daifuku.id, matcha.id])

        vm.name = "午茶套餐"
        vm.priceText = "90"
        let saved = vm.bundlesToSave()

        XCTAssertEqual(saved?.count, 2)
        XCTAssertEqual(saved?.first?.id, target.id)
        XCTAssertEqual(saved?.first?.name, "午茶套餐")
        XCTAssertEqual(saved?.first?.price, 90)
        XCTAssertEqual(saved?.first?.createdAt, target.createdAt)
        XCTAssertEqual(saved?.last, other)
    }

    func testInvalidFormReturnsNilAndExposesErrors() {
        let vm = BundleFormViewModel(kind: .fixed, editing: nil, event: event(), products: products)
        vm.name = "下午茶套餐"
        vm.priceText = "121"
        vm.selectedProductIds = [daifuku.id, matcha.id, redBean.id]

        XCTAssertEqual(vm.errors, [.priceAboveLimit(limit: 120)])
        XCTAssertNil(vm.bundlesToSave())
    }

    func testPriceAtLimitShowsNoDiscountHint() {
        let vm = BundleFormViewModel(kind: .fixed, editing: nil, event: event(), products: products)
        vm.name = "下午茶套餐"
        vm.priceText = "120"
        vm.selectedProductIds = [daifuku.id, matcha.id, redBean.id]

        XCTAssertEqual(vm.errors, [])
        XCTAssertTrue(vm.showsNoDiscountHint)
    }

    func testOriginalTotalSumsSelectedMembers() {
        let vm = BundleFormViewModel(kind: .fixed, editing: nil, event: event(), products: products)
        vm.selectedProductIds = [daifuku.id, matcha.id, redBean.id]
        XCTAssertEqual(vm.originalTotal, 120)

        vm.toggle(matcha.id)
        XCTAssertEqual(vm.selectedProductIds, [daifuku.id, redBean.id])
        XCTAssertEqual(vm.originalTotal, 60)
    }
}
