//
//  CDTransactionEntity+CoreDataProperties.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/29.
//
//

import Foundation
import CoreData

extension CDTransactionEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTransactionEntity> {
        return NSFetchRequest<CDTransactionEntity>(entityName: "CDTransactionEntity")
    }

    @NSManaged public var id: UUID
    @NSManaged public var sessionId: UUID
    @NSManaged public var itemsData: Data?
    @NSManaged public var totalAmount: Double
    @NSManaged public var paymentMethod: String
    @NSManaged public var timestamp: Date
    @NSManaged public var session: CDSessionEntity

}


extension CDTransactionEntity {
    
    var items: [SummaryItemModel] {
        get {
            guard let data = self.itemsData else { return [] }
            return (try? JSONDecoder().decode([SummaryItemModel].self, from: data)) ?? []
        }
        set {
            self.itemsData = try? JSONEncoder().encode(newValue)
        }
    }

    func update(from model: TransactionModel, context: NSManagedObjectContext) {
            self.id = model.id
            self.sessionId = model.sessionId
            self.totalAmount = model.totalAmount
            self.paymentMethod = model.paymentMethod.rawValue
            self.timestamp = model.timestamp
            self.items = model.items
    }

    func toModel() -> TransactionModel {
        return TransactionModel(
            id: self.id,
            sessionId: self.sessionId,
            items: self.items,
            totalAmount: self.totalAmount,
            paymentMethod: PaymentMethod(rawValue: self.paymentMethod) ?? .cash,
            timestamp: self.timestamp
        )
    }
}
