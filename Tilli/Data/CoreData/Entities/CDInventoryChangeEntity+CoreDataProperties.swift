//
//  CDInventoryChangeEntity+CoreDataProperties.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/12.
//

import Foundation
import CoreData

extension CDInventoryChangeEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDInventoryChangeEntity> {
        return NSFetchRequest<CDInventoryChangeEntity>(entityName: "CDInventoryChangeEntity")
    }

    @NSManaged public var id: UUID
    @NSManaged public var productId: UUID
    @NSManaged public var change: Int32
    @NSManaged public var reason: String
    @NSManaged public var customReason: String?
    @NSManaged public var transactionId: UUID?
    @NSManaged public var timestamp: Date
    @NSManaged public var bundleId: UUID?        // 來自哪個組合／套餐
    @NSManaged public var bundleName: String?    // 組合名稱快照
    @NSManaged public var event: CDEventEntity?
    @NSManaged public var product: CDProductEntity?

    // MARK: - Sync 相關欄位
    @NSManaged public var userId: String?        // 所屬用戶 ID
    @NSManaged public var eventId: UUID?       // Firestore 同步用
    @NSManaged public var syncStatus: String?    // "synced" | "pending" | "error"
    @NSManaged public var updatedAt: Date?       // 建立當下的時間，之後永不改變（append-only）
}

extension CDInventoryChangeEntity {

    func update(from model: InventoryChangeModel, context: NSManagedObjectContext) {
        self.id = model.id
        self.productId = model.productId
        self.change = Int32(model.change)
        self.reason = model.reason.rawValue
        self.customReason = model.customReason
        self.transactionId = model.transactionId
        self.timestamp = model.timestamp
        self.eventId = model.eventId
        self.bundleId = model.bundleId
        self.bundleName = model.bundleName
    }

    func toModel() -> InventoryChangeModel {
        InventoryChangeModel(entity: self)
    }
}
