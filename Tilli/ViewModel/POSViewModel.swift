//
//  POSViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/4.
//

import SwiftUI
import Foundation

enum ProductLayoutMode: String, Codable {
    case list
    case grid
}

class POSViewModel: ObservableObject {

    @Binding var event: EventModel
    @Published var categories: [CategoryModel] = []
    @Published var products: [ProductModel] = []
    @Published var quantities: [UUID: Int] = [:]
    @Published var selectedDiscountId: UUID?  // 當前選擇的折扣 ID（整筆訂單）

    // Alert 相關狀態（僅無庫存提醒使用）
    @Published var showAlert = false
    @Published var alertMessage = ""

    // Product Detail 相關狀態
    @Published var expandedCategories: Set<UUID> = []
    @Published var showDisabledProducts = false

    // 布局模式（保存到 UserDefaults）
    @Published var layoutMode: ProductLayoutMode {
        didSet {
            UserDefaults.standard.set(layoutMode.rawValue, forKey: "ProductLayoutMode")
        }
    }
    
    // 用於獲取最新狀態的 DataManager
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
        let activeCategories = event.categories.filter { !$0.isDisabled }
        return activeCategories.contains { category in
            !getSortedProductsForCategory(category.id).isEmpty
        }
    }

    /// 是否應該顯示空狀態（沒有任何商品包括下架商品）
    var shouldShowEmptyState: Bool {
        return !hasAnyProducts && disabledProducts.isEmpty
    }

    /// 取得選中的折扣 Model
    var selectedDiscount: DiscountModel? {
        guard let id = selectedDiscountId else { return nil }
        return event.discounts.first { $0.id == id }
    }

    init(event: Binding<EventModel>) {
        self._event = event

        // 从 UserDefaults 讀取布局模式
        if let savedMode = UserDefaults.standard.string(forKey: "ProductLayoutMode"),
           let mode = ProductLayoutMode(rawValue: savedMode) {
            self.layoutMode = mode
        } else {
            self.layoutMode = .list  // 默認為列表模式
        }
    }
    
    // MARK: - DataManager 管理
    
    /// 更新 DataManager 引用
    func updateDataManagers(productRepository: ProductRepository) {
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
        // 「商品名」目前無庫存，無法加入訂單。請先進貨補充庫存。
        alertMessage = String.localized("productDetailNoStock \(productName)")
        showAlert = true
    }
    
    /// 取得分類下已排序的商品（有庫存在前，無庫存在後）
    func getSortedProductsForCategory(_ categoryId: UUID) -> [ProductModel] {
        let categoryProducts = activeProducts.filter { $0.categoryId == categoryId }
        
        // 將商品分為有庫存和無庫存兩組
        let inStockProducts = categoryProducts.filter { !isOutOfStock($0) }
        let outOfStockProducts = categoryProducts.filter { isOutOfStock($0) }
        
        // 各組內部按名稱排序（使用語言環境排序），然後合併（有庫存在前）
        let sortedInStock = inStockProducts.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let sortedOutOfStock = outOfStockProducts.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        
        return sortedInStock + sortedOutOfStock
    }
    
    func loadProducts() {
        guard let productRepo = productRepository else { return }
        products = productRepo.fetchProducts(forEventId: event.id)
        categories = event.categories
        
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
    
    func quantity(for product: ProductModel) -> Int {
        quantities[product.id, default: 0]
    }
    
    func clearAllQuantities() {
        quantities.removeAll()
        selectedDiscountId = nil
    }

    /// 計算小計（未套用折扣）
    func subtotal() -> Decimal {
        activeProducts.reduce(Decimal(0)) { result, product in
            let qty = quantities[product.id, default: 0]
            let itemTotal = MoneyHelper.multiply(product.price, Decimal(qty))
            return MoneyHelper.add(result, itemTotal)
        }
    }

    /// 計算總金額（套用折扣）
    func totalAmount() -> Decimal {
        let sub = subtotal()

        guard let discount = selectedDiscount else {
            return sub
        }

        switch discount.type {
        case .percentage:
            let rate = MoneyHelper.subtract(Decimal(1), discount.value / 100)
            return MoneyHelper.multiply(sub, rate)
        case .amount:
            return max(MoneyHelper.subtract(sub, discount.value), 0)
        }
    }

    /// 檢查折扣是否超過商品總額（僅適用於固定金額折扣）
    var isDiscountExceedsLimit: Bool {
        guard let discount = selectedDiscount else { return false }
        let sub = subtotal()

        switch discount.type {
        case .percentage:
            return false  // 百分比已限制 ≤ 100%，不會超過
        case .amount:
            return discount.value > sub && sub > 0
        }
    }

    /// 計算實際套用的折扣（用於記錄交易）
    func effectiveDiscount() -> DiscountModel? {
        guard let discount = selectedDiscount else { return nil }
        let sub = subtotal()

        switch discount.type {
        case .percentage:
            // 百分比折扣直接使用原值
            return discount
        case .amount:
            // 固定金額折扣：取折扣值和商品總額的較小值
            let effectiveValue = min(discount.value, sub)
            return DiscountModel(type: .amount, value: effectiveValue)
        }
    }

    /// 折扣超過上限的提示訊息
    var discountWarningMessage: String? {
        guard isDiscountExceedsLimit else { return nil }
        // 折扣不可超過商品金額，已自動調整
        return String.localized("productDetailDiscountExceed")
    }

    /// 產生 SummaryItemModel 列表（不含折扣，折扣存在 Transaction 層級）
    func selectedProductsWithQuantity() -> [SummaryItemModel] {
        activeProducts.compactMap { product -> SummaryItemModel? in
            let qty = quantity(for: product)
            guard qty > 0 else { return nil }

            return SummaryItemModel(
                productId: product.id,
                name: product.name,
                price: product.price,
                categoryId: product.categoryId,
                category: product.categoryName,
                quantity: qty,
                timestamp: Date()
            )
        }
    }
    
    // MARK: - Alert 創建方法（無庫存提醒）
    func createAlert() -> Alert {
        // 提醒 / 好
        Alert(
            title: Text("commonReminder"),
            message: Text(alertMessage),
            dismissButton: .default(Text("commonOK"))
        )
    }
}
