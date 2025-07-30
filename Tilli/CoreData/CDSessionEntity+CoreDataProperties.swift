//
//  CDSessionEntity+CoreDataProperties.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/27.
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
    @NSManaged public var status: String
    @NSManaged public var categories: String
    @NSManaged public var products: NSSet?
    @NSManaged public var transactions: NSSet?

}

// MARK: Generated accessors for products
extension CDSessionEntity {

    @objc(addProductsObject:)
    @NSManaged public func addToProducts(_ value: CDProductEntity)

    @objc(removeProductsObject:)
    @NSManaged public func removeFromProducts(_ value: CDProductEntity)

    @objc(addProducts:)
    @NSManaged public func addToProducts(_ values: NSSet)

    @objc(removeProducts:)
    @NSManaged public func removeFromProducts(_ values: NSSet)

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



extension CDSessionEntity {

    var wrappedStatus: SessionStatus {
        get {
            SessionStatus(rawValue: self.status) ?? .ongoing
        }
        set {
            self.status = newValue.rawValue
        }
    }

    var wrappedCategories: [String] {
        get {
            guard let json = self.categories.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: json)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            self.categories = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        }
    }

    func update(from model: SessionModel, context: NSManagedObjectContext) {
        self.id = model.id
        self.title = model.title
        self.date = model.date
        self.wrappedStatus = model.status
        self.createdAt = model.createdAt
        self.wrappedCategories = model.categories
        
        // 更新 products
        self.removeFromProducts(self.products ?? [])
        for productModel in model.products {
            let product = CDProductEntity(context: context)
            product.update(from: productModel, context: context)
            self.addToProducts(product)
        }

        // 更新 transactions
        self.removeFromTransactions(self.transactions ?? [])
        for transactionModel in model.transactions {
            let cdTx = CDTransactionEntity(context: context)
            cdTx.update(from: transactionModel, context: context)
            self.addToTransactions(cdTx)
        }
    }

    // Core Data 載入資料後 → 轉成 SessionModel 給 UI 用
    func toModel() -> SessionModel {
        let productModels: [ProductModel] = (products as? Set<CDProductEntity>)?.compactMap { $0.toModel() } ?? []
        let transactionModels: [TransactionModel] = (transactions as? Set<CDTransactionEntity>)?.compactMap { $0.toModel() } ?? []

        return SessionModel(
            id: self.id,
            title: self.title,
            date: self.date,
            status: self.wrappedStatus,
            categories: self.wrappedCategories,
            createdAt: self.createdAt,
            products: productModels,
            transactions: transactionModels
        )
    }
}
