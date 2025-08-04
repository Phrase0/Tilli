//
//  CDSessionEntity+CoreDataProperties.swift
//  Tilli
//
//  Created by Peiyun on 2025/8/3.
//
//

import Foundation
import CoreData

extension CDSessionEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDSessionEntity> {
        return NSFetchRequest<CDSessionEntity>(entityName: "CDSessionEntity")
    }

    
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var date: Date
    @NSManaged public var createdAt: Date
    @NSManaged public var categories: NSSet
    @NSManaged public var transactions: NSSet?

}

// MARK: Generated accessors for transactions
extension CDSessionEntity {

    @objc(addTransactionsObject:)
    @NSManaged public func addToTransactions(_ value: CDTransactionEntity)

    @objc(removeTransactionsObject:)
    @NSManaged public func removeFromTransactions(_ value: CDTransactionEntity)

    @objc(addTransactions:)
    @NSManaged public func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged public func removeFromTransactions(_ values: NSSet)

}

// MARK: Generated accessors for categories
extension CDSessionEntity {

    @objc(addCategoriesObject:)
    @NSManaged public func addToCategories(_ value: CDCategoryEntity)

    @objc(removeCategoriesObject:)
    @NSManaged public func removeFromCategories(_ value: CDCategoryEntity)

    @objc(addCategories:)
    @NSManaged public func addToCategories(_ values: NSSet)

    @objc(removeCategories:)
    @NSManaged public func removeFromCategories(_ values: NSSet)

}

extension CDSessionEntity {

    func update(from model: SessionModel, context: NSManagedObjectContext) {
        self.id = model.id
        self.title = model.title
        self.date = model.date
        self.createdAt = model.createdAt

        // 更新分類（先清除再加）
        self.removeFromCategories(self.categories)
        for categoryModel in model.categories {
            let request: NSFetchRequest<CDCategoryEntity> = CDCategoryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", categoryModel.id as CVarArg)
            request.fetchLimit = 1

            if let existingCategory = try? context.fetch(request).first {
                existingCategory.update(from: categoryModel, context: context)
                self.addToCategories(existingCategory)
            } else {
                let newCategory = CDCategoryEntity(context: context)
                newCategory.update(from: categoryModel, context: context)
                self.addToCategories(newCategory)
            }
        }

        // 更新交易
        self.removeFromTransactions(self.transactions ?? [])
        for transactionModel in model.transactions {
            let cdTx = CDTransactionEntity(context: context)
            cdTx.update(from: transactionModel, context: context)
            self.addToTransactions(cdTx)
        }
    }
    
    
    // Core Data 載入資料後 → 轉成 SessionModel 給 UI 用
    func toModel() -> SessionModel {
        // 取出所有 CategoryModel
        let categoryModels = (categories as? Set<CDCategoryEntity>)?.compactMap { $0.toModel() } ?? []

        // 所有產品集中為一份 array（optional：可刪除）
//        let allProducts: [ProductModel] = categoryModels.flatMap { $0.products }

        let transactionModels = (transactions as? Set<CDTransactionEntity>)?.compactMap { $0.toModel() } ?? []

        return SessionModel(
            id: self.id,
            title: self.title,
            date: self.date,
            categories: categoryModels,
            createdAt: self.createdAt,
            transactions: transactionModels
        )
    }
    
    
}

