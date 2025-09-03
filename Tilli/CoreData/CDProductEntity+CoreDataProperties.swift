//
//  CDProductEntity+CoreDataProperties.swift
//  Tilli
//
//  Created by Peiyun on 2025/8/3.
//
//

import Foundation
import CoreData

extension CDProductEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDProductEntity> {
        return NSFetchRequest<CDProductEntity>(entityName: "CDProductEntity")
    }
    
    @NSManaged public var categoryId: UUID
    @NSManaged public var categoryName: String
    @NSManaged public var id: UUID
    @NSManaged public var sessionId: UUID
    @NSManaged public var name: String
    @NSManaged public var price: Double
    @NSManaged public var stock: Int32
    @NSManaged public var note: String?
    @NSManaged public var imageData: Data?
    @NSManaged public var category: CDCategoryEntity
    @NSManaged public var isDisabled: Bool

}

extension CDProductEntity {
    
    func update(from model: ProductModel, context: NSManagedObjectContext) {
        self.id = model.id
        self.sessionId = model.sessionId
        self.name = model.name
        self.price = model.price
        self.stock = Int32(model.stock)
        self.categoryId = model.categoryId
        self.categoryName = model.categoryName
        self.note = model.note
        if let imageData = model.imageData {
            self.imageData = imageData
        }
        self.isDisabled = model.isDisabled
    }

    func toModel() -> ProductModel {
            ProductModel(entity: self)
        }
}
