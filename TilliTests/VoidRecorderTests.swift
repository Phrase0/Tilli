import XCTest
@testable import Tilli

final class VoidRecorderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 2_000)
    private let eventId = UUID()

    private func change(
        productId: UUID = UUID(),
        change: Int,
        reason: InventoryChangeReason = .salesOut,
        transactionId: UUID?,
        bundleId: UUID? = nil,
        bundleName: String? = nil
    ) -> InventoryChangeModel {
        InventoryChangeModel(
            productId: productId,
            change: change,
            reason: reason,
            customReason: nil,
            transactionId: transactionId,
            timestamp: Date(timeIntervalSince1970: 1_000),
            eventId: eventId,
            bundleId: bundleId,
            bundleName: bundleName
        )
    }

    private func make(
        transaction: TransactionModel,
        changes: [InventoryChangeModel] = [],
        voidIndex: TransactionVoidIndex = .empty,
        reason: VoidReason? = .inputError,
        note: String = "",
        restock: Bool? = true
    ) -> Result<VoidRecorder.Record, VoidRecorder.Rejection> {
        VoidRecorder.makeRecord(
            transaction: transaction,
            salesChanges: changes,
            voidIndex: voidIndex,
            reason: reason,
            note: note,
            restock: restock,
            now: now
        )
    }

    func testRestockMirrorsEachSalesOutChange() throws {
        let tx = TransactionModel.mock(eventId: eventId)
        let changes = [change(change: -2, transactionId: tx.id), change(change: -1, transactionId: tx.id)]
        let record = try make(transaction: tx, changes: changes).get()
        XCTAssertEqual(record.inventoryChanges.map(\.change), [2, 1])
        XCTAssertTrue(record.inventoryChanges.allSatisfy { $0.reason == .voidRestock })
        XCTAssertTrue(record.inventoryChanges.allSatisfy { $0.transactionId == tx.id })
        XCTAssertTrue(record.inventoryChanges.allSatisfy { $0.timestamp == now && $0.eventId == eventId })
        XCTAssertTrue(record.void.restocked)
    }

    func testRestockKeepsBundleIdAndName() throws {
        let tx = TransactionModel.mock(eventId: eventId)
        let bundleId = UUID()
        let changes = [
            change(change: -1, transactionId: tx.id, bundleId: bundleId, bundleName: "套餐A"),
            change(change: -1, transactionId: tx.id, bundleId: bundleId, bundleName: "套餐A")
        ]
        let record = try make(transaction: tx, changes: changes).get()
        XCTAssertEqual(record.inventoryChanges.count, 2)
        XCTAssertTrue(record.inventoryChanges.allSatisfy { $0.bundleId == bundleId && $0.bundleName == "套餐A" })
        XCTAssertTrue(record.inventoryChanges.allSatisfy { $0.customReason == nil })
    }

    func testRestockSumsSameProductAcrossRows() {
        let tx = TransactionModel.mock(eventId: eventId)
        let product = UUID()
        let restock = [
            change(productId: product, change: 1, reason: .voidRestock, transactionId: tx.id),
            change(productId: product, change: 1, reason: .voidRestock, transactionId: tx.id)
        ]
        let result = VoidRecorder.stockUpdates(for: restock, currentStock: [product: 5])
        XCTAssertEqual(result[product], 7)
    }

    func testStockUpdatesSkipUnknownProducts() {
        let known = UUID()
        let restock = [
            change(productId: known, change: 2, reason: .voidRestock, transactionId: nil),
            change(productId: UUID(), change: 3, reason: .voidRestock, transactionId: nil)
        ]
        XCTAssertEqual(VoidRecorder.stockUpdates(for: restock, currentStock: [known: 1]), [known: 3])
    }

    func testNoRestockWritesOnlyVoid() throws {
        let tx = TransactionModel.mock(eventId: eventId)
        let record = try make(transaction: tx, changes: [change(change: -2, transactionId: tx.id)], restock: false).get()
        XCTAssertTrue(record.inventoryChanges.isEmpty)
        XCTAssertFalse(record.void.restocked)
        XCTAssertEqual(record.void.transactionId, tx.id)
        XCTAssertEqual(record.void.eventId, tx.eventId)
        XCTAssertEqual(record.void.voidedAt, now)
    }

    func testIgnoresOtherTransactionsAndNonSalesChanges() throws {
        let tx = TransactionModel.mock(eventId: eventId)
        let changes = [
            change(change: -2, transactionId: tx.id),
            change(change: -5, transactionId: UUID()),
            change(change: 10, reason: .purchase, transactionId: nil),
            change(change: 1, reason: .voidRestock, transactionId: tx.id)
        ]
        let record = try make(transaction: tx, changes: changes).get()
        XCTAssertEqual(record.inventoryChanges.map(\.change), [2])
    }

    func testRejectsAlreadyVoided() {
        let tx = TransactionModel.mock(eventId: eventId)
        let existing = TransactionVoidModel(
            id: UUID(), transactionId: tx.id, eventId: eventId, voidedAt: now,
            reason: .other, note: nil, restocked: false
        )
        let result = make(transaction: tx, voidIndex: TransactionVoidIndex(voids: [existing]))
        XCTAssertEqual(result.failureValue, .alreadyVoided)
    }

    func testRejectsMissingReasonOrRestockChoice() {
        let tx = TransactionModel.mock(eventId: eventId)
        XCTAssertEqual(make(transaction: tx, reason: nil).failureValue, .missingReason)
        XCTAssertEqual(make(transaction: tx, restock: nil).failureValue, .missingRestockChoice)
    }

    func testBlankNoteStoredAsNil() throws {
        let tx = TransactionModel.mock(eventId: eventId)
        XCTAssertNil(try make(transaction: tx, note: "  \n ").get().void.note)
        XCTAssertEqual(try make(transaction: tx, note: " 重複輸入 ").get().void.note, "重複輸入")
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
