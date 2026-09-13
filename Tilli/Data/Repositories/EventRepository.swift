//
//  EventRepository.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/27.
//

import CoreData
import SwiftUI
import FirebaseAuth

/// 場次驗證結果
enum EventValidationResult {
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

class EventRepository: ObservableObject {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    @Published var events: [EventModel] = []

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
        self.context = container.viewContext
        fetchEvents()

    }


    // MARK: - Event CRUD Operations
    
    /// 取得所有 Event，包含完整的 Category、Product、Transaction
    func fetchEvents() {
        let request: NSFetchRequest<CDEventEntity> = CDEventEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        // 預先載入相關資料，避免多次查詢
        request.relationshipKeyPathsForPrefetching = ["categories", "categories.products", "transactions"]

        do {
            let result = try context.fetch(request)
            let newEvents = result.map { $0.toModel() }
            self.events = newEvents
        } catch {
            print("Fetch events failed:", error)
        }
    }

    /// 根據 ID 取得特定 Event
    func fetchEvent(by id: UUID) -> EventModel? {
        let request: NSFetchRequest<CDEventEntity> = CDEventEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.relationshipKeyPathsForPrefetching = ["categories", "categories.products", "transactions"]

        do {
            if let entity = try context.fetch(request).first {
                return entity.toModel()
            }
        } catch {
            print("Fetch event by ID failed:", error)
        }
        return nil
    }

    /// 新增 Event（僅處理 Event 層級）
    func addEvent(_ model: EventModel) {
        // 驗證場次資料
        let validationResult = validateEvent(model)
        guard validationResult.isValid else {
            print("❌ 場次驗證失敗: \(validationResult.errorMessage ?? "未知錯誤")")
            return
        }

        let entity = CDEventEntity(context: context)
        entity.update(from: model, context: context)
        let currentUserId = Auth.auth().currentUser?.uid ?? UserProfileModel.guestUserId
        entity.userId = currentUserId
        entity.markPendingSync()

        // 創建 Categories 和 Products
        for categoryModel in model.categories {
            let categoryEntity = CDCategoryEntity(context: context)
            categoryEntity.update(from: categoryModel, context: context)
            categoryEntity.userId = currentUserId
            categoryEntity.markPendingSync()
            categoryEntity.event = entity

            for productModel in categoryModel.products {
                let productEntity = CDProductEntity(context: context)
                productEntity.update(from: productModel, context: context)
                productEntity.userId = currentUserId
                productEntity.markPendingSync()
                productEntity.category = categoryEntity
            }
        }

        if saveContext() {
            fetchEvents()
            // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md
        }
    }

    /// 更新 Event（包含 Category 的變更處理）
    func updateEvent(_ model: EventModel) {
        // 驗證場次資料
        let validationResult = validateEvent(model)
        guard validationResult.isValid else {
            print("❌ 場次驗證失敗: \(validationResult.errorMessage ?? "未知錯誤")")
            return
        }

        let request: NSFetchRequest<CDEventEntity> = CDEventEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)
        request.relationshipKeyPathsForPrefetching = ["categories", "categories.products"]

        do {
            guard let entity = try context.fetch(request).first else {
                print("Event not found for update")
                return
            }

            // 更新 Event 基本屬性
            entity.title = model.title
            entity.startDate = model.startDate
            entity.endDate = model.endDate
            entity.dateType = model.dateType.rawValue
            entity.currency = model.currency
            entity.discountsData = try? JSONEncoder().encode(model.discounts)
            entity.markPendingSync()

            // 處理 Categories 的變更，收集 sync 需要的資訊
            let categoryChanges = updateCategoriesForEvent(entity: entity, newCategories: model.categories)

            if saveContext() {
                fetchEvents()
                // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md
            }
        } catch {
            print("Update event failed:", error)
        }
    }
    
    /// Category 變更記錄（供 sync 使用）
    struct CategoryChanges {
        var added: [CategoryModel] = []       // 新增的 categories
        var deletedIds: [UUID] = []            // 硬刪除的 category IDs
        var disabled: [CategoryModel] = []     // 停用的 categories
        var updated: [CategoryModel] = []      // 更新的 categories
    }

    /// 更新 Event 的 Categories，回傳變更記錄供 sync 使用
    @discardableResult
    private func updateCategoriesForEvent(entity: CDEventEntity, newCategories: [CategoryModel]) -> CategoryChanges {
        var changes = CategoryChanges()

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
        //
        // 守衛保留（repository 是最後一道防線），但**只拒絕、不偷偷做別的事**：
        // 原本會靜默把類別改成「停用」，呼叫端以為刪掉了、實際上資料還在而且被改了狀態。
        // 現在有交易的類別就是**原封不動留著**，UI 重載後會看到它還在 —— 這才是誠實的回饋。
        //
        // ⭐ 判斷一律用 `SummaryItem.categoryId` 快照（`TransactionIndex`），
        // 與 `AddEventViewModel.getSwipeAction` 用同一份答案（A1）。
        // 原本 repository 用「該類別目前的商品清單」推算，商品被搬走後答案就會跟 UI 相反。
        let index = transactionIndex(forEventId: entity.id)
        for categoryEntity in categoriesToDelete {
            guard let index, !index.hasTransaction(categoryId: categoryEntity.id) else {
                print("🔴 類別「\(categoryEntity.name)」已有交易紀錄（或索引建立失敗），不予刪除")
                continue
            }
            changes.deletedIds.append(categoryEntity.id)
            entity.removeFromCategories(categoryEntity)
            context.delete(categoryEntity)
        }

        // 新增新的 categories
        let currentUserId = Auth.auth().currentUser?.uid ?? UserProfileModel.guestUserId
        for categoryModel in categoriesToAdd {
            let categoryEntity = CDCategoryEntity(context: context)
            categoryEntity.update(from: categoryModel, context: context)
            categoryEntity.userId = currentUserId
            categoryEntity.markPendingSync()
            categoryEntity.event = entity
            entity.addToCategories(categoryEntity)

            // 新增該 category 下的 products
            for productModel in categoryModel.products {
                let productEntity = CDProductEntity(context: context)
                productEntity.update(from: productModel, context: context)
                productEntity.userId = currentUserId
                productEntity.markPendingSync()
                productEntity.category = categoryEntity
                categoryEntity.addToProducts(productEntity)
            }

            changes.added.append(categoryModel)
        }

        // 更新現有的 categories
        for categoryModel in categoriesToUpdate {
            if let categoryEntity = existingCategories.first(where: { $0.id == categoryModel.id }) {
                // 檢查是否有實際變更
                let nameChanged = categoryEntity.name != categoryModel.name
                let disabledChanged = categoryEntity.isDisabled != categoryModel.isDisabled
                let sortOrderChanged = categoryEntity.sortOrder != Int16(categoryModel.sortOrder)

                // 更新基本屬性
                categoryEntity.name = categoryModel.name
                categoryEntity.isDisabled = categoryModel.isDisabled
                categoryEntity.sortOrder = Int16(categoryModel.sortOrder)

                if nameChanged || disabledChanged || sortOrderChanged {
                    categoryEntity.markPendingSync()
                    changes.updated.append(categoryModel)
                }
            }
        }

        return changes
    }

    /// 刪除 Event（硬刪除，但保留 Transaction）
    ///
    /// ⚠️ 注意：刪除 Event 後，相關的 Transaction 記錄會保留，
    /// 但 Transaction.event 關聯會被設為 nil（deletionRule="Nullify"）。
    /// Transaction 記錄仍可透過 eventId 欄位查詢。
    func deleteEvent(_ eventId: UUID) {
        // 調試：刪除前檢查
        print("🔥 準備刪除 Event: \(eventId)")
        debugTransactionStatus(forEventId: eventId)

        let request: NSFetchRequest<CDEventEntity> = CDEventEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", eventId as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                // 刪除 Event：
                // - Categories 和 Products 會被級聯刪除（deletionRule="Cascade"）
                // - Transactions 會保留，但 event 關聯會被設為 nil（deletionRule="Nullify"）
                context.delete(entity)
                if saveContext() {
                    // 調試：刪除後檢查
                    print("🔥 已刪除 Event，檢查交易記錄狀態:")
                    debugTransactionStatus(forEventId: eventId)
                    print("")
                    fetchEvents()
                    // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md
                }
            }
        } catch {
            print("Delete event failed:", error)
        }
    }

    // MARK: - Transaction Operations (僅允許新增)
    
    /// 新增交易記錄（永久保留）
    func addTransaction(_ model: TransactionModel) {
        let eventRequest: NSFetchRequest<CDEventEntity> = CDEventEntity.fetchRequest()
        eventRequest.predicate = NSPredicate(format: "id == %@", model.eventId as CVarArg)

        do {
            guard let eventEntity = try context.fetch(eventRequest).first else {
                print("找不到對應 event，無法加入 transaction")
                return
            }

            let entity = CDTransactionEntity(context: context)
            entity.update(from: model, context: context)
            entity.userId = Auth.auth().currentUser?.uid ?? UserProfileModel.guestUserId
            entity.markPendingSync()
            eventEntity.addToTransactions(entity)

            if saveContext() {
                TransactionRepository.shared.notifyTransactionsChanged()
                // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md
            }
        } catch {
            print("加入 transaction 失敗:", error)
        }
    }

    /// 複製場次（包含所有類別和產品，但不包含交易記錄）
    func duplicateEvent(
        originalEventId: UUID,
        newTitle: String,
        newStartDate: Date,
        newEndDate: Date?,
        newDateType: EventDateType
    ) -> EventModel? {
        let request: NSFetchRequest<CDEventEntity> = CDEventEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", originalEventId as CVarArg)
        request.relationshipKeyPathsForPrefetching = ["categories", "categories.products"]

        do {
            guard let originalEntity = try context.fetch(request).first else {
                print("找不到要複製的場次")
                return nil
            }

            // 創建新的 Event 實體
            let copyUserId = Auth.auth().currentUser?.uid ?? UserProfileModel.guestUserId
            let newEventEntity = CDEventEntity(context: context)
            newEventEntity.id = UUID()
            newEventEntity.title = newTitle
            newEventEntity.startDate = newStartDate
            newEventEntity.dateType = newDateType.rawValue
            newEventEntity.endDate = newEndDate
            newEventEntity.createdAt = Date()
            newEventEntity.currency = originalEntity.currency
            newEventEntity.discountsData = originalEntity.discountsData
            newEventEntity.userId = copyUserId
            newEventEntity.markPendingSync()

            // 複製所有 Categories 和 Products（按 sortOrder 排序以保持順序）
            var inventoryChangeEntities: [CDInventoryChangeEntity] = []

            if let originalCategories = originalEntity.categories as? Set<CDCategoryEntity> {
                let sortedCategories = originalCategories.sorted { $0.sortOrder < $1.sortOrder }
                for originalCategory in sortedCategories {
                    let newCategoryEntity = CDCategoryEntity(context: context)
                    newCategoryEntity.id = UUID()
                    newCategoryEntity.name = originalCategory.name
                    newCategoryEntity.createdAt = Date()
                    newCategoryEntity.isDisabled = originalCategory.isDisabled
                    newCategoryEntity.sortOrder = originalCategory.sortOrder
                    newCategoryEntity.userId = copyUserId
                    newCategoryEntity.markPendingSync()
                    newCategoryEntity.event = newEventEntity

                    // 複製該 Category 下的所有 Products
                    if let originalProducts = originalCategory.products as? Set<CDProductEntity> {
                        for originalProduct in originalProducts {
                            let newProductEntity = CDProductEntity(context: context)
                            newProductEntity.id = UUID()
                            newProductEntity.eventId = newEventEntity.id
                            newProductEntity.name = originalProduct.name
                            newProductEntity.price = originalProduct.price
                            newProductEntity.stock = originalProduct.stock
                            newProductEntity.categoryId = newCategoryEntity.id
                            newProductEntity.note = originalProduct.note
                            newProductEntity.imageData = originalProduct.imageData
                            newProductEntity.isDisabled = originalProduct.isDisabled
                            newProductEntity.sortOrder = originalProduct.sortOrder
                            newProductEntity.userId = copyUserId
                            newProductEntity.markPendingSync()
                            newProductEntity.category = newCategoryEntity

                            // 若有庫存，建立「進貨入庫」記錄
                            if originalProduct.stock > 0 {
                                let changeEntity = CDInventoryChangeEntity(context: context)
                                changeEntity.id = UUID()
                                changeEntity.productId = newProductEntity.id
                                changeEntity.event = newEventEntity
                                changeEntity.product = newProductEntity
                                changeEntity.change = originalProduct.stock
                                changeEntity.reason = InventoryChangeReason.purchase.rawValue
                                changeEntity.customReason = nil
                                changeEntity.transactionId = nil
                                changeEntity.timestamp = Date()
                                changeEntity.userId = copyUserId
                                changeEntity.markPendingSync()
                                inventoryChangeEntities.append(changeEntity)
                            }
                        }
                    }
                }
            }

            if saveContext() {
                fetchEvents()
                // 返回新建立的 EventModel
                let newEvent = newEventEntity.toModel()
                let newEventId = newEventEntity.id
                let changeModels = inventoryChangeEntities.map { $0.toModel() }
                // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md
                return newEvent
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
    func validateEvent(_ model: EventModel) -> EventValidationResult {
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

    /// 建立該場次的交易索引（刪除守衛用）。查詢失敗回傳 nil，呼叫端保守處理。
    private func transactionIndex(forEventId eventId: UUID) -> TransactionIndex? {
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "eventId == %@", eventId as CVarArg)
        do {
            return TransactionIndex(transactions: try context.fetch(request).map { $0.toModel() })
        } catch {
            print("🔴 建立交易索引失敗:", error)
            return nil
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
                print("  🏷️ Event ID: \(transaction.eventId)")
                print("  🔗 Event 關聯: \(transaction.event?.id.uuidString ?? "nil")")
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
            
            // 檢查哪些 Event 還存在
            let eventRequest: NSFetchRequest<CDEventEntity> = CDEventEntity.fetchRequest()
            let existingEvents = try context.fetch(eventRequest)
            print("📊 現存 Event 數: \(existingEvents.count)")
            
            let existingEventIds = Set(existingEvents.map { $0.id })
            let transactionEventIds = Set(allTransactions.map { $0.eventId })
            let orphanedTransactionEventIds = transactionEventIds.subtracting(existingEventIds)
            
            print("🔍 孤兒交易記錄 (Event已刪除): \(orphanedTransactionEventIds.count) 個不同的Event")
            for eventId in orphanedTransactionEventIds {
                let count = allTransactions.filter { $0.eventId == eventId }.count
                print("  📦 Event \(eventId): \(count) 筆交易")
            }
            
        } catch {
            print("❌ 調試查詢失敗: \(error)")
        }
        
        print("🔍 === 結束 ===")
    }
    
    /// 調試用：檢查刪除Event後交易記錄的狀態
    func debugTransactionStatus(forEventId eventId: UUID) {
        print("🔍 調試：檢查 Event \(eventId) 的交易記錄狀態")
        
        // 1. 檢查 Event 是否還存在
        let eventRequest: NSFetchRequest<CDEventEntity> = CDEventEntity.fetchRequest()
        eventRequest.predicate = NSPredicate(format: "id == %@", eventId as CVarArg)
        
        do {
            let eventResults = try context.fetch(eventRequest)
            print("📊 Event 存在數量: \(eventResults.count)")
            
            // 2. 檢查交易記錄
            let transactionRequest: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
            transactionRequest.predicate = NSPredicate(format: "eventId == %@", eventId as CVarArg)
            
            let transactionResults = try context.fetch(transactionRequest)
            print("📊 該 Event 的交易數: \(transactionResults.count)")
            
            for transaction in transactionResults {
                print("  💰 交易 ID: \(transaction.id)")
                print("  💰 Event 關聯: \(transaction.event?.id.uuidString ?? "nil")")
                print("  💰 EventId 欄位: \(transaction.eventId)")
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
            print("✅ Event data saved to CoreData")
            return true
        } catch {
            print("Core Data save failed:", error)
            context.rollback()
            return false
        }
    }
}
