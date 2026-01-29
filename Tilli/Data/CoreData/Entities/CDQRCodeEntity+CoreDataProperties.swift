//
//  CDQRCodeEntity+CoreDataProperties.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/18.
//

import Foundation
import CoreData

extension CDQRCodeEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDQRCodeEntity> {
        return NSFetchRequest<CDQRCodeEntity>(entityName: "CDQRCodeEntity")
    }

    @NSManaged public var id: UUID
    @NSManaged public var imageData: Data
    @NSManaged public var createdAt: Date

    // MARK: - Sync 相關欄位
    @NSManaged public var userId: String?        // 所屬用戶 ID
    @NSManaged public var updatedAt: Date?       // 最後更新時間
    @NSManaged public var syncStatus: String?    // "synced" | "pending" | "error"
    @NSManaged public var imageURL: String?      // Firebase Storage URL

}

extension CDQRCodeEntity: Identifiable {

}

extension CDQRCodeEntity {
    func update(from model: QRCodeModel, context: NSManagedObjectContext) {
        self.id = model.id
        self.imageData = model.imageData ?? Data()
        self.createdAt = model.createdAt
        self.imageURL = model.imageURL
    }

    func toModel() -> QRCodeModel {
        return QRCodeModel(
            id: self.id,
            imageData: self.imageData,
            imageURL: self.imageURL,
            createdAt: self.createdAt
        )
    }
}
