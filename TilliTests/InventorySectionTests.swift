//
//  InventorySectionTests.swift
//  TilliTests
//
//  管理商品頁：區塊清單（組合｜套餐｜類別）、排序畫面的草稿與寫入，以及實際點 chip、捲動。
//

import XCTest
import SwiftUI
@testable import Tilli

@MainActor
final class InventorySectionTests: XCTestCase {

    private var fixture: SectionFixture!
    private var viewModel: InventoryViewModel!

    override func setUp() async throws {
        try await super.setUp()
        fixture = try SectionFixture()
        viewModel = InventoryViewModel(dataSource: try fixture.makeDataSource())
        viewModel.updateRepositories(
            productRepository: ProductRepository(container: fixture.container),
            eventRepository: EventRepository(container: fixture.container)
        )
    }

    override func tearDown() async throws {
        viewModel = nil
        fixture = nil
        try await super.tearDown()
    }

    private func category(_ name: String) -> InventorySectionID { .category(fixture.categoryIds[name]!) }

    // MARK: - 區塊清單

    func testComboThenFixedThenCategories() {
        XCTAssertEqual(viewModel.sectionIDs, [.comboBundles, .fixedBundles, category("甜點"), category("飲料"), category("季節")])
    }

    func testSearchListsOnlyMatchingSections() {
        viewModel.searchText = "咖啡"
        XCTAssertEqual(viewModel.sectionIDs, [category("飲料")])
    }

    // MARK: - 排序畫面

    func testDraftListsAllItemsIgnoringSearchIncludingDisabled() throws {
        try fixture.setProductDisabled("抹茶", true)
        viewModel.loadData()
        viewModel.searchText = "大福"
        let draft = viewModel.makeReorderDraft()
        XCTAssertEqual(draft.combos.map(\.id), [fixture.comboId])
        XCTAssertEqual(draft.fixed.map(\.id), [fixture.teaSetId])
        XCTAssertEqual(draft.categories.map(\.category.name), ["甜點", "飲料", "季節"])
        XCTAssertEqual(draft.categories[0].products.map(\.name), ["大福", "抹茶", "紅豆"], "不套搜尋、含已下架")
    }

    func testSaveAppliesProductAndBundleOrder() throws {
        var draft = viewModel.makeReorderDraft()
        draft.categories[1].products.reverse()
        XCTAssertTrue(viewModel.saveOrder(draft))
        let saved = viewModel.makeReorderDraft()
        XCTAssertEqual(saved.categories[1].products.map(\.name), ["咖啡", "奶茶", "綠茶", "紅茶"])
        XCTAssertFalse(viewModel.reorderSaveFailed)
    }

    func testBundleOrderAppliesToInventoryAndPOS() throws {
        // 再加一個套餐，排序後收銀頁套餐順序跟著變
        let context = fixture.container.viewContext
        let event = try XCTUnwrap(context.fetch(CDEventEntity.fetchRequest()).first)
        var bundles = try JSONDecoder().decode([BundleModel].self, from: XCTUnwrap(event.bundlesData))
        let second = BundleModel.mock(name: "飲料套餐", price: 90, mode: .fixed,
                                      productIds: [fixture.productIds["紅茶"]!, fixture.productIds["咖啡"]!], sortOrder: 1)
        bundles.append(second)
        event.bundlesData = try JSONEncoder().encode(bundles)
        try context.save()
        viewModel.loadData()

        var draft = viewModel.makeReorderDraft()
        XCTAssertEqual(draft.fixed.map(\.name), ["下午茶套餐", "飲料套餐"])
        draft.fixed.reverse()
        XCTAssertTrue(viewModel.saveOrder(draft))

        XCTAssertEqual(viewModel.fixedBundles.map(\.name), ["飲料套餐", "下午茶套餐"])
        let pos = POSViewModel(dataSource: try fixture.makeDataSource(), defaults: UserDefaults(suiteName: "InventorySectionTests")!)
        pos.loadProducts()
        XCTAssertEqual(pos.fixedBundles.map(\.name), ["飲料套餐", "下午茶套餐"], "收銀頁套餐順序同步")
    }

    func testCancelLeavesOrderUnchanged() {
        let before = viewModel.makeReorderDraft()
        var draft = before
        draft.categories[1].products.reverse()
        // 取消：不呼叫 saveOrder
        XCTAssertEqual(viewModel.makeReorderDraft(), before)
    }

    func testSaveFailureIsReportedAndSheetStays() throws {
        let unattached = InventoryViewModel(dataSource: try fixture.makeDataSource())
        XCTAssertFalse(unattached.saveOrder(unattached.makeReorderDraft()))
        XCTAssertTrue(unattached.reorderSaveFailed)
        XCTAssertFalse(unattached.showAlert, "管理頁的提示不跳（被排序畫面蓋住）")
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

    // MARK: - 實際點 chip、捲動

    private func harness() -> InteractionHarness<some View> {
        InteractionHarness(
            NavigationStack {
                InventoryView(
                    event: viewModel.event,
                    viewModel: viewModel,
                    showShareSheet: .constant(false),
                    formTarget: .constant(nil)
                )
            }
            .environmentObject(ProductRepository(container: fixture.container))
            .environmentObject(EventRepository(container: fixture.container))
        )
    }

    private var titles: [String] {
        [String.localized("bundleChipCombo"), String.localized("bundleChipFixed"), "甜點", "飲料", "季節"]
    }

    func testTappingChipsScrollsAndHighlights() throws {
        let h = harness()
        XCTAssertEqual(h.selectedLabels, [titles[0]])
        XCTAssertTrue(h.tap("飲料"))
        XCTAssertGreaterThan(try XCTUnwrap(h.mainScrollView).contentOffset.y, 0, "清單有捲動")
        XCTAssertEqual(h.selectedLabels, ["飲料"])
        XCTAssertTrue(h.tap(titles[0]))
        XCTAssertEqual(try XCTUnwrap(h.mainScrollView).contentOffset.y, 0, accuracy: 1)
        XCTAssertEqual(h.selectedLabels, [titles[0]])
    }

    func testScrollingVisitsEverySectionInOrder() throws {
        let h = harness()
        let scrollView = try XCTUnwrap(h.mainScrollView)
        let maxY = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        XCTAssertGreaterThan(maxY, 0)
        var down: [String] = []
        for y in stride(from: 0, through: maxY, by: 20) {
            h.scroll(toY: y)
            if let label = h.selectedLabels.first, down.last != label { down.append(label) }
        }
        XCTAssertEqual(down, titles)
        var up: [String] = []
        for y in stride(from: maxY, through: 0, by: -20) {
            h.scroll(toY: y)
            if let label = h.selectedLabels.first, up.last != label { up.append(label) }
        }
        XCTAssertEqual(up, titles.reversed())
    }
}
