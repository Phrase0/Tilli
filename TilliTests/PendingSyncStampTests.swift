//
//  PendingSyncStampTests.swift
//  TilliTests
//
//  Created by Peiyun on 2026/9/13.
//
//  對應 FEATURE_PLAN_V1.md §2.7（C1、C4）、§14.3 第 1 項，與測試清單 U8／U17。
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

    /// ⭐ C1：交易原本**只設 syncStatus、漏設 updatedAt**（而且那時根本沒有這個欄位）。
    /// `updatedAt` 是 pull-by-cursor 與 LWW 的依據，漏設會讓增量下載抓不到。
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
