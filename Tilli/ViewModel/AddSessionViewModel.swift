//
//  AddSessionViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/17.
//

import Foundation

class AddSessionViewModel: ObservableObject {
    @Published var sessionName: String
    @Published var sessionDate: Date
    @Published var selectedCurrency: String
    @Published var newCategory: String = ""
    @Published var categories: [CategoryModel]
    @Published var editingCategoryID: UUID?

    // Alert 相關狀態
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var categoryPendingDeletion: UUID?
    @Published var categoryPendingRestore: UUID?
    @Published var isDisableAction = false

    var editingSession: SessionModel?

    // 用於獲取最新狀態的 DataManager
    private var transactionDataManager: TransactionDataManager?
    private var productRepository: ProductRepository?

    // 判斷是否有交易記錄（用於決定是否可編輯幣別）
    var isEditingWithTransaction: Bool {
        return hasTransaction()
    }
    
    var sortedCategories: [CategoryModel] {
        categories.sorted(by: { $0.createdAt < $1.createdAt })
    }
    
    var activeSortedCategories: [CategoryModel] {
        categories.filter { !$0.isDisabled }.sorted(by: { $0.createdAt < $1.createdAt })
    }
    
    var disabledSortedCategories: [CategoryModel] {
        categories.filter { $0.isDisabled }.sorted(by: { $0.createdAt < $1.createdAt })
    }
    
    var selectedCategory: CategoryModel? {
        sortedCategories.first(where: { $0.id == editingCategoryID })
    }

    init(sessionToEdit: SessionModel? = nil) {
        self.editingSession = sessionToEdit
        self.sessionName = sessionToEdit?.title ?? ""
        self.sessionDate = sessionToEdit?.date ?? Date()
        self.selectedCurrency = sessionToEdit?.currency ?? "TWD"
        self.categories = sessionToEdit?.categories ?? []
    }
    
    /// 更新 DataManager 引用
    func updateDataManagers(transactionDataManager: TransactionDataManager, productRepository: ProductRepository) {
        self.transactionDataManager = transactionDataManager
        self.productRepository = productRepository
    }

    func updateCategoryName(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 避免同名
        if categories.contains(where: { $0.name == trimmed && $0.id != id }) {
            return
        }

        if let index = categories.firstIndex(where: { $0.id == id }) {
            categories[index].name = trimmed
        }
    }

    func removeCategory(byId categoryId: UUID) {
        categories.removeAll { $0.id == categoryId }
    }
    
    func disableCategory(byId categoryId: UUID) {
        if let index = categories.firstIndex(where: { $0.id == categoryId }) {
            categories[index].isDisabled = true
        }
    }
    
    func restoreCategory(byId categoryId: UUID) {
        if let index = categories.firstIndex(where: { $0.id == categoryId }) {
            categories[index].isDisabled = false
        }
    }

    // 嘗試將 newCategory 加入,成功則清空 newCategory,失敗回傳錯誤訊息
    func tryAddCategory() -> String? {
        let trimmed = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return nil }

        if categories.contains(where: { $0.name == trimmed }) {
            return "此類別已存在"
        }

        let new = CategoryModel(id: UUID(), name: trimmed)
        categories.append(new)

        DispatchQueue.main.async {
            self.newCategory = ""
        }

        return nil
    }
    
    func hasTransaction(for categoryId: UUID? = nil) -> Bool {
        guard let sessionId = editingSession?.id else { return false }
        
        let transactions: [TransactionModel]
        if let transactionManager = transactionDataManager {
            transactions = transactionManager.fetchTransactions(forSessionId: sessionId)
        } else {
            transactions = editingSession?.transactions ?? []
        }
        
        // 如果沒有指定 categoryId，檢查是否有任何交易
        guard let categoryId = categoryId else {
            return !transactions.isEmpty
        }
        
        // 檢查特定類別的交易
        return transactions.contains { transaction in
            transaction.items.contains { $0.categoryId == categoryId }
        }
    }
    
    /// 檢查類別是否有產品（從最新數據源）
    func hasProducts(for categoryId: UUID) -> Bool {
        guard let sessionId = editingSession?.id,
              let productRepo = productRepository else {
            return false
        }
        let products = productRepo.fetchProducts(forSessionId: sessionId)
        return products.contains { $0.categoryId == categoryId }
    }

    
    // MARK: - Alert 處理邏輯
    
    /// 處理停用操作
    func handleDisableAction(for categoryId: UUID) {
        alertMessage = "已有交易記錄不可刪除，只能停用"
        categoryPendingDeletion = categoryId
        isDisableAction = true
        showAlert = true
    }
    
    /// 處理刪除操作
    func handleDeleteAction(for category: CategoryModel) {
        if hasProducts(for: category.id) {
            // 有商品 → 警告後再刪除
            alertMessage = "此類別仍有產品，確定要刪除嗎？"
            categoryPendingDeletion = category.id
            isDisableAction = false
            showAlert = true
        } else {
            // 沒有商品 → 直接刪除
            removeCategory(byId: category.id)
        }
    }
    
    /// 處理復原操作
    func handleRestoreAction(for categoryId: UUID) {
        categoryPendingRestore = categoryId
        showAlert = true
    }
    
    /// 確認刪除/停用操作
    func confirmDeletionAction() {
        guard let categoryId = categoryPendingDeletion else { return }
        
        if isDisableAction {
            disableCategory(byId: categoryId)
        } else {
            removeCategory(byId: categoryId)
        }
        
        resetDeletionState()
    }
    
    /// 確認復原操作
    func confirmRestoreAction() {
        guard let categoryId = categoryPendingRestore else { return }
        restoreCategory(byId: categoryId)
        categoryPendingRestore = nil
    }
    
    /// 取消刪除/停用操作
    func cancelDeletionAction() {
        resetDeletionState()
    }
    
    /// 取消復原操作
    func cancelRestoreAction() {
        categoryPendingRestore = nil
    }
    
    /// 重置刪除狀態
    private func resetDeletionState() {
        categoryPendingDeletion = nil
        isDisableAction = false
    }
    
    /// 處理 Swipe Actions
    func getSwipeAction(for category: CategoryModel) -> SwipeActionType {
        if hasTransaction(for: category.id) {
            return .disable
        } else {
            return .delete
        }
    }
    
    /// 驗證保存條件
    func validateSave() -> ValidationResult {
        // 儲存前嘗試新增 newCategory
        if let error = tryAddCategory() {
            return .failure(error)
        }

        if categories.filter({ !$0.isDisabled }).isEmpty {
            return .failure("請至少輸入一個類別")
        }
        
        return .success
    }

    func save() -> SessionModel {
        let baseSession = editingSession ?? SessionModel(
            title: "",
            date: Date(),
            categories: [],
            createdAt: Date()
        )

        return SessionModel(
            id: baseSession.id,
            title: sessionName,
            date: sessionDate,
            categories: categories,
            createdAt: baseSession.createdAt,
            transactions: baseSession.transactions,
            currency: selectedCurrency
        )
    }
}

// MARK: - Helper Enums

enum SwipeActionType {
    case delete
    case disable
}

enum ValidationResult {
    case success
    case failure(String)
}
