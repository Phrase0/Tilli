//
//  CDTransactionVoidEntity+CoreDataProperties.swift
//  Tilli
//

import Foundation
import CoreData

extension CDTransactionVoidEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTransactionVoidEntity> {
        return NSFetchRequest<CDTransactionVoidEntity>(entityName: "CDTransactionVoidEntity")
    }

    @NSManaged public var id: UUID
    @NSManaged public var transactionId: UUID    // 被作廢的交易
    @NSManaged public var eventId: UUID          // 交易所屬場次（無 relationship，場次刪除後保留）
    @NSManaged public var voidedAt: Date
    @NSManaged public var reason: String         // VoidReason.rawValue
    @NSManaged public var note: String?
    @NSManaged public var restocked: Bool        // 作廢時是否回補庫存

    // MARK: - Sync 相關欄位
    @NSManaged public var userId: String?
    @NSManaged public var syncStatus: String?    // "synced" | "pending" | "error"
    @NSManaged public var updatedAt: Date?       // 建立當下的時間，之後永不改變（append-only）
}

extension CDTransactionVoidEntity {

    func update(from model: TransactionVoidModel, context: NSManagedObjectContext) {
        self.id = model.id
        self.transactionId = model.transactionId
        self.eventId = model.eventId
        self.voidedAt = model.voidedAt
        self.reason = model.reason.rawValue
        self.note = model.note
        self.restocked = model.restocked
    }

    func toModel() -> TransactionVoidModel {
        TransactionVoidModel(entity: self)
    }
}
