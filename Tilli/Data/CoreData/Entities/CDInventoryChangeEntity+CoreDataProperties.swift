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
        // session relationship 需要在外部设置
    }

    func toModel() -> InventoryChangeModel {
        return InventoryChangeModel(
            id: self.id,
            productId: self.productId,
            change: Int(self.change),
            reason: InventoryChangeReason(rawValue: self.reason) ?? .adjustment,
            customReason: self.customReason,
            transactionId: self.transactionId,
            timestamp: self.timestamp
        )
    }
}
