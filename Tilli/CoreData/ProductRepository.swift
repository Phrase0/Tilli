//
//  ProductRepository.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/3.
//

import CoreData
import SwiftUI

class ProductRepository: ObservableObject {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
        self.context = container.viewContext
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
            productEntity.category = categoryEntity

            saveContext()
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
                entity.price = productModel.price
                
                // 庫存更新需要依照原有業務邏輯判斷
                updateStockWithBusinessLogic(entity: entity, newStock: productModel.stock)
                
                // 更新類別相關屬性
                entity.categoryId = productModel.categoryId
                entity.categoryName = productModel.categoryName
                
                entity.note = productModel.note
                if let imageData = productModel.imageData {
                    entity.imageData = imageData
                }
                
                saveContext()
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
                saveContext()
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
                saveContext()
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
            if hasRelatedTransactions(productId: productId) {
                // 有 Transaction，只能停用
                productEntity.isDisabled = true
                saveContext()
                return .disabledInstead("此產品已有交易紀錄，已改為停用狀態")
            } else {
                // 沒有 Transaction，可以硬刪除
                context.delete(productEntity)
                saveContext()
                return .deleted("產品已成功刪除")
            }
        } catch {
            print("Delete product failed:", error)
            return .failed("刪除失敗: \(error.localizedDescription)")
        }
    }

    // MARK: - Helper Methods

    /// 檢查 Product 是否有相關 Transaction
    private func hasRelatedTransactions(productId: UUID) -> Bool {
        let transactionRequest: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()

        do {
            let transactions = try context.fetch(transactionRequest)
            
            // 檢查所有交易的 items 中是否包含此 productId
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

    /// 根據業務邏輯更新庫存（保留原有的判斷規則）
    private func updateStockWithBusinessLogic(entity: CDProductEntity, newStock: Int) {
        // 這裡可以加入原有的庫存更新業務邏輯
        // 例如：檢查庫存是否足夠、是否有預留庫存等
        
        // 暫時直接更新，實際業務邏輯需要根據原有代碼調整
        entity.stock = Int32(newStock)
        
        // TODO: 根據原有的業務邏輯補充庫存更新規則
        // 例如：
        // - 檢查是否有進行中的交易
        // - 檢查庫存變更是否合理
        // - 記錄庫存變更歷史等
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