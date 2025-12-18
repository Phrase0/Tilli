//
//  SessionDataManager.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/27.
//

import CoreData
import SwiftUI

/// 場次驗證結果
enum SessionValidationResult {
    case success
    case failure(String)  // 失敗時包含錯誤訊息

    var isValid: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    var errorMessage: String? {
        if case .failure(let message) = self {
            return message
        }
        return nil
    }
}

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
        // 驗證場次資料
        let validationResult = validateSession(model)
        guard validationResult.isValid else {
            print("❌ 場次驗證失敗: \(validationResult.errorMessage ?? "未知錯誤")")
            return
        }

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
        // 驗證場次資料
        let validationResult = validateSession(model)
        guard validationResult.isValid else {
            print("❌ 場次驗證失敗: \(validationResult.errorMessage ?? "未知錯誤")")
            return
        }

        let request: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)
        request.relationshipKeyPathsForPrefetching = ["categories", "categories.products"]

        do {
            guard let entity = try context.fetch(request).first else {
                print("Session not found for update")
                return
            }

            // 檢查哪些欄位有變更
            let titleChanged = entity.title != model.title
            let dateChanged = !Calendar.current.isDate(entity.startDate, inSameDayAs: model.startDate)

            // 更新 Session 基本屬性
            entity.title = model.title
            entity.startDate = model.startDate
            entity.endDate = model.endDate
            entity.dateType = model.dateType.rawValue
            entity.currency = model.currency

            // 同步更新所有相關交易記錄
            if titleChanged || dateChanged {
                updateRelatedTransactions(
                    sessionId: model.id,
                    newTitle: titleChanged ? model.title : nil,
                    newDate: dateChanged ? model.startDate : nil
                )
            }

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
    /// 
    /// ⚠️ 注意：刪除 Session 後，相關的 Transaction 記錄會保留，
    /// 但 Transaction.session 關聯會被設為 nil（deletionRule="Nullify"）。
    /// Transaction 記錄仍可透過 sessionId 欄位查詢。
    func deleteSession(_ sessionId: UUID) {
        // 調試：刪除前檢查
        print("🔥 準備刪除 Session: \(sessionId)")
        debugTransactionStatus(forSessionId: sessionId)
        
        let request: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", sessionId as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                // 刪除 Session：
                // - Categories 和 Products 會被級聯刪除（deletionRule="Cascade"）
                // - Transactions 會保留，但 session 關聯會被設為 nil（deletionRule="Nullify"）
                context.delete(entity)
                if saveContext() {
                    // 調試：刪除後檢查
                    print("🔥 已刪除 Session，檢查交易記錄狀態:")
                    debugTransactionStatus(forSessionId: sessionId)
                    print("")
                    debugAllTransactions()
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
            newSessionEntity.startDate = newDate
            // 複製原場次的日期類型
            newSessionEntity.dateType = originalEntity.dateType
            // 如果是多日場次，保持相同的天數
            if let originalEndDate = originalEntity.endDate,
               let daysDifference = Calendar.current.dateComponents([.day], from: originalEntity.startDate, to: originalEndDate).day {
                newSessionEntity.endDate = Calendar.current.date(byAdding: .day, value: daysDifference, to: newDate)
            } else {
                newSessionEntity.endDate = nil
            }
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

    // MARK: - Validation Methods

    /// 驗證場次資料的合法性
    /// - Parameter model: 要驗證的場次模型
    /// - Returns: 驗證結果（成功或失敗及錯誤訊息）
    func validateSession(_ model: SessionModel) -> SessionValidationResult {
        // 1. 驗證場次名稱
        let trimmedTitle = model.title.trimmingCharacters(in: .whitespaces)
        if trimmedTitle.isEmpty {
            return .failure("場次名稱不可為空")
        }

        // 2. 根據場次類型驗證日期
        switch model.dateType {
        case .single:
            // 單日場次：endDate 應該等於 startDate 或為 nil
            // 不需要特別驗證
            return .success

        case .multi:
            // 多日場次：必須有 endDate 且晚於 startDate
            guard let endDate = model.endDate else {
                return .failure("多日場次必須設定結束日期")
            }

            // 確保結束日期晚於開始日期
            let calendar = Calendar.current
            let startDay = calendar.startOfDay(for: model.startDate)
            let endDay = calendar.startOfDay(for: endDate)

            guard endDay > startDay else {
                return .failure("結束日期必須晚於開始日期")
            }

            // 檢查至少需要 2 天
            let daysDifference = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
            guard daysDifference >= 1 else {
                return .failure("多日場次至少需要 2 天")
            }

            return .success

        case .permanent:
            // 無限期場次：不可有 endDate
            guard model.endDate == nil else {
                return .failure("無限期場次不可設定結束日期")
            }

            return .success
        }
    }

    // MARK: - Helper Methods

    /// 批量更新相關交易記錄的 Session 資訊
    /// 注意：只更新 sessionTitle，不修改交易的 timestamp（交易時間應該是不可變的事實）
    private func updateRelatedTransactions(sessionId: UUID, newTitle: String?, newDate: Date?) {
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "sessionId == %@", sessionId as CVarArg)

        do {
            let transactions = try context.fetch(request)

            for transaction in transactions {
                // 更新 sessionTitle
                if let newTitle = newTitle {
                    transaction.sessionTitle = newTitle
                }

                // ⚠️ 不修改 timestamp：交易時間應該保持為實際發生的時間
            }

            print("✅ 已更新 \(transactions.count) 筆交易記錄的 Session 標題")
        } catch {
            print("❌ 更新交易記錄失敗: \(error)")
        }
    }

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

    // MARK: - Debug Functions
    
    /// 調試用：顯示所有交易記錄的詳細內容
    func debugAllTransactions() {
        print("🔍 === 所有交易記錄詳細內容 ===")
        
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        do {
            let allTransactions = try context.fetch(request)
            print("📊 資料庫總交易數: \(allTransactions.count)")
            print("")
            
            for (index, transaction) in allTransactions.enumerated() {
                print("💰 交易 #\(index + 1)")
                print("  🆔 交易 ID: \(transaction.id)")
                print("  🏷️ Session ID: \(transaction.sessionId)")
                print("  🔗 Session 關聯: \(transaction.session?.id.uuidString ?? "nil")")
                print("  💵 總金額: \(transaction.totalAmount)")
                print("  📅 時間: \(transaction.timestamp)")
                print("  💳 支付方式: \(transaction.paymentMethod)")
                
                // 解析商品明細
                if let itemsData = transaction.itemsData,
                   let items = try? JSONDecoder().decode([SummaryItemModel].self, from: itemsData) {
                    print("  🛒 商品明細 (\(items.count) 項):")
                    for item in items {
                        print("    - \(item.name) x\(item.quantity) = \(item.total)")
                    }
                } else {
                    print("  🛒 商品明細: 無法解析")
                }
                print("  ---")
            }
            
            // 檢查哪些 Session 還存在
            let sessionRequest: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
            let existingSessions = try context.fetch(sessionRequest)
            print("📊 現存 Session 數: \(existingSessions.count)")
            
            let existingSessionIds = Set(existingSessions.map { $0.id })
            let transactionSessionIds = Set(allTransactions.map { $0.sessionId })
            let orphanedTransactionSessionIds = transactionSessionIds.subtracting(existingSessionIds)
            
            print("🔍 孤兒交易記錄 (Session已刪除): \(orphanedTransactionSessionIds.count) 個不同的Session")
            for sessionId in orphanedTransactionSessionIds {
                let count = allTransactions.filter { $0.sessionId == sessionId }.count
                print("  📦 Session \(sessionId): \(count) 筆交易")
            }
            
        } catch {
            print("❌ 調試查詢失敗: \(error)")
        }
        
        print("🔍 === 結束 ===")
    }
    
    /// 調試用：檢查刪除Session後交易記錄的狀態
    func debugTransactionStatus(forSessionId sessionId: UUID) {
        print("🔍 調試：檢查 Session \(sessionId) 的交易記錄狀態")
        
        // 1. 檢查 Session 是否還存在
        let sessionRequest: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        sessionRequest.predicate = NSPredicate(format: "id == %@", sessionId as CVarArg)
        
        do {
            let sessionResults = try context.fetch(sessionRequest)
            print("📊 Session 存在數量: \(sessionResults.count)")
            
            // 2. 檢查交易記錄
            let transactionRequest: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
            transactionRequest.predicate = NSPredicate(format: "sessionId == %@", sessionId as CVarArg)
            
            let transactionResults = try context.fetch(transactionRequest)
            print("📊 該 Session 的交易數: \(transactionResults.count)")
            
            for transaction in transactionResults {
                print("  💰 交易 ID: \(transaction.id)")
                print("  💰 Session 關聯: \(transaction.session?.id.uuidString ?? "nil")")
                print("  💰 SessionId 欄位: \(transaction.sessionId)")
                print("  💰 總金額: \(transaction.totalAmount)")
                print("  ---")
            }
            
            // 3. 檢查所有交易記錄
            let allTransactionRequest: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
            let allTransactions = try context.fetch(allTransactionRequest)
            print("📊 資料庫總交易數: \(allTransactions.count)")
            
        } catch {
            print("❌ 調試查詢失敗: \(error)")
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
