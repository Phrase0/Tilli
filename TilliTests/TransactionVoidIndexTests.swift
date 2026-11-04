import XCTest
import CoreData
@testable import Tilli

final class TransactionVoidIndexTests: XCTestCase {

    private var container: NSPersistentContainer!

    override func setUp() {
        super.setUp()
        container = TestStore.makeInMemoryContainer()
    }

    private func makeVoid(transactionId: UUID, eventId: UUID = UUID(), voidedAt: Date = Date()) -> TransactionVoidModel {
        TransactionVoidModel(id: UUID(), transactionId: transactionId, eventId: eventId,
                             voidedAt: voidedAt, reason: .other, note: nil, restocked: false)
    }

    private func insert(_ transaction: TransactionModel) {
        let entity = CDTransactionEntity(context: container.viewContext)
        entity.update(from: transaction, context: container.viewContext)
    }

    private func insert(_ record: TransactionVoidModel) {
        let entity = CDTransactionVoidEntity(context: container.viewContext)
        entity.update(from: record, context: container.viewContext)
    }

    func testEffectiveExcludesVoidedAndKeepsOrder() {
        let a = TransactionModel.mock(totalAmount: 100)
        let b = TransactionModel.mock(totalAmount: 200)
        let c = TransactionModel.mock(totalAmount: 300)
        let index = TransactionVoidIndex(voids: [makeVoid(transactionId: b.id)])
        XCTAssertEqual(index.effective([c, b, a]).map(\.id), [c.id, a.id])
        XCTAssertTrue(index.isVoided(b.id))
        XCTAssertFalse(index.isVoided(a.id))
    }

    func testEarliestVoidWinsWhenDuplicated() {
        let tid = UUID()
        let early = makeVoid(transactionId: tid, voidedAt: Date(timeIntervalSince1970: 100))
        let late = makeVoid(transactionId: tid, voidedAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(TransactionVoidIndex(voids: [late, early]).voidRecord(for: tid)?.id, early.id)
        XCTAssertEqual(TransactionVoidIndex(voids: [early, late]).voidRecord(for: tid)?.id, early.id)
    }

    func testEffectiveSummaryExcludesVoided() throws {
        let eventId = UUID()
        let a = TransactionModel.mock(eventId: eventId, totalAmount: 100)
        let b = TransactionModel.mock(eventId: eventId, totalAmount: 200)
        let c = TransactionModel.mock(eventId: eventId, totalAmount: 300)
        [a, b, c].forEach(insert)
        insert(makeVoid(transactionId: b.id, eventId: eventId))
        try container.viewContext.save()

        let repo = TransactionRepository(container: container)
        let summary = repo.effectiveSummary(forEventId: eventId)
        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(summary.total, 400)
    }

    func testFetchVoidsOnlyReturnsThatEvent() throws {
        let eventA = UUID(), eventB = UUID()
        let inA = makeVoid(transactionId: UUID(), eventId: eventA)
        insert(inA)
        insert(makeVoid(transactionId: UUID(), eventId: eventB))
        try container.viewContext.save()

        let repo = TransactionRepository(container: container)
        XCTAssertEqual(repo.fetchVoids(forEventId: eventA).map(\.id), [inA.id])
    }
}
