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
    @NSManaged public var sessionId: UUID
    @NSManaged public var change: Int32
    @NSManaged public var reason: String
    @NSManaged public var timestamp: Date
}

extension CDInventoryChangeEntity {

    func update(from model: InventoryChangeModel, context: NSManagedObjectContext) {
        self.id = model.id
        self.productId = model.productId
        self.sessionId = model.sessionId
        self.change = Int32(model.change)
        self.reason = model.reason.rawValue
        self.timestamp = model.timestamp
    }

    func toModel() -> InventoryChangeModel {
        return InventoryChangeModel(
            id: self.id,
            productId: self.productId,
            sessionId: self.sessionId,
            change: Int(self.change),
            reason: InventoryChangeReason(rawValue: self.reason) ?? .adjustment,
            timestamp: self.timestamp
        )
    }
}
