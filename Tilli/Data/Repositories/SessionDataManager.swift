//
//  SessionDataManager.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/27.
//

import CoreData
import SwiftUI

class SessionDataManager: ObservableObject {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    @Published var sessions: [SessionModel] = []

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
        self.context = container.viewContext
        fetchSessions()
    }

    // MARK: - Session CRUD Operations
    
    /// 取得所有 Session，包含完整的 Category、Product、Transaction
    func fetchSessions() {
        let request: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        // 預先載入相關資料，避免多次查詢
        request.relationshipKeyPathsForPrefetching = ["categories", "categories.products", "transactions"]

        do {
            let result = try context.fetch(request)
            let newSessions = result.map { $0.toModel() }
            
            // 確保在主線程更新 @Published 屬性
            DispatchQueue.main.async {
                self.sessions = newSessions
            }
        } catch {
            print("Fetch sessions failed:", error)
        }
    }

    /// 根據 ID 取得特定 Session
    func fetchSession(by id: UUID) -> SessionModel? {
        let request: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.relationshipKeyPathsForPrefetching = ["categories", "categories.products", "transactions"]

        do {
            if let entity = try context.fetch(request).first {
                return entity.toModel()
            }
        } catch {
            print("Fetch session by ID failed:", error)
        }
        return nil
    }

    /// 新增 Session（僅處理 Session 層級）
    func addSession(_ model: SessionModel) {
        let entity = CDSessionEntity(context: context)
        entity.update(from: model, context: context)
        
        // 創建 Categories 和 Products
        for categoryModel in model.categories {
            let categoryEntity = CDCategoryEntity(context: context)
            categoryEntity.update(from: categoryModel, context: context)
            categoryEntity.session = entity
            
            for productModel in categoryModel.products {
                let productEntity = CDProductEntity(context: context)
                productEntity.update(from: productModel, context: context)
                productEntity.category = categoryEntity
            }
        }
        
        if saveContext() {
            fetchSessions() // 僅在成功保存後重新載入
        }
    }

    /// 更新 Session（包含 Category 的變更處理）
    func updateSession(_ model: SessionModel) {
        let request: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)
        request.relationshipKeyPathsForPrefetching = ["categories", "categories.products"]

        do {
            guard let entity = try context.fetch(request).first else {
                print("Session not found for update")
                return
            }
            
            // 更新 Session 基本屬性
            entity.title = model.title
            entity.date = model.date
            entity.currency = model.currency

            // 處理 Categories 的變更
            updateCategoriesForSession(entity: entity, newCategories: model.categories)
            
            if saveContext() {
                fetchSessions() // 僅在成功保存後重新載入
            }
        } catch {
            print("Update session failed:", error)
        }
    }
    
    /// 更新 Session 的 Categories
    private func updateCategoriesForSession(entity: CDSessionEntity, newCategories: [CategoryModel]) {
        let existingCategories = entity.categories as? Set<CDCategoryEntity> ?? Set()
        let existingCategoryIds = Set(existingCategories.map { $0.id })
        let newCategoryIds = Set(newCategories.map { $0.id })
        
        // 找出需要刪除的 categories
        let categoriesToDelete = existingCategories.filter { !newCategoryIds.contains($0.id) }
        
        // 找出需要新增的 categories
        let categoriesToAdd = newCategories.filter { !existingCategoryIds.contains($0.id) }
        
        // 找出需要更新的 categories
        let categoriesToUpdate = newCategories.filter { existingCategoryIds.contains($0.id) }
        
        // 刪除不再需要的 categories（但要檢查是否有交易記錄）
        for categoryEntity in categoriesToDelete {
            // 檢查是否有相關交易記錄
            if hasRelatedTransactionsForCategory(categoryId: categoryEntity.id) {
                // 有交易記錄，只能停用
                categoryEntity.isDisabled = true
                print("Category \(categoryEntity.name) has transactions, disabled instead of deleted")
            } else {
                // 無交易記錄，可以硬刪除
                entity.removeFromCategories(categoryEntity)
                context.delete(categoryEntity)
            }
        }
        
        // 新增新的 categories
        for categoryModel in categoriesToAdd {
            let categoryEntity = CDCategoryEntity(context: context)
            categoryEntity.update(from: categoryModel, context: context)
            categoryEntity.session = entity
            entity.addToCategories(categoryEntity)
            
            // 新增該 category 下的 products
            for productModel in categoryModel.products {
                let productEntity = CDProductEntity(context: context)
                productEntity.update(from: productModel, context: context)
                productEntity.category = categoryEntity
                categoryEntity.addToProducts(productEntity)
            }
        }
        
        // 更新現有的 categories
        for categoryModel in categoriesToUpdate {
            if let categoryEntity = existingCategories.first(where: { $0.id == categoryModel.id }) {
                // 更新基本屬性
                categoryEntity.name = categoryModel.name
                categoryEntity.isDisabled = categoryModel.isDisabled

                // 只更新 products 的 categoryName（不處理 products 的新增/刪除）
                // Products 的 CRUD 由 ProductRepository 負責
                if let products = categoryEntity.products as? Set<CDProductEntity> {
                    for product in products {
                        product.categoryName = categoryModel.name
                    }
                }
            }
        }
    }

    /// 刪除 Session（硬刪除，但保留 Transaction）
    func deleteSession(_ sessionId: UUID) {
        let request: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", sessionId as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                // Transaction 會自動保留，因為它們沒有級聯刪除
                context.delete(entity)
                if saveContext() {
                    fetchSessions() // 僅在成功保存後重新載入
                }
            }
        } catch {
            print("Delete session failed:", error)
        }
    }

    // MARK: - Transaction Operations (僅允許新增)
    
    /// 新增交易記錄（永久保留）
    func addTransaction(_ model: TransactionModel) {
        let sessionRequest: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        sessionRequest.predicate = NSPredicate(format: "id == %@", model.sessionId as CVarArg)

        do {
            guard let sessionEntity = try context.fetch(sessionRequest).first else {
                print("找不到對應 session，無法加入 transaction")
                return
            }

            let entity = CDTransactionEntity(context: context)
            entity.update(from: model, context: context)
            sessionEntity.addToTransactions(entity)

            if saveContext() {
                fetchSessions() // 僅在成功保存後重新載入以更新交易記錄
            }
        } catch {
            print("加入 transaction 失敗:", error)
        }
    }

    /// 更新交易記錄（僅允許修改業務欄位）
    func updateTransaction(_ model: TransactionModel) {
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                entity.update(from: model, context: context)
                if saveContext() {
                    fetchSessions() // 僅在成功保存後重新載入
                }
            }
        } catch {
            print("Update transaction failed:", error)
        }
    }
    
    /// 複製場次（包含所有類別和產品，但不包含交易記錄）
    func duplicateSession(originalSessionId: UUID, newTitle: String, newDate: Date) -> SessionModel? {
        let request: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", originalSessionId as CVarArg)
        request.relationshipKeyPathsForPrefetching = ["categories", "categories.products"]
        
        do {
            guard let originalEntity = try context.fetch(request).first else {
                print("找不到要複製的場次")
                return nil
            }
            
            // 創建新的 Session 實體
            let newSessionEntity = CDSessionEntity(context: context)
            newSessionEntity.id = UUID()
            newSessionEntity.title = newTitle
            newSessionEntity.date = newDate
            newSessionEntity.createdAt = Date()
            newSessionEntity.currency = originalEntity.currency
            
            // 複製所有 Categories 和 Products
            if let originalCategories = originalEntity.categories as? Set<CDCategoryEntity> {
                for originalCategory in originalCategories {
                    let newCategoryEntity = CDCategoryEntity(context: context)
                    newCategoryEntity.id = UUID()
                    newCategoryEntity.name = originalCategory.name
                    newCategoryEntity.createdAt = Date()
                    newCategoryEntity.isDisabled = originalCategory.isDisabled
                    newCategoryEntity.session = newSessionEntity
                    
                    // 複製該 Category 下的所有 Products
                    if let originalProducts = originalCategory.products as? Set<CDProductEntity> {
                        for originalProduct in originalProducts {
                            let newProductEntity = CDProductEntity(context: context)
                            newProductEntity.id = UUID()
                            newProductEntity.sessionId = newSessionEntity.id
                            newProductEntity.name = originalProduct.name
                            newProductEntity.price = originalProduct.price
                            newProductEntity.stock = originalProduct.stock
                            newProductEntity.categoryId = newCategoryEntity.id
                            newProductEntity.categoryName = newCategoryEntity.name
                            newProductEntity.note = originalProduct.note
                            newProductEntity.imageData = originalProduct.imageData
                            newProductEntity.isDisabled = originalProduct.isDisabled
                            newProductEntity.category = newCategoryEntity
                        }
                    }
                }
            }
            
            if saveContext() {
                fetchSessions() // 僅在成功保存後重新載入
                // 返回新建立的 SessionModel
                return newSessionEntity.toModel()
            } else {
                return nil
            }
        } catch {
            print("複製場次失敗:", error)
            return nil
        }
    }

    // MARK: - Helper Methods
    
    /// 檢查 Category 下是否有相關 Transaction
    private func hasRelatedTransactionsForCategory(categoryId: UUID) -> Bool {
        // 先找到該 Category 下的所有 Product
        let productRequest: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        productRequest.predicate = NSPredicate(format: "category.id == %@", categoryId as CVarArg)

        do {
            let products = try context.fetch(productRequest)
            let productIds = products.map { $0.id }

            if productIds.isEmpty {
                return false // 沒有 Product，當然沒有 Transaction
            }

            // 檢查所有交易的 items 中是否包含這些 productIds
            let transactionRequest: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
            let transactions = try context.fetch(transactionRequest)
            
            for transaction in transactions {
                if let itemsData = transaction.itemsData,
                   let items = try? JSONDecoder().decode([SummaryItemModel].self, from: itemsData) {
                    if items.contains(where: { productIds.contains($0.productId) }) {
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

    // MARK: - Save Context
    @discardableResult
    private func saveContext() -> Bool {
        do {
            try context.save()
            print("✅ Session data saved to CoreData")
            return true
        } catch {
            print("Core Data save failed:", error)
            context.rollback()
            return false
        }
    }
}
