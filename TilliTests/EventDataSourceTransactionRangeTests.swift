//
//  EventDataSourceTransactionRangeTests.swift
//  TilliTests
//
//  EventDataSource.transactions(in:) 的邊界（FEATURE_PLAN §11 第 2 批 2.3）：
//  nil 回傳全部；落在 start／end 上的交易包含在內；補記帳依 displayDate（occurredAt）落點。
//

import XCTest
import CoreData
@testable import Tilli

@MainActor
final class EventDataSourceTransactionRangeTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var dataSource: EventDataSource!
    private var eventId: UUID!

    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var end: Date { start.addingTimeInterval(3600) }

    private var atStartId: UUID!
    private var atEndId: UUID!
    private var beforeStartId: UUID!
    private var afterEndId: UUID!
    /// 記錄時間在範圍外、實際發生時間在範圍內的補記帳
    private var backdatedInsideId: UUID!
    /// 記錄時間在範圍內、實際發生時間在範圍外的補記帳
    private var backdatedOutsideId: UUID!

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

    private func seed() throws {
        let context = container.viewContext
        let event = CDEventEntity(context: context)
        eventId = UUID()
        event.id = eventId
        event.title = "測試場次"
        event.startDate = start
        event.createdAt = start
        event.currency = "TWD"
        event.dateType = EventDateType.single.rawValue

        func makeTransaction(timestamp: Date, occurredAt: Date? = nil) -> UUID {
            let transaction = CDTransactionEntity(context: context)
            transaction.id = UUID()
            transaction.eventId = eventId
            transaction.eventTitle = event.title
            transaction.currency = "TWD"
            transaction.totalAmount = NSDecimalNumber(value: 100)
            transaction.paymentMethod = PaymentMethod.cash.rawValue
            transaction.timestamp = timestamp
            transaction.occurredAt = occurredAt
            transaction.items = []
            transaction.event = event
            return transaction.id
        }

        atStartId = makeTransaction(timestamp: start)
        atEndId = makeTransaction(timestamp: end)
        beforeStartId = makeTransaction(timestamp: start.addingTimeInterval(-1))
        afterEndId = makeTransaction(timestamp: end.addingTimeInterval(1))
        backdatedInsideId = makeTransaction(timestamp: end.addingTimeInterval(86_400), occurredAt: start.addingTimeInterval(60))
        backdatedOutsideId = makeTransaction(timestamp: start.addingTimeInterval(60), occurredAt: start.addingTimeInterval(-86_400))

        try context.save()
    }

    private func ids(in range: DateInterval?) -> Set<UUID> {
        Set(dataSource.transactions(in: range).map(\.id))
    }

    func testNilRangeReturnsAllTransactions() {
        XCTAssertEqual(ids(in: nil).count, 6)
    }

    func testTransactionsExactlyOnStartAndEndAreIncluded() {
        let result = ids(in: DateInterval(start: start, end: end))

        XCTAssertTrue(result.contains(atStartId))
        XCTAssertTrue(result.contains(atEndId))
        XCTAssertFalse(result.contains(beforeStartId))
        XCTAssertFalse(result.contains(afterEndId))
    }

    func testBackdatedTransactionsFollowOccurredAtNotTimestamp() {
        let result = ids(in: DateInterval(start: start, end: end))

        XCTAssertTrue(result.contains(backdatedInsideId))
        XCTAssertFalse(result.contains(backdatedOutsideId))
    }
}
