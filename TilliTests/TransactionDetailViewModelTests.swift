//
//  TransactionDetailViewModelTests.swift
//  TilliTests
//
//  交易明細頁 ViewModel 與共用的交易顯示文字（交易編號、付款方式）、作廢狀態。
//

import XCTest
import CoreData
@testable import Tilli

@MainActor
final class TransactionDetailViewModelTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var dataSource: EventDataSource!
    private let voidedTransactionId = UUID()
    private let voidedAt = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        try await super.setUp()
        container = TestStore.makeInMemoryContainer()
        let eventId = try seed()

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

    /// 一筆已作廢的交易（附說明、已回流）
    private func seed() throws -> UUID {
        let context = container.viewContext

        let event = CDEventEntity(context: context)
        event.id = UUID()
        event.title = "測試場次"
        event.startDate = Date()
        event.createdAt = Date()
        event.currency = "TWD"
        event.dateType = EventDateType.single.rawValue

        let entity = CDTransactionEntity(context: context)
        entity.id = voidedTransactionId
        entity.eventId = event.id
        entity.eventTitle = event.title
        entity.currency = "TWD"
        entity.totalAmount = 0
        entity.paymentMethod = PaymentMethod.cash.rawValue
        entity.timestamp = Date()
        entity.items = []
        entity.appliedDiscounts = []
        entity.event = event

        let void = CDTransactionVoidEntity(context: context)
        void.id = UUID()
        void.transactionId = voidedTransactionId
        void.eventId = event.id
        void.voidedAt = voidedAt
        void.reason = VoidReason.returned.rawValue
        void.note = "客人退回"
        void.restocked = true

        try context.save()
        return event.id
    }

    private func makeViewModel(_ transaction: TransactionModel) -> TransactionDetailViewModel {
        TransactionDetailViewModel(transaction: transaction, dataSource: dataSource)
    }

    private func transaction(currency: String = "TWD", paymentMethod: PaymentMethod = .cash) -> TransactionModel {
        TransactionModel(
            id: UUID(uuidString: "abcdef12-3456-7890-abcd-ef1234567890")!,
            eventId: UUID(),
            eventTitle: "測試場次",
            currency: currency,
            items: [],
            totalAmount: 0,
            paymentMethod: paymentMethod,
            timestamp: Date()
        )
    }

    func testTransactionNumberUsesFirstEightCharactersUppercased() {
        XCTAssertEqual(TransactionModel.displayNumber(for: UUID(uuidString: "abcdef12-3456-7890-abcd-ef1234567890")!), "TXNABCDEF12")
        XCTAssertEqual(makeViewModel(transaction()).transactionNumber, "TXNABCDEF12")
    }

    func testPaymentMethodTextIsLocalized() {
        XCTAssertEqual(makeViewModel(transaction(paymentMethod: .cash)).paymentMethodText,
                       String.localized("transactionPaymentCash"))
        XCTAssertEqual(makeViewModel(transaction(paymentMethod: .ePayment)).paymentMethodText,
                       String.localized("transactionPaymentEPayment"))
    }

    func testAmountsUseTheTransactionCurrency() {
        let viewModel = makeViewModel(transaction(currency: "USD"))
        XCTAssertEqual(viewModel.formatAmount(Decimal(string: "1.5")!), MoneyHelper.format(Decimal(string: "1.5")!, currencyCode: "USD"))
        XCTAssertEqual(viewModel.currency, "USD")
    }

    func testVoidRecordLoadedFromDataSource() {
        let notVoided = makeViewModel(transaction())
        XCTAssertNil(notVoided.voidRecord)
        XCTAssertFalse(notVoided.isVoided)

        let voided = makeViewModel(dataSource.allTransactions.first { $0.id == voidedTransactionId }!)
        XCTAssertTrue(voided.isVoided)
        XCTAssertEqual(voided.voidRecord?.reason, .returned)
        XCTAssertEqual(voided.voidRecord?.note, "客人退回")
        XCTAssertEqual(voided.voidRecord?.restocked, true)
        XCTAssertEqual(voided.voidRecord?.voidedAt, voidedAt)
    }
}
