import XCTest
import CoreData
@testable import Tilli

final class TransactionVoidModelTests: XCTestCase {

    private var container: NSPersistentContainer!

    override func setUp() {
        super.setUp()
        container = TestStore.makeInMemoryContainer()
    }

    private func makeEntity(reason: String, note: String?) -> CDTransactionVoidEntity {
        let entity = CDTransactionVoidEntity(context: container.viewContext)
        entity.id = UUID()
        entity.transactionId = UUID()
        entity.eventId = UUID()
        entity.voidedAt = Date(timeIntervalSince1970: 1_700_000_000)
        entity.reason = reason
        entity.note = note
        entity.restocked = true
        return entity
    }

    func testEntityRoundTripKeepsAllFields() {
        let entity = makeEntity(reason: VoidReason.returned.rawValue, note: "客人說太甜")
        let model = entity.toModel()
        XCTAssertEqual(model.id, entity.id)
        XCTAssertEqual(model.transactionId, entity.transactionId)
        XCTAssertEqual(model.eventId, entity.eventId)
        XCTAssertEqual(model.voidedAt, entity.voidedAt)
        XCTAssertEqual(model.reason, .returned)
        XCTAssertEqual(model.note, "客人說太甜")
        XCTAssertTrue(model.restocked)

        let other = CDTransactionVoidEntity(context: container.viewContext)
        other.update(from: model, context: container.viewContext)
        XCTAssertEqual(other.toModel(), model)
    }

    func testEmptyNoteIsStoredAsNil() {
        let entity = makeEntity(reason: VoidReason.other.rawValue, note: "")
        XCTAssertNil(entity.toModel().note)
        let model = TransactionVoidModel(id: UUID(), transactionId: UUID(), eventId: UUID(),
                                         voidedAt: Date(), reason: .other, note: "", restocked: false)
        XCTAssertNil(model.note)
    }

    func testUnknownReasonFallsBackToOther() {
        let entity = makeEntity(reason: "somethingNew", note: nil)
        XCTAssertEqual(entity.toModel().reason, .other)
    }

    func testVoidRestockIsIncreaseButNotManuallySelectable() {
        XCTAssertTrue(InventoryChangeReason.voidRestock.isIncrease)
        XCTAssertFalse(InventoryChangeReason.increaseReasons.contains(.voidRestock))
        XCTAssertFalse(InventoryChangeReason.decreaseReasons.contains(.voidRestock))
        XCTAssertFalse(InventoryChangeReason.availableReasons(for: 5).contains(.voidRestock))
        XCTAssertFalse(InventoryChangeReason.availableReasons(for: -5).contains(.voidRestock))
        XCTAssertEqual(InventoryChangeReason.voidRestock.displayName, String.localized("inventoryReasonVoidRestock"))
    }
}
