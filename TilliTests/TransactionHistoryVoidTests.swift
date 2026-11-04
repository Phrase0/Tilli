//
//  TransactionHistoryVoidTests.swift
//  TilliTests
//
//  交易紀錄列表保留作廢交易，但每日合計、筆數與交易 CSV 只算有效交易；
//  庫存異動 CSV 的交易編號欄對銷售出庫與作廢回流都有值。
//

import XCTest
import CoreData
@testable import Tilli

@MainActor
final class TransactionHistoryVoidTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var eventId: UUID!
    private var productId: UUID!
    private var context: NSManagedObjectContext { container.viewContext }

    override func setUp() async throws {
        try await super.setUp()
        container = TestStore.makeInMemoryContainer()

        let event = CDEventEntity(context: context)
        event.id = UUID()
        event.title = "測試場次"
        event.startDate = Date()
        event.createdAt = Date()
        event.currency = "TWD"
        event.dateType = EventDateType.single.rawValue
        eventId = event.id

        let category = CDCategoryEntity(context: context)
        category.id = UUID()
        category.name = "甜點"
        category.createdAt = Date()
        category.isDisabled = false
        category.sortOrder = 0
        category.event = event

        let product = CDProductEntity(context: context)
        product.id = UUID()
        productId = product.id
        product.eventId = event.id
        product.name = "布丁"
        product.price = NSDecimalNumber(value: 100)
        product.stock = 10
        product.categoryId = category.id
        product.isDisabled = false
        product.sortOrder = 0
        product.createdAt = Date()
        product.category = category
        try context.save()
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private func makeDataSource() -> EventDataSource {
        let event = EventRepository(container: container).fetchEvent(by: eventId)!
        let dataSource = EventDataSource(event: event)
        dataSource.attach(
            eventRepository: EventRepository(container: container),
            productRepository: ProductRepository(container: container),
            transactionRepository: TransactionRepository(container: container),
            inventoryChangeRepository: InventoryChangeRepository(container: container)
        )
        return dataSource
    }

    @discardableResult
    private func addTransaction(price: Decimal, voided: Bool) throws -> UUID {
        let event = try fetchEventEntity()
        let items = [SummaryItemModel.mock(productId: productId, name: "布丁", price: price,
                                           categoryId: UUID(), category: "甜點")]
        let entity = CDTransactionEntity(context: context)
        entity.id = UUID()
        entity.eventId = eventId
        entity.eventTitle = "測試場次"
        entity.currency = "TWD"
        entity.totalAmount = NSDecimalNumber(decimal: items.subtotal)
        entity.paymentMethod = PaymentMethod.cash.rawValue
        entity.timestamp = Date()
        entity.items = RevenueAllocator.allocate(items, discounts: [], currency: "TWD")
        entity.appliedDiscounts = []
        entity.event = event

        if voided {
            let void = CDTransactionVoidEntity(context: context)
            void.id = UUID()
            void.transactionId = entity.id
            void.eventId = eventId
            void.voidedAt = Date()
            void.reason = VoidReason.other.rawValue
            void.restocked = false
        }
        try context.save()
        return entity.id
    }

    private func fetchEventEntity() throws -> CDEventEntity {
        try XCTUnwrap(try context.fetch(CDEventEntity.fetchRequest()).first)
    }

    private func loadedViewModel() -> TransactionHistoryViewModel {
        let viewModel = TransactionHistoryViewModel(dataSource: makeDataSource())
        viewModel.loadData()
        return viewModel
    }

    func testDailyGroupTotalsExcludeVoided() throws {
        try addTransaction(price: 100, voided: false)
        let voidedId = try addTransaction(price: 200, voided: true)

        let viewModel = loadedViewModel()
        let group = try XCTUnwrap(viewModel.filteredGroupedTransactions.first)

        XCTAssertEqual(group.transactions.count, 2)
        XCTAssertEqual(group.totalAmount, 100)
        XCTAssertEqual(group.count, 1)
        XCTAssertEqual(group.voidedIds, [voidedId])
        XCTAssertEqual(viewModel.eventTotalAmount, 100)
        XCTAssertTrue(viewModel.isVoided(group.transactions.first { $0.id == voidedId }!))
    }

    func testAllVoidedDayShowsZero() throws {
        try addTransaction(price: 200, voided: true)

        let group = try XCTUnwrap(loadedViewModel().filteredGroupedTransactions.first)

        XCTAssertEqual(group.transactions.count, 1)
        XCTAssertEqual(group.totalAmount, 0)
        XCTAssertEqual(group.count, 0)
    }

    func testTransactionCSVExcludesVoided() throws {
        let keptId = try addTransaction(price: 100, voided: false)
        let voidedId = try addTransaction(price: 200, voided: true)

        let csv = loadedViewModel().generateCSVContent()

        XCTAssertTrue(csv.contains(TransactionModel.displayNumber(for: keptId)))
        XCTAssertFalse(csv.contains(TransactionModel.displayNumber(for: voidedId)))
    }

    func testInventoryCSVShowsTransactionNumberForVoidRestock() throws {
        let salesTxId = UUID()
        let restockTxId = UUID()
        let manualTxId = UUID()
        let event = try fetchEventEntity()
        let product = try XCTUnwrap(try context.fetch(CDProductEntity.fetchRequest()).first)

        func addChange(_ reason: InventoryChangeReason, transactionId: UUID?, amount: Int) {
            let model = InventoryChangeModel(productId: productId, change: amount, reason: reason,
                                             transactionId: transactionId, timestamp: Date())
            let entity = CDInventoryChangeEntity(context: context)
            entity.update(from: model, context: context)
            entity.eventId = eventId
            entity.event = event
            entity.product = product
        }
        addChange(.salesOut, transactionId: salesTxId, amount: -1)
        addChange(.voidRestock, transactionId: restockTxId, amount: 1)
        addChange(.adjustment, transactionId: manualTxId, amount: 2)
        try context.save()

        let dataSource = makeDataSource()
        let viewModel = InventoryViewModel(dataSource: dataSource)
        viewModel.loadData()
        let csv = viewModel.generateInventoryDetailCSV()

        XCTAssertTrue(csv.contains(TransactionModel.displayNumber(for: salesTxId)))
        XCTAssertTrue(csv.contains(TransactionModel.displayNumber(for: restockTxId)))
        XCTAssertFalse(csv.contains(TransactionModel.displayNumber(for: manualTxId)))
    }
}
