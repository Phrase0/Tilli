//
//  POSBundleCartTests.swift
//  TilliTests
//
//  POSViewModel 的套餐行、組合取消與庫存佔用（設計 §4.5、§5.4、§5.6、§9.1 第 5 點）。
//  走真實的 EventDataSource（in-memory CoreData），不呼叫任何碰 Auth 的 Repository 方法。
//

import XCTest
import CoreData
@testable import Tilli

@MainActor
final class POSBundleCartTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var viewModel: POSViewModel!

    private var eventId: UUID!
    private var daifukuId: UUID!      // 大福 40，庫存 2
    private var matchaId: UUID!       // 抹茶 60，庫存 5
    private var teaSetId: UUID!       // 套餐：大福 + 抹茶 = 90
    private var comboId: UUID!        // 組合：任選 2 個 80

    override func setUp() async throws {
        try await super.setUp()
        container = TestStore.makeInMemoryContainer()
        try seed()

        let event = EventRepository(container: container).fetchEvent(by: eventId)!
        let dataSource = EventDataSource(event: event)
        dataSource.attach(
            eventRepository: EventRepository(container: container),
            productRepository: ProductRepository(container: container),
            transactionRepository: TransactionRepository(container: container),
            inventoryChangeRepository: InventoryChangeRepository(container: container)
        )
        viewModel = POSViewModel(dataSource: dataSource)
        viewModel.loadProducts()
    }

    override func tearDown() async throws {
        viewModel = nil
        container = nil
        try await super.tearDown()
    }

    private func seed() throws {
        let context = container.viewContext

        let event = CDEventEntity(context: context)
        eventId = UUID()
        event.id = eventId
        event.title = "測試場次"
        event.startDate = Date()
        event.createdAt = Date()
        event.currency = "TWD"
        event.dateType = EventDateType.single.rawValue

        let category = CDCategoryEntity(context: context)
        category.id = UUID()
        category.name = "甜點"
        category.createdAt = Date()
        category.isDisabled = false
        category.sortOrder = 0
        category.event = event

        func makeProduct(name: String, price: Int, stock: Int32, sortOrder: Int16) -> UUID {
            let product = CDProductEntity(context: context)
            product.id = UUID()
            product.eventId = event.id
            product.name = name
            product.price = NSDecimalNumber(value: price)
            product.stock = stock
            product.categoryId = category.id
            product.isDisabled = false
            product.sortOrder = sortOrder
            product.createdAt = Date(timeIntervalSince1970: TimeInterval(sortOrder))
            product.category = category
            return product.id
        }

        daifukuId = makeProduct(name: "大福", price: 40, stock: 2, sortOrder: 0)
        matchaId = makeProduct(name: "抹茶", price: 60, stock: 5, sortOrder: 1)

        teaSetId = UUID()
        comboId = UUID()
        let bundles: [BundleModel] = [
            .mock(id: teaSetId, name: "下午茶套餐", price: 90, mode: .fixed, productIds: [daifukuId, matchaId]),
            .mock(id: comboId, name: "任選兩個", price: 80, mode: .chooseAny(count: 2), productIds: [daifukuId, matchaId]),
            .mock(name: "已下架套餐", price: 90, mode: .fixed, productIds: [daifukuId, matchaId], isDisabled: true),
        ]
        event.bundlesData = try JSONEncoder().encode(bundles)
        event.discountsData = try JSONEncoder().encode([DiscountModel.percentage(10)])

        try context.save()
    }

    private var daifuku: ProductModel { viewModel.products.first { $0.id == daifukuId }! }
    private var matcha: ProductModel { viewModel.products.first { $0.id == matchaId }! }
    private var teaSet: BundleModel { viewModel.fixedBundles.first { $0.id == teaSetId }! }

    // MARK: - 收銀頁顯示

    func testFixedBundlesExcludeCombosAndDisabledBundles() {
        XCTAssertEqual(viewModel.fixedBundles.map(\.id), [teaSetId])
    }

    // MARK: - 雙向佔用（§5.6）

    func testBundleLineReservesStockForSingleProducts() {
        viewModel.addBundle(teaSet)

        viewModel.increaseQuantity(for: daifuku)
        viewModel.increaseQuantity(for: daifuku)

        XCTAssertEqual(viewModel.quantity(for: daifuku), 1, "大福庫存 2，套餐已佔 1，只能再單點 1 個")
    }

    func testAddingBundleWhenMemberUsedUpShowsReasonAndDoesNotAdd() {
        viewModel.increaseQuantity(for: daifuku)
        viewModel.increaseQuantity(for: daifuku)

        viewModel.addBundle(teaSet)

        XCTAssertEqual(viewModel.bundleQuantity(teaSetId), 0)
        XCTAssertTrue(viewModel.showAlert)
        XCTAssertEqual(viewModel.availability(of: teaSet), .failure(.memberOutOfStock(productName: "大福")))
    }

    func testRemoveBundleDecrementsThenRemovesLine() {
        viewModel.addBundle(teaSet)
        viewModel.addBundle(teaSet)
        XCTAssertEqual(viewModel.bundleQuantity(teaSetId), 2)

        viewModel.removeBundle(teaSetId)
        XCTAssertEqual(viewModel.bundleQuantity(teaSetId), 1)

        viewModel.removeBundle(teaSetId)
        XCTAssertNil(viewModel.cart.bundleLines[teaSetId])
    }

    // MARK: - 定價與組合

    func testTotalUsesBundlePriceAndAutoAppliedCombo() {
        viewModel.addBundle(teaSet)                 // 90
        viewModel.increaseQuantity(for: daifuku)    // 40 ┐ 組合 80（原價 100）
        viewModel.increaseQuantity(for: matcha)     // 60 ┘

        XCTAssertEqual(viewModel.subtotal(), 190)
        XCTAssertEqual(viewModel.totalAmount(), 170)
    }

    /// 順序：組合差額 → 百分比（§5.5）
    func testPercentageDiscountIsBasedOnSubtotalMinusComboDeduction() {
        viewModel.increaseQuantity(for: daifuku)
        viewModel.increaseQuantity(for: matcha)
        viewModel.toggleDiscount(viewModel.percentageDiscounts.first!)   // 10%

        XCTAssertEqual(viewModel.appliedDiscounts().map(\.amount), [8], "折扣基礎 = 100 − 組合差額 20 = 80")
        XCTAssertEqual(viewModel.discountAmount(), 8)
        XCTAssertEqual(viewModel.totalAmount(), 72)
    }

    func testCancellingComboOnlyAffectsThisCartAndCanBeRestored() {
        viewModel.increaseQuantity(for: daifuku)
        viewModel.increaseQuantity(for: matcha)
        XCTAssertEqual(viewModel.totalAmount(), 80)

        viewModel.toggleComboCancelled(comboId)
        XCTAssertEqual(viewModel.totalAmount(), 100)

        viewModel.toggleComboCancelled(comboId)
        XCTAssertEqual(viewModel.totalAmount(), 80)
    }

    func testCheckoutSummaryExpandsBundleIntoMembersWithDeduction() {
        viewModel.addBundle(teaSet)

        let summary = viewModel.pricing.summaryItems(categoryName: viewModel.categoryName(for:), timestamp: Date())

        XCTAssertEqual(Set(summary.items.map(\.productId)), [daifukuId, matchaId])
        XCTAssertTrue(summary.items.allSatisfy { $0.bundleId == teaSetId && $0.category == "甜點" })
        XCTAssertEqual(summary.bundleDeductions.map(\.amount), [10])
    }

    // MARK: - 清除

    func testClearAllQuantitiesAlsoClearsBundleLinesAndCancelledCombos() {
        viewModel.addBundle(teaSet)
        viewModel.increaseQuantity(for: matcha)
        viewModel.toggleComboCancelled(comboId)

        viewModel.clearAllQuantities()

        XCTAssertEqual(viewModel.cart, Cart())
    }

    // MARK: - 失效套餐行（§9.1 第 5 點）

    func testChangedBundleBlocksCheckoutUntilConfirmedThenOnlyThatLineIsRemoved() {
        viewModel.addBundle(teaSet)
        viewModel.increaseQuantity(for: matcha)
        XCTAssertTrue(viewModel.prepareCheckout())

        // 管理頁把套餐改價後回到收銀頁
        var changed = viewModel.event.bundles
        let index = changed.firstIndex { $0.id == teaSetId }!
        changed[index].price = 95
        XCTAssertTrue(EventRepository(container: container).saveBundles(changed, forEventId: eventId))
        viewModel.loadProducts()

        XCTAssertEqual(viewModel.invalidBundleLines.map(\.reason), [.priceChanged])
        XCTAssertFalse(viewModel.prepareCheckout(), "有失效的套餐行不能開結帳")

        viewModel.confirmInvalidBundleLines()

        XCTAssertTrue(viewModel.invalidBundleLines.isEmpty)
        XCTAssertEqual(viewModel.bundleQuantity(teaSetId), 0)
        XCTAssertEqual(viewModel.quantity(for: matcha), 1, "其餘商品保留")
        XCTAssertTrue(viewModel.prepareCheckout())
    }
}
