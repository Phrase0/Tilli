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
    
//    func update(from model: CategoryModel, context: NSManagedObjectContext) {
//        self.id = model.id
//        self.name = model.name
//        self.createdAt = model.createdAt
//
//        self.removeFromProducts(self.products ?? [])
//        for productModel in model.products {
//            // 檢查商品是否已存在
//            let existingProduct = (self.products as? Set<CDProductEntity>)?.first {
//                $0.id == productModel.id
//            }
//            
//            if let existing = existingProduct {
//                // 更新現有商品
//                existing.update(from: productModel, context: context)
//            } else {
//                // 創建新商品
//                let product = CDProductEntity(context: context)
//                product.update(from: productModel, context: context)
//                product.category = self
//                self.addToProducts(product)
//            }
//        }
//    }
    //這是新的
//    func update(from model: CategoryModel, context: NSManagedObjectContext) {
//        self.id = model.id
//        self.name = model.name
//        self.createdAt = model.createdAt
//
//        let existingProducts = self.products as? Set<CDProductEntity> ?? []
//        var productMap: [UUID: CDProductEntity] = [:]
//        for product in existingProducts {
//            productMap[product.id] = product
//        }
//
//        // 比對 model.products → 更新、保留、新增
//        var updatedProducts = Set<CDProductEntity>()
//
//        for productModel in model.products {
//            if let existing = productMap[productModel.id] {
//                existing.update(from: productModel, context: context)
//                updatedProducts.insert(existing)
//            } else {
//                let newProduct = CDProductEntity(context: context)
//                newProduct.update(from: productModel, context: context)
//                newProduct.category = self
//                updatedProducts.insert(newProduct)
//            }
//        }
//
//        // 刪除不存在的 product
////        let removedProducts = existingProducts.subtracting(updatedProducts)
////        for removed in removedProducts {
////            context.delete(removed)
////        }
//
//        // 更新 products 關聯
//        self.products = updatedProducts as NSSet
//    }


    func update(from model: CategoryModel, context: NSManagedObjectContext) {
        self.id = model.id
        self.name = model.name
        self.createdAt = model.createdAt

        // 🟢 智慧判斷：檢查是否應該同步產品
        let shouldSyncProducts = self.shouldSyncProducts(with: model)
        
        if shouldSyncProducts {
            // 完整同步產品（包含刪除）
            self.syncProducts(with: model, context: context)
        } else {
            // 只更新/新增產品，不刪除
            self.updateProductsOnly(with: model, context: context)
        }
    }
    
    // 判斷是否需要同步產品
    private func shouldSyncProducts(with model: CategoryModel) -> Bool {
        // 情況 1: 如果 model 有產品，且目前沒有產品 → 需要同步
        if !model.products.isEmpty && (self.products as? Set<CDProductEntity>)?.isEmpty == true {
            return true
        }
        
        // 情況 2: 如果 model 的產品數量與現有產品數量相符或更多 → 可能是完整資料
        let currentProductCount = (self.products as? Set<CDProductEntity>)?.count ?? 0
        if model.products.count >= currentProductCount {
            return true
        }
        
        // 情況 3: 如果 model 沒有產品 → 不同步（保留現有產品）
        if model.products.isEmpty {
            return false
        }
        
        // 其他情況：保守起見，不刪除
        return false
    }
    
    // 🟢 完整同步產品（包含刪除）
    private func syncProducts(with model: CategoryModel, context: NSManagedObjectContext) {
        let existingProducts = self.products as? Set<CDProductEntity> ?? []
        var productMap: [UUID: CDProductEntity] = [:]
        for product in existingProducts {
            productMap[product.id] = product
        }

        var updatedProducts = Set<CDProductEntity>()

        for productModel in model.products {
            if let existing = productMap[productModel.id] {
                existing.update(from: productModel, context: context)
                updatedProducts.insert(existing)
            } else {
                let newProduct = CDProductEntity(context: context)
                newProduct.update(from: productModel, context: context)
                newProduct.category = self
                updatedProducts.insert(newProduct)
            }
        }

        // 刪除不存在的產品
        let removedProducts = existingProducts.subtracting(updatedProducts)
        for removed in removedProducts {
            context.delete(removed)
        }

        self.products = updatedProducts as NSSet
    }
    
    // 🟢 只更新/新增產品，不刪除
    private func updateProductsOnly(with model: CategoryModel, context: NSManagedObjectContext) {
        for productModel in model.products {
            if let existingProduct = (self.products as? Set<CDProductEntity>)?.first(where: { $0.id == productModel.id }) {
                // 🟢 保護庫存：如果 Core Data 中的庫存比較少，保留 Core Data 的值
                let currentStock = Int(existingProduct.stock)
                existingProduct.update(from: productModel, context: context)
                
                // 如果 model 的庫存比較多，可能是舊資料，恢復 Core Data 的庫存
                if productModel.stock > currentStock {
                    existingProduct.stock = Int32(currentStock)
                }
            } else {
                // 新產品，正常新增
                let newProduct = CDProductEntity(context: context)
                newProduct.update(from: productModel, context: context)
                newProduct.category = self
                self.addToProducts(newProduct)
            }
        }
    }
    //----
    func toModel() -> CategoryModel {
        let products = (self.products as? Set<CDProductEntity>)?.compactMap { $0.toModel() } ?? []
        return CategoryModel(id: self.id, name: self.name, products: products, createdAt: self.createdAt)
    }

}

