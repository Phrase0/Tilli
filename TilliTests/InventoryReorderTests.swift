//
//  InventoryReorderTests.swift
//  TilliTests
//
//  排序畫面（InventoryReorderViewModel）：草稿內容、拖曳、寫入、取消、寫入失敗，
//  以及排序結果同步到管理頁與收銀頁、不影響組合自動套用順序。
//

import XCTest
@testable import Tilli

@MainActor
final class InventoryReorderTests: XCTestCase {

    private var fixture: SectionFixture!
    private var dataSource: EventDataSource!
    private var inventory: InventoryViewModel!
    private var viewModel: InventoryReorderViewModel!

    override func setUp() async throws {
        try await super.setUp()
        fixture = try SectionFixture()
        dataSource = try fixture.makeDataSource()
        inventory = InventoryViewModel(dataSource: dataSource)
        inventory.updateRepositories(
            productRepository: ProductRepository(container: fixture.container),
            eventRepository: EventRepository(container: fixture.container)
        )
        viewModel = makeReorderViewModel()
    }

    override func tearDown() async throws {
        viewModel = nil
        inventory = nil
        dataSource = nil
        fixture = nil
        try await super.tearDown()
    }

    /// 與 App 相同的接法：共用同一個 dataSource，有寫入時管理頁重新載入
    private func makeReorderViewModel() -> InventoryReorderViewModel {
        let inventory = inventory!
        let reorder = InventoryReorderViewModel(dataSource: dataSource) { inventory.loadData() }
        reorder.updateRepositories(
            productRepository: ProductRepository(container: fixture.container),
            eventRepository: EventRepository(container: fixture.container)
        )
        return reorder
    }

    func testDraftListsAllItemsIgnoringSearchIncludingDisabled() throws {
        try fixture.setProductDisabled("抹茶", true)
        inventory.loadData()
        inventory.searchText = "大福"
        let draft = makeReorderViewModel().draft
        XCTAssertEqual(draft.combos.map(\.id), [fixture.comboId])
        XCTAssertEqual(draft.fixed.map(\.id), [fixture.teaSetId])
        XCTAssertEqual(draft.categories.map(\.category.name), ["甜點", "飲料", "季節"])
        XCTAssertEqual(draft.categories[0].products.map(\.name), ["大福", "抹茶", "紅豆"], "不套搜尋、含已下架")
    }

    func testMovingProductsOnlyChangesDraftUntilSave() {
        viewModel.moveProducts(inGroup: 1, from: IndexSet(integer: 3), to: 0)
        XCTAssertEqual(viewModel.draft.categories[1].products.map(\.name), ["咖啡", "紅茶", "綠茶", "奶茶"])
        XCTAssertEqual(makeReorderViewModel().draft.categories[1].products.map(\.name), ["紅茶", "綠茶", "奶茶", "咖啡"],
                       "還沒按完成，資料庫不變")
    }

    func testSaveAppliesProductOrderAndReloadsInventory() {
        viewModel.moveProducts(inGroup: 1, from: IndexSet(integer: 3), to: 0)
        XCTAssertTrue(viewModel.save())
        XCTAssertFalse(viewModel.saveFailed)
        XCTAssertEqual(makeReorderViewModel().draft.categories[1].products.map(\.name), ["咖啡", "紅茶", "綠茶", "奶茶"])
        let drinks = inventory.getItemsForCategory(fixture.categoryIds["飲料"]!).map(\.product.name)
        XCTAssertEqual(drinks, ["咖啡", "紅茶", "綠茶", "奶茶"], "管理頁重新載入")
    }

    func testBundleOrderAppliesToInventoryAndPOS() throws {
        // 再加一個套餐，排序後管理頁與收銀頁的套餐順序跟著變
        let context = fixture.container.viewContext
        let event = try XCTUnwrap(context.fetch(CDEventEntity.fetchRequest()).first)
        var bundles = try JSONDecoder().decode([BundleModel].self, from: XCTUnwrap(event.bundlesData))
        let second = BundleModel.mock(name: "飲料套餐", price: 90, mode: .fixed,
                                      productIds: [fixture.productIds["紅茶"]!, fixture.productIds["咖啡"]!], sortOrder: 1)
        bundles.append(second)
        event.bundlesData = try JSONEncoder().encode(bundles)
        try context.save()
        inventory.loadData()
        viewModel = makeReorderViewModel()

        XCTAssertEqual(viewModel.draft.fixed.map(\.name), ["下午茶套餐", "飲料套餐"])
        viewModel.moveFixed(from: IndexSet(integer: 1), to: 0)
        XCTAssertTrue(viewModel.save())

        XCTAssertEqual(inventory.fixedBundles.map(\.name), ["飲料套餐", "下午茶套餐"])
        let pos = POSViewModel(dataSource: try fixture.makeDataSource(), defaults: UserDefaults(suiteName: "InventoryReorderTests")!)
        pos.loadProducts()
        XCTAssertEqual(pos.fixedBundles.map(\.name), ["飲料套餐", "下午茶套餐"], "收銀頁套餐順序同步")
    }

    func testCancelLeavesOrderUnchanged() {
        let before = viewModel.draft
        viewModel.moveProducts(inGroup: 1, from: IndexSet(integer: 3), to: 0)
        // 取消：不呼叫 save，直接丟掉這個 ViewModel
        XCTAssertEqual(makeReorderViewModel().draft, before)
    }

    func testSaveWithoutRepositoriesFailsAndReportsOnReorderScreen() {
        let unattached = InventoryReorderViewModel(dataSource: dataSource)
        XCTAssertFalse(unattached.save())
        XCTAssertTrue(unattached.saveFailed)
        XCTAssertFalse(inventory.showAlert, "管理頁的提示不跳（被排序畫面蓋住）")
    }

    func testComboApplyOrderUnaffectedBySortOrder() {
        let cheap = ProductModel.mock(name: "便宜", price: 30)
        let pricey = ProductModel.mock(name: "貴", price: 60)
        let category = CategoryModel.mock()
        var first = BundleModel.mock(name: "任兩個便宜", price: 50, mode: .chooseAny(count: 2), productIds: [cheap.id, pricey.id])
        var second = BundleModel.mock(name: "任兩個貴", price: 100, mode: .chooseAny(count: 2), productIds: [cheap.id, pricey.id])
        var cart = Cart()
        cart.productQuantities = [cheap.id: 2, pricey.id: 2]
        let products = [cheap.id: cheap, pricey.id: pricey].mapValues { p -> ProductModel in var p = p; p.categoryId = category.id; return p }
        func applied() -> [UUID] {
            CartPricing.price(cart: cart, products: products, bundles: [first.id: first, second.id: second],
                              categories: [category], selectedDiscounts: []).combos.map(\.bundleId)
        }
        first.sortOrder = 0; second.sortOrder = 1
        let a = applied()
        first.sortOrder = 1; second.sortOrder = 0
        XCTAssertEqual(applied(), a)
    }
}
