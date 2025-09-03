//
//  CDCategoryEntity+CoreDataProperties.swift
//  Tilli
//
//  Created by Peiyun on 2025/8/3.
//
//

import Foundation
import CoreData


extension CDCategoryEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDCategoryEntity> {
        return NSFetchRequest<CDCategoryEntity>(entityName: "CDCategoryEntity")
    }

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var createdAt: Date
    @NSManaged public var session: CDSessionEntity
    @NSManaged public var products: NSSet?
    @NSManaged public var isDisabled: Bool

}

// MARK: Generated accessors for products
extension CDCategoryEntity {

    @objc(addProductsObject:)
    @NSManaged public func addToProducts(_ value: CDProductEntity)

    @objc(removeProductsObject:)
    @NSManaged public func removeFromProducts(_ value: CDProductEntity)

    @objc(addProducts:)
    @NSManaged public func addToProducts(_ values: NSSet)

    @objc(removeProducts:)
    @NSManaged public func removeFromProducts(_ values: NSSet)

}

extension CDCategoryEntity {
    func update(from model: CategoryModel, context: NSManagedObjectContext) {
        self.id = model.id
        self.name = model.name
        self.createdAt = model.createdAt
        self.isDisabled = model.isDisabled
    }

    func toModel() -> CategoryModel {
        let products = (self.products as? Set<CDProductEntity>)?.compactMap { $0.toModel() } ?? []
        return CategoryModel(id: self.id, name: self.name, products: products, createdAt: self.createdAt, isDisabled: self.isDisabled)
    }

}

