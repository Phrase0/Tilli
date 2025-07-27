//
//  CDTransactionEntity+CoreDataProperties.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/27.
//
//

import Foundation
import CoreData


extension CDTransactionEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTransactionEntity> {
        return NSFetchRequest<CDTransactionEntity>(entityName: "CDTransactionEntity")
    }

    @NSManaged public var session: CDSessionEntity?

}

extension CDTransactionEntity {

    func update(from model: TransactionModel, context: NSManagedObjectContext) {
        // 關聯到 Session（透過 sessionId 尋找對應的 CDSessionEntity）
        let fetchRequest: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", model.sessionId as CVarArg)

        if let sessionEntity = try? context.fetch(fetchRequest).first {
            self.session = sessionEntity
        }
    }

    func toModel() -> TransactionModel {
        // 提供一個空 TransactionModel，僅保留 sessionId（如果找得到）
        let sessionUUID = self.session?.id ?? UUID()
        return TransactionModel(
            id: UUID(), // 新建 UUID，也可改為 self.id 若有設欄位
            sessionId: sessionUUID,
            items: [],
            totalAmount: 0,
            paymentMethod: .cash,
            timestamp: Date()
        )
    }
}
