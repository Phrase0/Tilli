//
//  POSQuantityControlTests.swift
//  TilliTests
//
//  POSViewModel 的增減元件規則：加／減、展開／收合、能不能再加。
//  走真實的 EventDataSource（in-memory CoreData），不呼叫任何碰 Auth 的 Repository 方法。
//

import XCTest
import CoreData
import Combine
@testable import Tilli

@MainActor
final class POSQuantityControlTests: XCTestCase {

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

    // MARK: - 加／減與展開

    func testIncrementAddsOneAndExpandsItem() {
        viewModel.increment(.product(daifukuId))
        XCTAssertEqual(viewModel.quantity(of: .product(daifukuId)), 1)
        XCTAssertEqual(viewModel.expandedItem, .product(daifukuId))
    }

    func testIncrementWithoutExpandDoesNotChangeExpandedItem() {
        viewModel.expand(.product(matchaId))
        viewModel.increment(.product(daifukuId), expand: false)
        XCTAssertEqual(viewModel.quantity(of: .product(daifukuId)), 1)
        XCTAssertEqual(viewModel.expandedItem, .product(matchaId))
    }

    func testExpandingAnotherItemCollapsesThePrevious() {
        viewModel.increment(.product(daifukuId))
        viewModel.increment(.bundle(teaSetId))
        XCTAssertEqual(viewModel.quantity(of: .bundle(teaSetId)), 1)
        XCTAssertEqual(viewModel.expandedItem, .bundle(teaSetId))
    }

    func testDecrementToZeroCollapses() {
        viewModel.increment(.product(matchaId))
        viewModel.increment(.product(matchaId))
        viewModel.decrement(.product(matchaId))
        XCTAssertEqual(viewModel.quantity(of: .product(matchaId)), 1)
        XCTAssertEqual(viewModel.expandedItem, .product(matchaId), "還有數量就維持展開")

        viewModel.decrement(.product(matchaId))
        XCTAssertEqual(viewModel.quantity(of: .product(matchaId)), 0)
        XCTAssertNil(viewModel.expandedItem)
    }

    func testCollapseControlsClearsExpandedItem() {
        viewModel.increment(.product(daifukuId))
        viewModel.collapseControls()
        XCTAssertNil(viewModel.expandedItem)
        XCTAssertEqual(viewModel.quantity(of: .product(daifukuId)), 1)
    }

    // MARK: - 能不能再加

    func testCannotIncrementProductWhenStockReservedByBundle() {
        // 大福庫存 2：套餐 1 份 + 單點 1 個
        viewModel.increment(.bundle(teaSetId))
        viewModel.increment(.product(daifukuId))
        XCTAssertFalse(viewModel.canIncrement(.product(daifukuId)))

        viewModel.increment(.product(daifukuId))
        XCTAssertEqual(viewModel.quantity(of: .product(daifukuId)), 1)
        XCTAssertTrue(viewModel.canIncrement(.product(matchaId)))
    }

    func testCannotIncrementUnavailableBundle() {
        viewModel.increment(.product(daifukuId))
        XCTAssertTrue(viewModel.canIncrement(.bundle(teaSetId)))
        viewModel.increment(.product(daifukuId))
        XCTAssertFalse(viewModel.canIncrement(.bundle(teaSetId)))
    }

    func testUnknownBundleCannotBeIncremented() {
        let unknown = CartItemID.bundle(UUID())
        XCTAssertFalse(viewModel.canIncrement(unknown))
        viewModel.increment(unknown)
        XCTAssertEqual(viewModel.quantity(of: unknown), 0)
    }

    // MARK: - 本來就沒庫存 vs 被購物車用完

    private func setStock(_ productId: UUID, _ stock: Int32) throws {
        let request = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productId as CVarArg)
        let entity = try XCTUnwrap(container.viewContext.fetch(request).first)
        entity.stock = stock
        try container.viewContext.save()
    }

    func testBundleLimitedByCartIsNotGreyedButCannotIncrement() {
        viewModel.increment(.product(daifukuId))
        viewModel.increment(.product(daifukuId))
        XCTAssertNil(viewModel.soldOutReason(of: teaSet), "被購物車用完不灰卡片")
        XCTAssertFalse(viewModel.canIncrement(.bundle(teaSetId)))
    }

    func testBundleWithZeroStockMemberIsGreyedRegardlessOfCart() throws {
        try setStock(daifukuId, 0)
        viewModel.loadProducts()
        XCTAssertEqual(viewModel.soldOutReason(of: teaSet), .memberOutOfStock(productName: "大福"))
    }

    func testUnavailableAlertOnlyWhenSoldOutNotWhenLimitedByCart() throws {
        viewModel.increment(.product(daifukuId))
        viewModel.increment(.product(daifukuId))
        viewModel.showUnavailableAlert(for: teaSet)
        XCTAssertFalse(viewModel.showAlert, "被購物車用完時點卡片不提醒")

        viewModel.clearAllQuantities()
        try setStock(daifukuId, 0)
        viewModel.loadProducts()
        viewModel.showUnavailableAlert(for: teaSet)
        XCTAssertTrue(viewModel.showAlert)
        // 與點缺貨商品的提醒相同（「大福」目前無庫存，無法加入訂單…）
        XCTAssertEqual(viewModel.alertMessage, String.localized("productDetailNoStock \("大福")"))
    }

    // MARK: - 組合列

    func testComboRowsKeepCreationOrderAndShowRestorableAmount() {
        // 抹茶 2 個 → 「任選兩個 80」：120 − 80 = 40
        viewModel.increment(.product(matchaId))
        viewModel.increment(.product(matchaId))
        XCTAssertEqual(viewModel.comboRows.map(\.id), [comboId])
        XCTAssertEqual(viewModel.comboRows.first?.amount, 40)
        XCTAssertEqual(viewModel.comboRows.first?.groupCount, 1)
        XCTAssertEqual(viewModel.comboRows.first?.isCancelled, false)

        viewModel.toggleComboCancelled(comboId)
        XCTAssertEqual(viewModel.comboRows.map(\.id), [comboId], "取消後列還在原位")
        XCTAssertEqual(viewModel.comboRows.first?.isCancelled, true)
        XCTAssertEqual(viewModel.comboRows.first?.amount, 40, "顯示恢復後可省的金額")
        XCTAssertEqual(viewModel.comboRows.first?.groupCount, 1)
        XCTAssertTrue(viewModel.pricing.combos.isEmpty)
    }

    func testCancelledComboThatNoLongerAppliesIsNotListed() {
        viewModel.increment(.product(matchaId))
        viewModel.increment(.product(matchaId))
        viewModel.toggleComboCancelled(comboId)
        viewModel.decrement(.product(matchaId))
        // 只剩 1 個抹茶，恢復也湊不成一組：不列出（不顯示「−NT$0」與按了就消失的「恢復」）
        XCTAssertTrue(viewModel.comboRows.isEmpty)

        // 再加回來：仍是這一筆已取消的組合
        viewModel.increment(.product(matchaId))
        XCTAssertEqual(viewModel.comboRows.map(\.isCancelled), [true])
    }

    // MARK: - 購物車清空

    func testRemovingLastItemEmptiesCart() {
        viewModel.increment(.bundle(teaSetId))
        XCTAssertFalse(viewModel.isCartEmpty)
        viewModel.decrement(.bundle(teaSetId))
        XCTAssertTrue(viewModel.isCartEmpty)
    }

    func testClearAllQuantitiesCollapses() {
        viewModel.increment(.product(daifukuId))
        viewModel.clearAllQuantities()
        XCTAssertNil(viewModel.expandedItem)
        XCTAssertTrue(viewModel.isCartEmpty)
    }

    // MARK: - 審查修正

    func testCollapseWhenNothingExpandedDoesNotPublish() {
        var publishCount = 0
        let cancellable = viewModel.objectWillChange.sink { _ in publishCount += 1 }
        viewModel.collapseControls()
        viewModel.collapseControls()
        XCTAssertEqual(publishCount, 0, "捲動時每一幀都會呼叫；沒有展開時不可觸發重繪")
        cancellable.cancel()
    }

    func testEmptyingCartForgetsCancelledCombosForNextCustomer() {
        viewModel.increment(.product(matchaId))
        viewModel.increment(.product(matchaId))
        XCTAssertFalse(viewModel.pricing.combos.isEmpty)
        viewModel.toggleComboCancelled(comboId)
        XCTAssertTrue(viewModel.pricing.combos.isEmpty)

        // 這位客人把東西全部刪掉
        viewModel.decrement(.product(matchaId))
        viewModel.decrement(.product(matchaId))
        XCTAssertTrue(viewModel.isCartEmpty)

        // 下一位客人買同樣的東西，組合要自動套用
        viewModel.increment(.product(matchaId))
        viewModel.increment(.product(matchaId))
        XCTAssertFalse(viewModel.pricing.combos.isEmpty, "取消組合只對這一筆有效")
    }
}
