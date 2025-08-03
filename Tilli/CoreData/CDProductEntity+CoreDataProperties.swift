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
    
    @NSManaged public var id: UUID
    @NSManaged public var sessionId: UUID
    @NSManaged public var name: String
    @NSManaged public var price: Double
    @NSManaged public var stock: Int32
    @NSManaged public var note: String?
    @NSManaged public var imageData: Data?
    @NSManaged public var category: CDCategoryEntity

}

extension CDProductEntity {
    
    func update(from model: ProductModel, context: NSManagedObjectContext) {
        self.id = model.id
        self.sessionId = model.sessionId
        self.name = model.name
        self.price = model.price
        self.stock = Int32(model.stock)
        self.note = model.note
        self.imageData = model.imageData

        // 確保分類已存在 → 強制 unwrap
        let request: NSFetchRequest<CDCategoryEntity> = CDCategoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.categoryId as CVarArg)
        request.fetchLimit = 1

        do {
            if let category = try context.fetch(request).first {
                self.category = category
            } else {
                fatalError("Category with ID \(model.categoryId) not found.")
            }
        } catch {
            fatalError("Failed to fetch category: \(error)")
        }
    }

    func toModel() -> ProductModel {
            ProductModel(entity: self)
        }
}
