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
    @NSManaged public var startDate: Date        // 場次開始日期（必填）
    @NSManaged public var endDate: Date?         // 場次結束日期（可選，nil 表示無限期）
    @NSManaged public var dateType: String       // 場次類型："single" | "multi" | "permanent"
    @NSManaged public var createdAt: Date
    @NSManaged public var currency: String
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
        // 更新基本欄位
        self.id = model.id
        self.title = model.title
        self.startDate = model.startDate
        self.endDate = model.endDate
        self.dateType = model.dateType.rawValue
        self.createdAt = model.createdAt
        self.currency = model.currency
    }


    // Core Data 載入資料後 → 轉成 SessionModel 給 UI 用
    func toModel() -> SessionModel {
        // 取出所有 CategoryModel
        let categoryModels = (categories as? Set<CDCategoryEntity>)?.compactMap { $0.toModel() } ?? []

        let transactionModels = (transactions as? Set<CDTransactionEntity>)?.compactMap { $0.toModel() } ?? []

        return SessionModel(
            id: self.id,
            title: self.title,
            startDate: self.startDate,
            endDate: self.endDate,
            dateType: SessionDateType(rawValue: self.dateType) ?? .single,
            categories: categoryModels,
            createdAt: self.createdAt,
            currency: self.currency
        )
    }


}

