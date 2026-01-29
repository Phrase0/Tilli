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
    @NSManaged public var session: CDSessionEntity?

    // MARK: - Sync 相關欄位
    @NSManaged public var userId: String?        // 所屬用戶 ID
    @NSManaged public var sessionId: UUID?       // Firestore 同步用
    @NSManaged public var syncStatus: String?    // "synced" | "pending" | "error"
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
        self.sessionId = model.sessionId
    }

    func toModel() -> InventoryChangeModel {
        return InventoryChangeModel(
            id: self.id,
            productId: self.productId,
            change: Int(self.change),
            reason: InventoryChangeReason(rawValue: self.reason) ?? .adjustment,
            customReason: self.customReason,
            transactionId: self.transactionId,
            timestamp: self.timestamp,
            sessionId: self.sessionId ?? self.session?.id
        )
    }
}
