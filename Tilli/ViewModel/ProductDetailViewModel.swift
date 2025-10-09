//
//  ProductViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/4.
//

import SwiftUI
import Foundation

class ProductViewModel: ObservableObject {
    
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
    
    // Product Detail 相關狀態
    @Published var expandedCategories: Set<UUID> = []
    @Published var showDisabledProducts = false
    
    // 用於獲取最新狀態的 DataManager
    private var transactionDataManager: TransactionDataManager?
    private var sessionDataManager: SessionDataManager?
    private var productRepository: ProductRepository?
    
    // 計算屬性：可顯示的產品（Product.isDisabled == false && Category.isDisabled == false）
    var activeProducts: [ProductModel] {
        products.filter { product in
            let isProductEnabled = !product.isDisabled
            let isCategoryEnabled = categories.first(where: { $0.id == product.categoryId })?.isDisabled == false
            return isProductEnabled && isCategoryEnabled
        }
    }
    
    // 計算屬性：已停用且 Category 未停用的產品（只顯示在下架區的產品）
    var disabledProducts: [ProductModel] {
        products.filter { product in
            let isProductDisabled = product.isDisabled
            let isCategoryEnabled = categories.first(where: { $0.id == product.categoryId })?.isDisabled == false
            // 只顯示：Product 停用 且 Category 未停用 的產品
            return isProductDisabled && isCategoryEnabled
        }
    }

    // MARK: - 商品狀態邏輯

    /// 檢查是否有任何可用商品（用於判斷是否顯示空狀態）
    var hasAnyProducts: Bool {
        let activeCategories = session.categories.filter { !$0.isDisabled }
        return activeCategories.contains { category in
            !getSortedProductsForCategory(category.id).isEmpty
        }
    }

    /// 是否應該顯示空狀態（沒有任何商品包括下架商品）
    var shouldShowEmptyState: Bool {
        return !hasAnyProducts && disabledProducts.isEmpty
    }
    
    init(session: Binding<SessionModel>) {
        self._session = session
    }
    
    // MARK: - DataManager 管理
    
    /// 更新 DataManager 引用
    func updateDataManagers(
        transactionDataManager: TransactionDataManager,
        sessionDataManager: SessionDataManager,
        productRepository: ProductRepository
    ) {
        self.transactionDataManager = transactionDataManager
        self.sessionDataManager = sessionDataManager
        self.productRepository = productRepository
    }
    
    // MARK: - Product Detail 相關方法
    
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
    
    /// 檢查商品是否無庫存
    func isOutOfStock(_ product: ProductModel) -> Bool {
        return product.stock <= 0
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
    
    func loadProducts() {
        guard let productRepo = productRepository else { return }
        products = productRepo.fetchProducts(forSessionId: session.id)
        categories = session.categories
        
        // 首次載入時展開所有分類
        if expandedCategories.isEmpty {
            expandAllCategories()
        }
    }
    
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
    
    func totalAmount() -> Decimal {
        activeProducts.reduce(Decimal(0)) { result, product in
            let qty = quantities[product.id, default: 0]
            let discount = selectedDiscounts[product.id] ?? 0
            let total = MoneyHelper.calculateTotal(
                price: product.price,
                quantity: qty,
                discountPercentage: discount
            )
            return MoneyHelper.add(result, total)
        }
    }
    
    func selectedProductsWithQuantityAndDiscount() -> [SummaryItemModel] {
        activeProducts.compactMap { product -> SummaryItemModel? in
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
    
    // MARK: - 共用方法
    
    /// 檢查產品是否有交易記錄
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
    
    func removeProduct(byId productId: UUID) {
        guard let productRepo = productRepository else { return }
        let result = productRepo.deleteProduct(productId)
        
        switch result {
        case .deleted(let message):
            print(message)
        case .disabledInstead(let message):
            alertMessage = message
            showAlert = true
        case .failed(let message):
            alertMessage = message
            showAlert = true
        }
    }
    
    func disableProduct(byId productId: UUID) {
        guard let productRepo = productRepository else { return }
        productRepo.disableProduct(productId)
    }
    
    func restoreProduct(byId productId: UUID) {
        guard let productRepo = productRepository else { return }
        productRepo.enableProduct(productId)
    }
    
    // MARK: - Alert 處理邏輯
    
    /// 處理下架操作
    func handleDisableAction(for productId: UUID) {
        alertMessage = "已有交易記錄不可刪除，只能下架"
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
    
    // MARK: - Alert 創建方法
    func createAlert() -> Alert {
        if productPendingRestore != nil {
            // 復原操作的警告
            return Alert(
                title: Text("確認復原"),
                message: Text("確定要復原此產品嗎？"),
                primaryButton: .default(Text("確認")) { [weak self] in
                    self?.confirmRestoreAction()
                },
                secondaryButton: .cancel { [weak self] in
                    self?.cancelRestoreAction()
                }
            )
        } else if productPendingDeletion != nil {
            if isDisableAction {
                // 下架操作的警告
                return Alert(
                    title: Text("確認下架"),
                    message: Text(alertMessage),
                    primaryButton: .default(Text("確認")) { [weak self] in
                        self?.confirmDeletionAction()
                    },
                    secondaryButton: .cancel { [weak self] in
                        self?.cancelDeletionAction()
                    }
                )
            } else {
                // 刪除操作的警告
                return Alert(
                    title: Text("確認刪除"),
                    message: Text(alertMessage),
                    primaryButton: .destructive(Text("刪除")) { [weak self] in
                        self?.confirmDeletionAction()
                    },
                    secondaryButton: .cancel { [weak self] in
                        self?.cancelDeletionAction()
                    }
                )
            }
        } else {
            return Alert(
                title: Text("提醒"),
                message: Text(alertMessage),
                dismissButton: .default(Text("好"))
            )
        }
    }
}

// MARK: - Helper Enums

enum ProductActionType {
    case delete
    case disable
}
