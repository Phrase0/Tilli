//
//  CDPendingSyncOperation+CoreDataProperties.swift
//  Tilli
//
//  Created by Peiyun on 2026/1/29.
//  Created for CoreData + Firebase Sync
//  離線操作佇列 Entity，用於處理無網路時的 CRUD 操作
//

import Foundation
import CoreData

extension CDPendingSyncOperation {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDPendingSyncOperation> {
        return NSFetchRequest<CDPendingSyncOperation>(entityName: "CDPendingSyncOperation")
    }

    @NSManaged public var id: UUID                   // 操作的唯一識別碼
    @NSManaged public var entityType: String         // "session" | "category" | "product" | ...
    @NSManaged public var entityId: UUID             // 被操作的實體 ID
    @NSManaged public var operationType: String      // "create" | "update" | "delete"
    @NSManaged public var payload: Data?             // JSON encoded data
    @NSManaged public var createdAt: Date            // 操作建立時間（用於排序執行順序）
    @NSManaged public var retryCount: Int16          // 重試次數（最多 3 次）
    @NSManaged public var lastError: String?         // 最後一次錯誤訊息

}

extension CDPendingSyncOperation: Identifiable {

}

// MARK: - 操作類型

enum SyncOperationType: String {
    case create = "create"
    case update = "update"
    case delete = "delete"
}

// MARK: - 實體類型

enum SyncEntityType: String {
    case session = "session"
    case category = "category"
    case product = "product"
    case transaction = "transaction"
    case inventoryChange = "inventoryChange"
    case qrCode = "qrCode"
}

// MARK: - 同步狀態

enum SyncStatus: String {
    case synced = "synced"      // 已同步
    case pending = "pending"    // 等待同步
    case error = "error"        // 同步失敗
}
