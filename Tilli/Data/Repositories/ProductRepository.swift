//
//  ProductRepository.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/3.
//

import CoreData
import SwiftUI
import FirebaseAuth

class ProductRepository: ObservableObject {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext
    private let inventoryChangeRepository: InventoryChangeRepository

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
        self.context = container.viewContext
        self.inventoryChangeRepository = InventoryChangeRepository(container: container)
    }

    // MARK: - Product CRUD Operations

    /// 新增 Product 到指定 Category
    func addProduct(to categoryId: UUID, productModel: ProductModel) {
        let categoryRequest: NSFetchRequest<CDCategoryEntity> = CDCategoryEntity.fetchRequest()
        categoryRequest.predicate = NSPredicate(format: "id == %@", categoryId as CVarArg)

        do {
            guard let categoryEntity = try context.fetch(categoryRequest).first else {
                print("找不到對應 category，無法加入 product")
                return
            }

            let productEntity = CDProductEntity(context: context)
            productEntity.update(from: productModel, context: context)
            productEntity.userId = Auth.auth().currentUser?.uid
            productEntity.syncStatus = "pending"
            productEntity.updatedAt = Date()
            productEntity.category = categoryEntity

            saveContext()
            // 同步到 Firestore
            Task { @MainActor in
                SyncManager.shared.syncProduct(productModel, operation: .create)
            }
        } catch {
            print("加入 product 失敗:", error)
        }
    }

    /// 更新 Product（允許修改名稱、價格、庫存等屬性，遵循原有業務邏輯）
    func updateProduct(_ productId: UUID, productModel: ProductModel) {
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productId as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                // 更新基本屬性
                entity.name = productModel.name
                entity.price = NSDecimalNumber(decimal: productModel.price)
                
                // 庫存更新需要依照原有業務邏輯判斷
                updateStockWithBusinessLogic(entity: entity, newStock: productModel.stock)
                
                // 更新類別相關屬性
                entity.categoryId = productModel.categoryId
                entity.categoryName = productModel.categoryName
                
                entity.note = productModel.note
                if let imageData = productModel.imageData {
                    entity.imageData = imageData
                }
                entity.syncStatus = "pending"
                entity.updatedAt = Date()

                saveContext()
                // 同步到 Firestore
                Task { @MainActor in
                    SyncManager.shared.syncProduct(productModel, operation: .update)
                }
            }
        } catch {
            print("Update product failed:", error)
        }
    }

    /// 停用 Product
    func disableProduct(_ productId: UUID) {
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productId as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                entity.isDisabled = true
                entity.syncStatus = "pending"
                entity.updatedAt = Date()
                saveContext()
                // 同步到 Firestore
                let productModel = entity.toModel()
                Task { @MainActor in
                    SyncManager.shared.syncProduct(productModel, operation: .update)
                }
            }
        } catch {
            print("Disable product failed:", error)
        }
    }

    /// 啟用 Product
    func enableProduct(_ productId: UUID) {
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productId as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                entity.isDisabled = false
                entity.syncStatus = "pending"
                entity.updatedAt = Date()
                saveContext()
                // 同步到 Firestore
                let productModel = entity.toModel()
                Task { @MainActor in
                    SyncManager.shared.syncProduct(productModel, operation: .update)
                }
            }
        } catch {
            print("Enable product failed:", error)
        }
    }

    /// 刪除 Product（智能刪除：有 Transaction 則停用，無則硬刪除）
    func deleteProduct(_ productId: UUID) -> ProductDeletionResult {
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productId as CVarArg)

        do {
            guard let productEntity = try context.fetch(request).first else {
                return .failed("找不到要刪除的 Product")
            }

            // 檢查是否有相關 Transaction
            if hasRelatedTransactions(productId: productId, sessionId: productEntity.sessionId) {
                // 有 Transaction，只能停用
                productEntity.isDisabled = true
                productEntity.syncStatus = "pending"
                productEntity.updatedAt = Date()
                saveContext()
                // 同步停用狀態到 Firestore
                let productModel = productEntity.toModel()
                Task { @MainActor in
                    SyncManager.shared.syncProduct(productModel, operation: .update)
                }
                return .disabledInstead("此產品已有交易記錄，已改為停用狀態")
            } else {
                // 沒有 Transaction，可以硬刪除
                // 先刪除該產品的所有庫存異動記錄
                let deletedChangeIds = inventoryChangeRepository.deleteChanges(forProductId: productId)
                context.delete(productEntity)
                saveContext()
                // 同步刪除到 Firestore（含庫存異動）
                Task { @MainActor in
                    SyncManager.shared.syncDeleteProductWithInventoryChanges(productId, inventoryChangeIds: deletedChangeIds)
                }
                return .deleted("產品已成功刪除")
            }
        } catch {
            print("Delete product failed:", error)
            return .failed("刪除失敗: \(error.localizedDescription)")
        }
    }

    // MARK: - Helper Methods

    /// 檢查 Product 是否有相關 Transaction（僅查詢同場次的交易）
    private func hasRelatedTransactions(productId: UUID, sessionId: UUID?) -> Bool {
        let transactionRequest: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        if let sessionId = sessionId {
            transactionRequest.predicate = NSPredicate(format: "sessionId == %@", sessionId as CVarArg)
        }

        do {
            let transactions = try context.fetch(transactionRequest)

            // 檢查交易的 items 中是否包含此 productId
            for transaction in transactions {
                if let itemsData = transaction.itemsData,
                   let items = try? JSONDecoder().decode([SummaryItemModel].self, from: itemsData) {
                    if items.contains(where: { $0.productId == productId }) {
                        return true
                    }
                }
            }
            return false
        } catch {
            print("檢查 Transaction 失敗:", error)
            return true // 發生錯誤時保守處理，假設有 Transaction
        }
    }

    /// 更新庫存
    private func updateStockWithBusinessLogic(entity: CDProductEntity, newStock: Int) {
        entity.stock = Int32(newStock)
    }

    // MARK: - Query Methods

    /// 取得指定 Category 下的所有 Product
    func fetchProducts(forCategoryId categoryId: UUID) -> [ProductModel] {
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "category.id == %@", categoryId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let result = try context.fetch(request)
            return result.map { $0.toModel() }
        } catch {
            print("Fetch products for category failed:", error)
            return []
        }
    }
    

    /// 取得指定 Session 下的所有 Product
    func fetchProducts(forSessionId sessionId: UUID) -> [ProductModel] {
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "sessionId == %@", sessionId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "category.name", ascending: true), 
                                   NSSortDescriptor(key: "name", ascending: true)]

        do {
            let result = try context.fetch(request)
            return result.map { $0.toModel() }
        } catch {
            print("Fetch products for session failed:", error)
            return []
        }
    }

    // MARK: - Batch Operations
    
    /// 批次更新產品庫存
    func batchUpdateProductStock(_ stockUpdates: [UUID: Int]) -> Bool {
        guard !stockUpdates.isEmpty else {
            return true
        }
        
        let productIds = Array(stockUpdates.keys)
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", productIds)
        
        do {
            let products = try context.fetch(request)
            
            let now = Date()
            for product in products {
                if let newStock = stockUpdates[product.id] {
                    product.stock = Int32(max(newStock, 0))
                    product.syncStatus = "pending"
                    product.updatedAt = now
                }
            }
            
            try context.save()

            // 同步到 Firestore
            let updatedModels = products.map { $0.toModel() }
            Task { @MainActor in
                for model in updatedModels {
                    SyncManager.shared.syncProduct(model, operation: .update)
                }
            }

            print("✅ Batch updated \(products.count) products stock")
            return true

        } catch {
            context.rollback()
            print("🔴 批次更新產品庫存失敗: \(error)")
            return false
        }
    }

    /// 批次更新多個產品（完整更新）
    func batchUpdateProducts(_ productUpdates: [ProductModel]) -> Bool {
        guard !productUpdates.isEmpty else {
            return true
        }

        let productIds = productUpdates.map { $0.id }
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", productIds)

        do {
            let entities = try context.fetch(request)
            let entityDict = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })

            let now = Date()
            for productModel in productUpdates {
                if let entity = entityDict[productModel.id] {
                    entity.name = productModel.name
                    entity.price = NSDecimalNumber(decimal: productModel.price)
                    updateStockWithBusinessLogic(entity: entity, newStock: productModel.stock)
                    entity.categoryId = productModel.categoryId
                    entity.categoryName = productModel.categoryName
                    entity.note = productModel.note
                    if let imageData = productModel.imageData {
                        entity.imageData = imageData
                    }
                    entity.syncStatus = "pending"
                    entity.updatedAt = now
                }
            }

            try context.save()

            // 同步到 Firestore
            Task { @MainActor in
                for model in productUpdates {
                    SyncManager.shared.syncProduct(model, operation: .update)
                }
            }

            print("✅ Batch updated \(entities.count) products")
            return true

        } catch {
            context.rollback()
            print("🔴 批次更新多個產品失敗: \(error)")
            return false
        }
    }
    

    // MARK: - Save Context
    private func saveContext() {
        do {
            try context.save()
            print("Product data saved to CoreData")
        } catch {
            print("Core Data save failed:", error)
            context.rollback()
        }
    }
}

// MARK: - Product Deletion Result

enum ProductDeletionResult {
    case deleted(String)          // 成功硬刪除
    case disabledInstead(String)  // 因為有 Transaction，改為停用
    case failed(String)           // 刪除失敗
}
