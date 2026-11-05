//
//  VoidTransactionViewModelTests.swift
//  TilliTests
//
//  作廢視窗 VM：原因與庫存方式都選了才可送出；已作廢不可送出；確認框文字。
//  寫入（作廢紀錄＋回流＋庫存一次存檔）的測試在 AtomicLedgerWriteTests。
//

import XCTest
import CoreData
@testable import Tilli

@MainActor
final class VoidTransactionViewModelTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var dataSource: EventDataSource!

    private let openTransactionId = UUID(uuidString: "1a2b3c4d-0000-0000-0000-000000000001")!
    private let voidedTransactionId = UUID(uuidString: "9f8e7d6c-0000-0000-0000-000000000002")!

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

    /// 兩筆 $350 交易：一筆未作廢、一筆已作廢
    private func seed() throws -> UUID {
        let context = container.viewContext

        let event = CDEventEntity(context: context)
        event.id = UUID()
        event.title = "測試場次"
        event.startDate = Date()
        event.createdAt = Date()
        event.currency = "TWD"
        event.dateType = EventDateType.single.rawValue

        for id in [openTransactionId, voidedTransactionId] {
            let items = [SummaryItemModel.mock(productId: UUID(), name: "商品", price: 350,
                                               categoryId: UUID(), category: "甜點")]
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

        let void = CDTransactionVoidEntity(context: context)
        void.id = UUID()
        void.transactionId = voidedTransactionId
        void.eventId = event.id
        void.voidedAt = Date()
        void.reason = VoidReason.inputError.rawValue
        void.restocked = true

        try context.save()
        return event.id
    }

    private func makeViewModel(for id: UUID) -> VoidTransactionViewModel {
        let transaction = dataSource.allTransactions.first { $0.id == id }!
        return VoidTransactionViewModel(transaction: transaction, dataSource: dataSource)
    }

    func testCanSubmitRequiresReasonAndRestockChoice() {
        let viewModel = makeViewModel(for: openTransactionId)
        XCTAssertNil(viewModel.selectedReason)
        XCTAssertNil(viewModel.restockChoice)
        XCTAssertFalse(viewModel.canSubmit)

        viewModel.selectedReason = .returned
        XCTAssertFalse(viewModel.canSubmit)

        viewModel.selectedReason = nil
        viewModel.restockChoice = false
        XCTAssertFalse(viewModel.canSubmit)

        viewModel.selectedReason = .returned
        XCTAssertTrue(viewModel.canSubmit)
    }

    func testCannotSubmitWhenAlreadyVoided() {
        let viewModel = makeViewModel(for: voidedTransactionId)
        viewModel.selectedReason = .other
        viewModel.restockChoice = true
        XCTAssertFalse(viewModel.canSubmit)
    }

    func testConfirmTextUsesDisplayNumberAmountAndRestockChoice() {
        let viewModel = makeViewModel(for: openTransactionId)
        let amount = MoneyHelper.format(350, currencyCode: "TWD")
        XCTAssertEqual(viewModel.transactionNumber, "TXN1A2B3C4D")
        XCTAssertEqual(viewModel.amountText, amount)
        XCTAssertEqual(viewModel.confirmTitle, String.localized("voidConfirmTitle \("TXN1A2B3C4D") \(amount)"))
        XCTAssertTrue(viewModel.confirmTitle.contains("TXN1A2B3C4D"))
        XCTAssertTrue(viewModel.confirmTitle.contains(amount))
        XCTAssertFalse(viewModel.confirmTitle.hasPrefix("voidConfirmTitle"), "字串要從 Localizable.xcstrings 取到")

        viewModel.restockChoice = true
        XCTAssertEqual(viewModel.confirmMessage,
                       String.localized("voidConfirmMessage") + "\n" + String.localized("voidConfirmRestock"))

        viewModel.restockChoice = false
        XCTAssertEqual(viewModel.confirmMessage,
                       String.localized("voidConfirmMessage") + "\n" + String.localized("voidConfirmNoRestock"))
    }
}
