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
    func addProduct(to categoryId: UUID, productModel: ProductModel, imageChanged: Bool = false) {
        let categoryRequest: NSFetchRequest<CDCategoryEntity> = CDCategoryEntity.fetchRequest()
        categoryRequest.predicate = NSPredicate(format: "id == %@", categoryId as CVarArg)

        do {
            guard let categoryEntity = try context.fetch(categoryRequest).first else {
                print("找不到對應 category，無法加入 product")
                return
            }

            let productEntity = CDProductEntity(context: context)
            productEntity.update(from: productModel, context: context)
            productEntity.sortOrder = Int16(nextProductSortOrder(forCategoryId: categoryId))
            productEntity.userId = Auth.auth().currentUser?.uid ?? UserProfileModel.guestUserId
            productEntity.markPendingSync()
            productEntity.category = categoryEntity

            saveContext()
            // 同步到 Firestore（用剛存好的 entity 轉回 model，確保 sortOrder 等 repository 算出來的值一起同步，而不是呼叫端傳進來的舊值）
            let savedModel = productEntity.toModel()
            // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md
        } catch {
            print("加入 product 失敗:", error)
        }
    }

    /// 取得同類別內下一個可用的 sortOrder（目前最大值 + 1，該類別尚無商品則為 0）
    private func nextProductSortOrder(forCategoryId categoryId: UUID) -> Int {
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "categoryId == %@", categoryId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: false)]
        request.fetchLimit = 1

        do {
            if let maxEntity = try context.fetch(request).first {
                return Int(maxEntity.sortOrder) + 1
            }
            return 0
        } catch {
            print("取得 sortOrder 失敗:", error)
            return 0
        }
    }

    /// 依拖曳後的新順序，重新寫入同一類別內商品的 sortOrder（管理商品頁長按拖曳排序用）
    /// `orderedProductIds` 必須是「同一個類別」內、拖曳後的完整順序。
    func updateProductOrder(_ orderedProductIds: [UUID]) {
        guard !orderedProductIds.isEmpty else { return }

        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", orderedProductIds)

        do {
            let entities = try context.fetch(request)
            let entityDict = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })

            var updatedModels: [ProductModel] = []
            for (index, productId) in orderedProductIds.enumerated() {
                guard let entity = entityDict[productId] else { continue }
                entity.sortOrder = Int16(index)
                entity.markPendingSync()
                updatedModels.append(entity.toModel())
            }

            saveContext()
            // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md
        } catch {
            print("更新商品排序失敗:", error)
        }
    }

    /// 更新 Product（允許修改名稱、價格、庫存等屬性，遵循原有業務邏輯）
    func updateProduct(_ productId: UUID, productModel: ProductModel, imageChanged: Bool = false) {
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
                
                entity.note = productModel.note
                if let imageData = productModel.imageData {
                    entity.imageData = imageData
                }
                if imageChanged {
                    entity.imageURL = nil  // TODO: [SYNC-PENDING] 清空舊 URL，重建同步後由上傳端回寫
                }
                entity.markPendingSync()

                saveContext()
                // 同步到 Firestore（用 entity 轉回 model，而非呼叫端傳進來的 productModel——
                // sortOrder 這裡不會被更新，若直接同步 productModel 會把它預設值 0 誤傳上雲端）
                let savedModel = entity.toModel()
                // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md
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
                entity.markPendingSync()
                saveContext()
                // 同步到 Firestore
                let productModel = entity.toModel()
                // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md
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
                entity.markPendingSync()
                saveContext()
                // 同步到 Firestore
                let productModel = entity.toModel()
                // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md
            }
        } catch {
            print("Enable product failed:", error)
        }
    }

    /// 刪除 Product
    ///
    /// 有交易紀錄的商品**不可刪除**（刪掉再建同名商品會讓報表統計分裂成兩個 UUID）。
    /// 守衛保留，因為 repository 是最後一道防線（將來的批次刪除／匯入會需要），
    /// 但它**只拒絕、不偷偷做別的事** —— 原本會靜默改成「停用」，
    /// 呼叫端以為刪掉了、實際上資料還在。
    func deleteProduct(_ productId: UUID) -> ProductDeletionResult {
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productId as CVarArg)

        do {
            guard let productEntity = try context.fetch(request).first else {
                return .failed(String.localized("productDeleteNotFound"))
            }

            guard let index = transactionIndex(forEventId: productEntity.eventId) else {
                // 查不到交易就不敢刪（保守處理），但明確告知呼叫端
                return .failed(String.localized("productDeleteCheckFailed"))
            }

            if index.hasTransaction(productId: productId) {
                return .failed(String.localized("productDetailCannotDelete"))
            } else {
                // 沒有 Transaction，可以硬刪除
                // 先刪除該產品的所有庫存異動記錄
                let deletedChangeIds = inventoryChangeRepository.deleteChanges(forProductId: productId)
                context.delete(productEntity)
                saveContext()
                // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md
                return .deleted("Product deleted")
            }
        } catch {
            print("Delete product failed:", error)
            return .failed(String.localized("productDeleteFailed \(error.localizedDescription)"))
        }
    }

    // MARK: - Helper Methods

    /// 建立該場次的交易索引（刪除守衛用）。查詢失敗回傳 nil，由呼叫端誠實失敗。
    private func transactionIndex(forEventId eventId: UUID?) -> TransactionIndex? {
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        if let eventId {
            request.predicate = NSPredicate(format: "eventId == %@", eventId as CVarArg)
        }
        do {
            return TransactionIndex(transactions: try context.fetch(request).map { $0.toModel() })
        } catch {
            print("🔴 建立交易索引失敗:", error)
            return nil
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
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]

        do {
            let result = try context.fetch(request)
            return result.map { $0.toModel() }
        } catch {
            print("Fetch products for category failed:", error)
            return []
        }
    }
    

    /// 取得指定 Event 下的所有 Product
    func fetchProducts(forEventId eventId: UUID) -> [ProductModel] {
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "eventId == %@", eventId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]

        do {
            let result = try context.fetch(request)
            return result.map { $0.toModel() }
        } catch {
            print("Fetch products for event failed:", error)
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
                    product.markPendingSync(at: now)
                }
            }
            
            try context.save()

            // 同步到 Firestore
            let updatedModels = products.map { $0.toModel() }
            // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md

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
                    entity.note = productModel.note
                    if let imageData = productModel.imageData {
                        entity.imageData = imageData
                    }
                    entity.markPendingSync(at: now)
                }
            }

            try context.save()

            // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md

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
    case deleted(String)   // 成功硬刪除
    case failed(String)    // 刪除失敗（含「有交易紀錄不可刪除」）
}
