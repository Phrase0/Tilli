//
//  SessionDetailViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/8.
//

import SwiftUI

class SessionDetailViewModel: ObservableObject {
    
    @Binding var session: SessionModel
    @Published var categories: [CategoryModel] = []
    @Published var products: [ProductModel] = []
    @Published var quantities: [UUID: Int] = [:]
    @Published var selectedDiscounts: [UUID: Int] = [:]
    
    // Alert 相關狀態
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var productPendingDeletion: UUID?
    @Published var productPendingRestore: UUID?
    @Published var isDisableAction = false
    
    
    // 新增：用來追蹤每個分類的展開狀態
    @Published var expandedCategories: Set<UUID> = []
    
    // 下架商品區顯示狀態
    @Published var showDisabledProducts = false
    
    // 用於獲取最新狀態的 DataManager
    private var transactionDataManager: TransactionDataManager?
    private var productDataManager: ProductDataManager?
    
    // 計算屬性：啟用的產品
    var activeProducts: [ProductModel] {
        products.filter { !$0.isDisabled }
    }
    
    // 計算屬性：下架的產品
    var disabledProducts: [ProductModel] {
        products.filter { $0.isDisabled }
    }
    
    init(session: Binding<SessionModel>) {
        self._session = session
    }
    
    // MARK: - 分類展開狀態管理
    
    /// 切換分類的展開狀態
    func toggleCategoryExpansion(_ categoryId: UUID) {
        withAnimation(.easeInOut(duration: 0.3)) {
            if expandedCategories.contains(categoryId) {
                expandedCategories.remove(categoryId)
            } else {
                expandedCategories.insert(categoryId)
            }
        }
    }
    
    /// 檢查分類是否展開
    func isCategoryExpanded(_ categoryId: UUID) -> Bool {
        return expandedCategories.contains(categoryId)
    }
    
    /// 初始化時展開所有分類
    func expandAllCategories() {
        expandedCategories = Set(categories.filter { !$0.isDisabled }.map { $0.id })
    }
    
    // MARK: - 更新 DataManager 引用
    func updateDataManagers(transactionDataManager: TransactionDataManager, productDataManager: ProductDataManager) {
        self.transactionDataManager = transactionDataManager
        self.productDataManager = productDataManager
    }
    
    // MARK: - 庫存檢查相關方法
    
    /// 檢查商品是否無庫存
    func isOutOfStock(_ product: ProductModel) -> Bool {
        return product.stock <= 0
    }
    
    /// 檢查是否有無庫存商品
    func hasOutOfStockProducts() -> Bool {
        return activeProducts.contains { isOutOfStock($0) }
    }
    
    /// 取得無庫存商品數量
    func outOfStockProductsCount() -> Int {
        return activeProducts.filter { isOutOfStock($0) }.count
    }
    
    /// 顯示無庫存商品點擊提醒
    func showOutOfStockAlert(for productName: String) {
        alertMessage = "「\(productName)」目前無庫存，無法加入訂單。請先進貨補充庫存。"
        showAlert = true
    }
    
    /// 取得分類下已排序的商品（有庫存在前，無庫存在後）
    func getSortedProductsForCategory(_ categoryId: UUID) -> [ProductModel] {
        let categoryProducts = activeProducts.filter { $0.categoryId == categoryId }
        
        // 將商品分為有庫存和無庫存兩組
        let inStockProducts = categoryProducts.filter { !isOutOfStock($0) }
        let outOfStockProducts = categoryProducts.filter { isOutOfStock($0) }
        
        // 各組內部按名稱排序，然後合併（有庫存在前）
        let sortedInStock = inStockProducts.sorted { $0.name < $1.name }
        let sortedOutOfStock = outOfStockProducts.sorted { $0.name < $1.name }
        
        return sortedInStock + sortedOutOfStock
    }
    
    // MARK: - 交易檢查邏輯
    func hasTransaction(for productId: UUID) -> Bool {
        guard let sessionId = session.id as UUID? else { return false }
        
        // 優先使用 TransactionDataManager 獲取最新的交易數據
        if let transactionManager = transactionDataManager {
            let transactions = transactionManager.fetchTransactions(forSessionId: sessionId)
            for transaction in transactions {
                for item in transaction.items {
                    if item.productId == productId {
                        return true
                    }
                }
            }
            return false
        }
        
        // 後備方案：使用初始的 session 數據
        for transaction in session.transactions {
            for item in transaction.items {
                if item.productId == productId {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - 產品管理方法
    
    func loadProducts() {
        guard let productManager = productDataManager else { return }
        products = productManager.fetchProducts(forSessionId: session.id)
        categories = session.categories
        
        // 首次載入時展開所有分類
        if expandedCategories.isEmpty {
            expandAllCategories()
        }
    }
    
    func removeProduct(byId productId: UUID) {
        guard let productManager = productDataManager else { return }
        let allProducts = productManager.fetchProducts(forSessionId: session.id)
        if let product = allProducts.first(where: { $0.id == productId }) {
            productManager.deleteProduct(product)
        }
    }
    
    func disableProduct(byId productId: UUID) {
        guard let productManager = productDataManager else { return }
        let allProducts = productManager.fetchProducts(forSessionId: session.id)
        if var product = allProducts.first(where: { $0.id == productId }) {
            product.isDisabled = true
            productManager.updateProduct(product)
        }
    }
    
    func restoreProduct(byId productId: UUID) {
        guard let productManager = productDataManager else { return }
        let allProducts = productManager.fetchProducts(forSessionId: session.id)
        if var product = allProducts.first(where: { $0.id == productId }) {
            product.isDisabled = false
            productManager.updateProduct(product)
        }
    }
    
    // MARK: - Alert 處理邏輯
    
    /// 處理下架操作
    func handleDisableAction(for productId: UUID) {
        alertMessage = "已有交易紀錄不可刪除，只能下架"
        productPendingDeletion = productId
        isDisableAction = true
        showAlert = true
    }
    
    /// 處理刪除操作
    func handleDeleteAction(for productId: UUID) {
        alertMessage = "確定要刪除此產品嗎？"
        productPendingDeletion = productId
        isDisableAction = false
        showAlert = true
    }
    
    /// 處理復原操作
    func handleRestoreAction(for productId: UUID) {
        productPendingRestore = productId
        showAlert = true
    }
    
    /// 確認刪除/下架操作
    func confirmDeletionAction() {
        guard let productId = productPendingDeletion else { return }
        
        if isDisableAction {
            disableProduct(byId: productId)
        } else {
            removeProduct(byId: productId)
            // 清除該產品的選擇狀態
            quantities.removeValue(forKey: productId)
            selectedDiscounts.removeValue(forKey: productId)
        }
        
        loadProducts()
        resetDeletionState()
    }
    
    /// 確認復原操作
    func confirmRestoreAction() {
        guard let productId = productPendingRestore else { return }
        restoreProduct(byId: productId)
        loadProducts()
        productPendingRestore = nil
    }
    
    /// 取消刪除/下架操作
    func cancelDeletionAction() {
        resetDeletionState()
    }
    
    /// 取消復原操作
    func cancelRestoreAction() {
        productPendingRestore = nil
    }
    
    /// 重置刪除狀態
    private func resetDeletionState() {
        productPendingDeletion = nil
        isDisableAction = false
    }
    
    /// 處理 Actions（參考 AddSessionViewModel）
    func getActionType(for productId: UUID) -> ProductActionType {
        if hasTransaction(for: productId) {
            return .disable
        } else {
            return .delete
        }
    }
    
    // MARK: - 購物車邏輯（更新以支援庫存檢查）
    
    func increaseQuantity(for product: ProductModel) {
        // 檢查是否無庫存
        if isOutOfStock(product) {
            showOutOfStockAlert(for: product.name)
            return
        }
        
        let current = quantities[product.id, default: 0]
        if current < product.stock {
            quantities[product.id] = current + 1
        }
    }
    
    func decreaseQuantity(for product: ProductModel) {
        // 無庫存商品也不能減少數量
        if isOutOfStock(product) {
            return
        }
        
        let current = quantities[product.id, default: 0]
        if current > 0 {
            quantities[product.id] = current - 1
        }
    }
    
    func toggleDiscount(for product: ProductModel, percent: Int) {
        // 無庫存商品不能選擇折扣
        if isOutOfStock(product) {
            return
        }
        
        if selectedDiscounts[product.id] == percent {
            selectedDiscounts[product.id] = nil
        } else {
            selectedDiscounts[product.id] = percent
        }
    }
    
    func isDiscountSelected(for product: ProductModel, percent: Int) -> Bool {
        selectedDiscounts[product.id] == percent
    }
    
    func quantity(for product: ProductModel) -> Int {
        quantities[product.id, default: 0]
    }
    
    func clearAllQuantities() {
        quantities.removeAll()
        selectedDiscounts.removeAll()
    }
    
    func totalAmount() -> Int {
        activeProducts.reduce(0) { result, product in
            let qty = quantities[product.id, default: 0]
            let discount = selectedDiscounts[product.id] ?? 0
            let discountedPrice = product.price * (1 - Double(discount) / 100)
            let roundedTotal = (discountedPrice * Double(qty)).rounded()
            return result + Int(roundedTotal)
        }
    }
    
    func selectedProductsWithQuantityAndDiscount() -> [SummaryItemModel] {
        activeProducts.compactMap { product in
            let qty = quantity(for: product)
            guard qty > 0 else { return nil }

            let discount = selectedDiscounts[product.id, default: 0]

            return SummaryItemModel(
                productId: product.id,
                name: product.name,
                price: product.price,
                categoryId: product.categoryId,
                category: product.categoryName,
                quantity: qty,
                discount: discount,
                timestamp: Date()
            )
        }
    }
}

// MARK: - Helper Enums

enum ProductActionType {
    case delete
    case disable
}
