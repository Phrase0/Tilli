//
//  LocalDataManagerTests.swift
//  TilliTests
//
//  本機資料管理：歸戶改寫 userId 與登出清除要涵蓋作廢紀錄（`CDTransactionVoidEntity` 沒有 relationship，不會被 cascade）。
//

import XCTest
import CoreData
@testable import Tilli

final class LocalDataManagerTests: XCTestCase {

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

    @discardableResult
    private func addVoid(userId: String) throws -> CDTransactionVoidEntity {
        let void = CDTransactionVoidEntity(context: context)
        void.id = UUID()
        void.transactionId = UUID()
        void.eventId = UUID()
        void.voidedAt = Date()
        void.reason = VoidReason.other.rawValue
        void.restocked = false
        void.userId = userId
        void.syncStatus = SyncStatus.synced.rawValue
        try context.save()
        return void
    }

    private func voidCount() throws -> Int {
        try context.count(for: CDTransactionVoidEntity.fetchRequest())
    }

    func testClearAllLocalDataDeletesVoidRecords() throws {
        try addVoid(userId: "guest")
        XCTAssertEqual(try voidCount(), 1)

        LocalDataManager(context: context).clearAllLocalData()

        XCTAssertEqual(try voidCount(), 0)
    }

    func testUpdateAllUserIdsRewritesVoidRecords() throws {
        let void = try addVoid(userId: "guest")

        LocalDataManager(context: context).updateAllUserIds(from: "guest", to: "member")

        XCTAssertEqual(void.userId, "member")
        XCTAssertEqual(void.syncStatus, SyncStatus.pending.rawValue)
    }
}
