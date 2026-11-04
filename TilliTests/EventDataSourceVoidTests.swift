//
//  EventDataSourceVoidTests.swift
//  TilliTests
//
//  EventDataSource.transactions 是有效交易（排除作廢）；allTransactions 含作廢。
//  報表用前者，交易紀錄列表與 TransactionIndex（鎖定）用後者。
//

import XCTest
import CoreData
@testable import Tilli

@MainActor
final class EventDataSourceVoidTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var dataSource: EventDataSource!
    private var eventId: UUID!

    private let keptProductId = UUID()
    private let voidedOnlyProductId = UUID()
    private var keptTransactionId = UUID()
    private var voidedTransactionId = UUID()

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
    }

    override func tearDown() async throws {
        dataSource = nil
        container = nil
        try await super.tearDown()
    }

    /// 兩筆交易：一筆有效（只賣 kept 商品）、一筆作廢（只賣 voidedOnly 商品）
    private func seed() throws {
        let context = container.viewContext

        let event = CDEventEntity(context: context)
        event.id = UUID()
        event.title = "測試場次"
        event.startDate = Date()
        event.createdAt = Date()
        event.currency = "TWD"
        event.dateType = EventDateType.single.rawValue
        eventId = event.id

        let categoryId = UUID()

        func addTransaction(id: UUID, productId: UUID, price: Decimal) {
            let items = [SummaryItemModel.mock(productId: productId, name: "商品", price: price,
                                               categoryId: categoryId, category: "甜點")]
            let entity = CDTransactionEntity(context: context)
            entity.id = id
            entity.eventId = event.id
            entity.eventTitle = event.title
            entity.currency = "TWD"
            entity.totalAmount = NSDecimalNumber(decimal: items.subtotal)
            entity.paymentMethod = PaymentMethod.cash.rawValue
            entity.timestamp = Date()
            entity.items = RevenueAllocator.allocate(items, discounts: [], currency: "TWD")
            entity.appliedDiscounts = []
            entity.event = event
        }

        addTransaction(id: keptTransactionId, productId: keptProductId, price: 100)
        addTransaction(id: voidedTransactionId, productId: voidedOnlyProductId, price: 250)

        let void = CDTransactionVoidEntity(context: context)
        void.id = UUID()
        void.transactionId = voidedTransactionId
        void.eventId = event.id
        void.voidedAt = Date()
        void.reason = VoidReason.other.rawValue
        void.restocked = false

        try context.save()
    }

    func testTransactionsExcludeVoidedButAllTransactionsKeepThem() {
        XCTAssertEqual(dataSource.allTransactions.count, 2)
        XCTAssertEqual(dataSource.transactions.map(\.id), [keptTransactionId])
        XCTAssertEqual(dataSource.allTransactions(in: nil).count, 2)
        XCTAssertEqual(dataSource.transactions(in: nil).map(\.id), [keptTransactionId])
        XCTAssertTrue(dataSource.voidIndex.isVoided(voidedTransactionId))

        let interval = DateInterval(start: Date().addingTimeInterval(-3600), end: Date().addingTimeInterval(3600))
        XCTAssertEqual(dataSource.allTransactions(in: interval).count, 2)
        XCTAssertEqual(dataSource.transactions(in: interval).count, 1)
    }

    func testSalesAnalyticsRevenueExcludesVoided() {
        let sales = SalesAnalyticsViewModel(dataSource: dataSource)
        sales.loadData()
        XCTAssertEqual(sales.salesOverview?.totalAmount, 100)
        XCTAssertEqual(sales.salesOverview?.totalAmount, dataSource.transactions.total)
    }

    func testProductPerformanceExcludesVoided() {
        let performance = ProductPerformanceViewModel(dataSource: dataSource)
        performance.loadData()
        XCTAssertEqual(performance.topProducts.first { $0.productId == keptProductId }?.salesCount, 1)
        XCTAssertNil(performance.topProducts.first { $0.productId == voidedOnlyProductId })
    }

    func testTransactionIndexStillCountsVoidedTransactions() {
        XCTAssertTrue(dataSource.transactionIndex.hasTransaction(productId: voidedOnlyProductId))
        XCTAssertTrue(dataSource.transactionIndex.hasTransaction(productId: keptProductId))
    }

    func testEventsSummaryMatchesDataSourceSummary() {
        let summary = TransactionRepository(container: container).effectiveSummary(forEventId: eventId)
        XCTAssertEqual(summary.count, dataSource.transactions.summary.count)
        XCTAssertEqual(summary.total, dataSource.transactions.summary.total)
        XCTAssertEqual(summary.count, 1)
    }
}
