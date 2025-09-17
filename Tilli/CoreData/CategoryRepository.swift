//
//  CategoryRepository.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/3.
//

import CoreData
import SwiftUI

class CategoryRepository: ObservableObject {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
        self.context = container.viewContext
    }

    // MARK: - Category CRUD Operations

    /// 新增 Category 到指定 Session
    func addCategory(to sessionId: UUID, categoryModel: CategoryModel) {
        let sessionRequest: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        sessionRequest.predicate = NSPredicate(format: "id == %@", sessionId as CVarArg)

        do {
            guard let sessionEntity = try context.fetch(sessionRequest).first else {
                print("找不到對應 session，無法加入 category")
                return
            }

            let categoryEntity = CDCategoryEntity(context: context)
            categoryEntity.update(from: categoryModel, context: context)
            categoryEntity.session = sessionEntity

            saveContext()
        } catch {
            print("加入 category 失敗:", error)
        }
    }

    /// 更新 Category
    func updateCategory(_ categoryId: UUID, categoryModel: CategoryModel) {
        let request: NSFetchRequest<CDCategoryEntity> = CDCategoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", categoryId as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                entity.name = categoryModel.name
                // 不更新 isDisabled 狀態，這由 disable/enable 方法處理
                saveContext()
            }
        } catch {
            print("Update category failed:", error)
        }
    }

    /// 停用 Category
    func disableCategory(_ categoryId: UUID) {
        let request: NSFetchRequest<CDCategoryEntity> = CDCategoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", categoryId as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                entity.isDisabled = true
                saveContext()
            }
        } catch {
            print("Disable category failed:", error)
        }
    }

    /// 啟用 Category
    func enableCategory(_ categoryId: UUID) {
        let request: NSFetchRequest<CDCategoryEntity> = CDCategoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", categoryId as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                entity.isDisabled = false
                saveContext()
            }
        } catch {
            print("Enable category failed:", error)
        }
    }

    /// 刪除 Category（智能刪除：有 Transaction 則停用，無則硬刪除）
    func deleteCategory(_ categoryId: UUID) -> CategoryDeletionResult {
        let request: NSFetchRequest<CDCategoryEntity> = CDCategoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", categoryId as CVarArg)

        do {
            guard let categoryEntity = try context.fetch(request).first else {
                return .failed("找不到要刪除的類別")
            }

            // 檢查是否有相關 Transaction
            if hasRelatedTransactions(categoryId: categoryId) {
                // 有 Transaction，只能停用
                categoryEntity.isDisabled = true
                saveContext()
                return .disabledInstead("此分類已有交易記錄，已改為停用狀態")
            } else {
                // 沒有 Transaction，可以硬刪除
                context.delete(categoryEntity) // 這會連帶刪除 Products
                saveContext()
                return .deleted("分類已成功刪除")
            }
        } catch {
            print("Delete category failed:", error)
            return .failed("刪除失敗: \(error.localizedDescription)")
        }
    }

    // MARK: - Helper Methods

    /// 檢查 Category 下是否有相關 Transaction
    private func hasRelatedTransactions(categoryId: UUID) -> Bool {
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
    private func saveContext() {
        do {
            try context.save()
            print("Category data saved to CoreData")
        } catch {
            print("Core Data save failed:", error)
            context.rollback()
        }
    }
}

// MARK: - Category Deletion Result

enum CategoryDeletionResult {
    case deleted(String)          // 成功硬刪除
    case disabledInstead(String)  // 因為有 Transaction，改為停用
    case failed(String)           // 刪除失敗
}
