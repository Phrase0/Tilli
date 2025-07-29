//
//  CDProductEntity+CoreDataProperties.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/25.
//
//

import Foundation
import CoreData

extension CDProductEntity {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDProductEntity> {
        return NSFetchRequest<CDProductEntity>(entityName: "CDProductEntity")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var sessionId: UUID
    @NSManaged public var name: String
    @NSManaged public var price: Double
    @NSManaged public var stock: Int32
    @NSManaged public var category: String
    @NSManaged public var note: String?
    @NSManaged public var imageData: Data?
    @NSManaged public var session: CDSessionEntity
}

extension CDProductEntity {
    
    func update(from model: ProductModel, context: NSManagedObjectContext) {
        self.id = model.id
        self.sessionId = model.sessionId
        self.name = model.name
        self.price = model.price
        self.stock = Int32(model.stock)
        self.category = model.category
        self.note = model.note
        self.imageData = model.imageData
    }

    func toModel() -> ProductModel {
            ProductModel(entity: self)
        }
}
