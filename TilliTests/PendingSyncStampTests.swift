//
//  PendingSyncStampTests.swift
//  TilliTests
//
//  Created by Peiyun on 2026/9/13.
//
//  「待同步」標記：syncStatus 與 updatedAt 一定一起設定。
//

import XCTest
import CoreData
@testable import Tilli

final class PendingSyncStampTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext { container.viewContext }

    override func setUp() {
        super.setUp()
        container = TestStore.makeInMemoryContainer()
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    // MARK: - 兩個欄位一定一起設定

    func testProductGetsBothSyncStatusAndUpdatedAt() {
        let product = CDProductEntity(context: context)

        product.markPendingSync()

        XCTAssertEqual(product.syncStatus, SyncStatus.pending.rawValue)
        XCTAssertNotNil(product.updatedAt)
    }

    /// ⭐ 交易也要設 `updatedAt`：它是增量下載與「最後寫入者勝」的依據，漏設會讓增量下載抓不到。
    func testTransactionGetsUpdatedAtWhichWasPreviouslyMissing() {
        let transaction = CDTransactionEntity(context: context)

        transaction.markPendingSync()

        XCTAssertEqual(transaction.syncStatus, SyncStatus.pending.rawValue)
        XCTAssertNotNil(transaction.updatedAt, "1.11 已補上這個欄位，markPendingSync 必須設定它")
    }

    func testInventoryChangeGetsUpdatedAtWhichWasPreviouslyMissing() {
        let change = CDInventoryChangeEntity(context: context)

        change.markPendingSync()

        XCTAssertEqual(change.syncStatus, SyncStatus.pending.rawValue)
        XCTAssertNotNil(change.updatedAt)
    }

    func testCategoryAndEventAndQRCodeAlsoCovered() {
        let category = CDCategoryEntity(context: context)
        let event = CDEventEntity(context: context)
        let qrCode = CDQRCodeEntity(context: context)

        category.markPendingSync()
        event.markPendingSync()
        qrCode.markPendingSync()

        for entity in [category as NSManagedObject, event, qrCode] {
            XCTAssertEqual(entity.value(forKey: "syncStatus") as? String, SyncStatus.pending.rawValue)
            XCTAssertNotNil(entity.value(forKey: "updatedAt"))
        }
    }

    // MARK: - 批次一致性

    func testExplicitDateIsUsedSoBatchWritesShareOneTimestamp() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entities = (0..<5).map { _ in CDProductEntity(context: context) }

        for entity in entities {
            entity.markPendingSync(at: now)
        }

        XCTAssertTrue(
            entities.allSatisfy { $0.updatedAt == now },
            "同一批寫入應共用同一個 updatedAt，之後才能靠它判斷是同一次變更"
        )
    }

    func testDefaultDateIsRoughlyNow() {
        let before = Date()
        let product = CDProductEntity(context: context)

        product.markPendingSync()

        let updatedAt = try? XCTUnwrap(product.updatedAt)
        XCTAssertNotNil(updatedAt)
        XCTAssertGreaterThanOrEqual(updatedAt!, before)
        XCTAssertLessThanOrEqual(updatedAt!, Date())
    }

    // MARK: - 覆寫

    func testMarkPendingSyncOverwritesPreviousSyncedState() {
        let product = CDProductEntity(context: context)
        product.syncStatus = SyncStatus.synced.rawValue
        product.updatedAt = Date(timeIntervalSince1970: 0)

        product.markPendingSync()

        XCTAssertEqual(product.syncStatus, SyncStatus.pending.rawValue)
        XCTAssertGreaterThan(product.updatedAt!, Date(timeIntervalSince1970: 0))
    }
}
