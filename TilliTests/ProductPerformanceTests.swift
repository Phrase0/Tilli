//
//  ProductPerformanceTests.swift
//  TilliTests
//
//  Created by Peiyun on 2026/9/15.
//
//  對應 FEATURE_PLAN_V1.md §5.1／§4.2（D5）與 §11 第 2 批的 2.1／2.2。
//

import XCTest
import CoreData
@testable import Tilli

// MARK: - 2.1 平均單價（純函式）

final class ProductSalesStatsTests: XCTestCase {

    private func makeStats() -> ProductSalesStats {
        ProductSalesStats(productId: UUID(), name: "大福", category: "甜點", categoryId: UUID())
    }

    /// ⭐ D5：原本 `unitPrice` 每次 addSale 覆蓋成最後一筆的單價，
    /// 註解直接寫「假設同商品單價一致」。多種成交單價時那個值是失真的。
    func testAverageUnitPriceAcrossDifferentPrices() {
        let stats = makeStats()

        stats.addSale(quantity: 3, unitPrice: 100, actualTotal: 300)   // 原價 300
        stats.addSale(quantity: 2, unitPrice: 50, actualTotal: 100)    // 原價 100

        XCTAssertEqual(stats.totalQuantity, 5)
        XCTAssertEqual(stats.originalRevenue, 400)
        // (300 + 100) ÷ 5 = 80，而不是「最後一筆的 50」
        XCTAssertEqual(stats.averageUnitPrice, 80)
    }

    func testAverageUnitPriceEqualsUnitPriceWhenOnlyOnePrice() {
        let stats = makeStats()

        stats.addSale(quantity: 4, unitPrice: 120, actualTotal: 480)

        // 只有一種單價時，結果與改動前的 unitPrice 相同（確保沒有回歸）
        XCTAssertEqual(stats.averageUnitPrice, 120)
    }

    func testAverageUnitPriceIsZeroWhenNothingSold() {
        // 不可以除以零
        XCTAssertEqual(makeStats().averageUnitPrice, 0)
    }

    func testAddSaleAccumulatesRevenueAndDiscount() {
        let stats = makeStats()

        stats.addSale(quantity: 2, unitPrice: 100, actualTotal: 180)   // 折 20
        stats.addSale(quantity: 1, unitPrice: 100, actualTotal: 90)    // 折 10

        XCTAssertEqual(stats.originalRevenue, 300)
        XCTAssertEqual(stats.actualRevenue, 270)
        XCTAssertEqual(stats.totalDiscount, 30)
        XCTAssertEqual(stats.averageUnitPrice, 100)
    }

    func testAverageUnitPriceKeepsPrecision() {
        let stats = makeStats()

        // 100 ÷ 3 除不盡，不該被提前捨入成整數
        stats.addSale(quantity: 3, unitPrice: Decimal(string: "33.33")!, actualTotal: 99.99)

        XCTAssertEqual(stats.averageUnitPrice, Decimal(string: "33.33")!)
    }
}

// MARK: - 2.2 排行 + 未售出（走真實的 EventDataSource）

@MainActor
final class ProductPerformanceSplitTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var dataSource: EventDataSource!
    private var viewModel: ProductPerformanceViewModel!

    private var eventId: UUID!
    private var categoryId: UUID!
    private var soldProductId: UUID!
    private var unsoldProductId: UUID!
    private var disabledUnsoldProductId: UUID!

    override func setUp() async throws {
        try await super.setUp()
        container = TestStore.makeInMemoryContainer()
        try seed()

        let event = EventRepository(container: container).fetchEvent(by: eventId)!
        dataSource = EventDataSource(event: event)
        dataSource.attach(
            eventRepository: EventRepository(container: container),
            productRepository: ProductRepository(container: container),
            transactionRepository: TransactionRepository(container: container),
            inventoryChangeRepository: InventoryChangeRepository(container: container)
        )
        viewModel = ProductPerformanceViewModel(dataSource: dataSource)
    }

    override func tearDown() async throws {
        viewModel = nil
        dataSource = nil
        container = nil
        try await super.tearDown()
    }

    /// 三個商品：1 個賣過、1 個沒賣過、1 個「已下架且沒賣過」
    /// （最後那個靠複製場次會產生，見 §5.1 的決定）
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
        categoryId = UUID()
        category.id = categoryId
        category.name = "甜點"
        category.createdAt = Date()
        category.isDisabled = false
        category.sortOrder = 0
        category.event = event

        func makeProduct(name: String, sortOrder: Int16, isDisabled: Bool) -> CDProductEntity {
            let product = CDProductEntity(context: context)
            product.id = UUID()
            product.eventId = event.id
            product.name = name
            product.price = NSDecimalNumber(value: 100)
            product.stock = 10
            product.categoryId = category.id
            product.isDisabled = isDisabled
            product.sortOrder = sortOrder
            product.createdAt = Date()
            product.category = category
            return product
        }

        let sold = makeProduct(name: "賣過的", sortOrder: 0, isDisabled: false)
        let unsold = makeProduct(name: "沒賣過的", sortOrder: 1, isDisabled: false)
        let disabledUnsold = makeProduct(name: "下架且沒賣過的", sortOrder: 2, isDisabled: true)
        soldProductId = sold.id
        unsoldProductId = unsold.id
        disabledUnsoldProductId = disabledUnsold.id

        let transaction = CDTransactionEntity(context: context)
        transaction.id = UUID()
        transaction.eventId = event.id
        transaction.eventTitle = event.title
        transaction.currency = "TWD"
        transaction.totalAmount = NSDecimalNumber(value: 200)
        transaction.paymentMethod = PaymentMethod.cash.rawValue
        transaction.timestamp = Date()
        transaction.items = [
            .mock(productId: sold.id, name: "賣過的", price: 100,
                  categoryId: category.id, category: "甜點", quantity: 2)
        ]
        transaction.event = event

        try context.save()
    }

    // MARK: -

    func testRankingListsOnlySoldProducts() {
        viewModel.loadData()

        XCTAssertEqual(viewModel.topProducts.count, 1)
        XCTAssertEqual(viewModel.topProducts.first?.productId, soldProductId)
        XCTAssertEqual(viewModel.topProducts.first?.rank, 1)
        XCTAssertEqual(viewModel.topProducts.first?.salesCount, 2)
    }

    /// ⭐ §5.1：沒賣掉的商品不能是隱形的 —— 只從交易反推的話根本發現不了它們
    func testUnsoldListContainsEveryProductWithoutSales() {
        viewModel.loadData()

        let unsoldIds = Set(viewModel.unsoldProducts.map(\.id))
        XCTAssertEqual(unsoldIds, [unsoldProductId, disabledUnsoldProductId])
        XCTAssertFalse(unsoldIds.contains(soldProductId))
    }

    /// 「已下架且沒賣過」不做特例：一樣列進未售出，只是多帶一個標記
    func testDisabledUnsoldProductIsListedAndFlagged() {
        viewModel.loadData()

        let disabled = viewModel.unsoldProducts.first { $0.id == disabledUnsoldProductId }
        XCTAssertNotNil(disabled)
        XCTAssertTrue(disabled?.isDisabled == true)

        let normal = viewModel.unsoldProducts.first { $0.id == unsoldProductId }
        XCTAssertTrue(normal?.isDisabled == false)
    }

    func testUnsoldProductsFollowProductSortOrder() {
        viewModel.loadData()

        XCTAssertEqual(viewModel.unsoldProducts.map(\.name), ["沒賣過的", "下架且沒賣過的"])
    }

    func testSoldAndUnsoldTogetherCoverAllProducts() {
        viewModel.loadData()

        let total = viewModel.topProducts.count + viewModel.unsoldProducts.count
        XCTAssertEqual(total, dataSource.products.count,
                       "每個商品只會出現在其中一區，且不能漏掉任何一個")
    }

    func testHasSalesInRangeDrivesEmptyState() {
        viewModel.loadData()
        XCTAssertTrue(viewModel.hasSalesInRange)

        // 一個沒有任何交易的時間範圍
        var longAgo = ReportTimeRange(event: dataSource.event, type: .custom)
        longAgo.customStart = Date(timeIntervalSince1970: 0)
        longAgo.customEnd = Date(timeIntervalSince1970: 1)
        viewModel.loadData(timeRange: longAgo)

        XCTAssertFalse(viewModel.hasSalesInRange, "沒有交易時要能顯示空狀態")
        XCTAssertTrue(viewModel.topProducts.isEmpty)
        XCTAssertEqual(viewModel.unsoldProducts.count, 3, "所有商品都算未售出")
    }

    func testAverageUnitPriceFlowsThroughToPerformanceData() {
        viewModel.loadData()

        XCTAssertEqual(viewModel.topProducts.first?.averageUnitPrice, 100)
    }
}
