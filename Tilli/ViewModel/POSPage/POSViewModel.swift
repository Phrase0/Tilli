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

@MainActor
class POSViewModel: ObservableObject {

    /// 場次工作區的共用資料源（CONVENTIONS.md 規則 1 例外 2）
    private let dataSource: EventDataSource

    /// ⭐ event / categories / products 一律一起從 dataSource 取同一份快照，
    /// 不再出現「商品是新鮮的、類別是舊快照」（A3）
    @Published private(set) var event: EventModel
    @Published private(set) var categories: [CategoryModel] = []
    @Published private(set) var products: [ProductModel] = []
    @Published var quantities: [UUID: Int] = [:]
    /// 折扣：每個型別各自單選，可同時一個百分比 + 一個定額（§6.1）。
    ///
    /// 用型別當 key 而不是兩個獨立欄位 —— 之後多一種折扣型別時，
    /// 這裡與 `toggleDiscount` / `isSelected` 都不用改。
    @Published private(set) var selectedDiscountIds: [DiscountType: UUID] = [:]

    // Alert 相關狀態（僅無庫存提醒使用）
    @Published var showAlert = false
    @Published var alertMessage = ""

    // Product Detail 相關狀態
    @Published var expandedCategories: Set<UUID> = []

    // 布局模式（保存到 UserDefaults）
    @Published var layoutMode: ProductLayoutMode {
        didSet {
            UserDefaults.standard.set(layoutMode.rawValue, forKey: "ProductLayoutMode")
        }
    }
    
    /// 可販售的商品（商品未下架 + 所屬類別存在且未停用）
    var activeProducts: [ProductModel] {
        products.filter { $0.isAvailableForSale(in: categories) }
    }

    /// 啟用中的類別（POS 的區塊順序；View 也用這個，不再各自過濾 event.categories）
    var activeCategories: [CategoryModel] {
        categories.active
    }

    // MARK: - 商品狀態邏輯

    /// 檢查是否有任何可用商品（用於判斷是否顯示空狀態）
    var hasAnyProducts: Bool {
        !activeProducts.isEmpty
    }

    /// 是否應該顯示空狀態（下架商品不顯示在收銀頁，只看啟用商品）
    var shouldShowEmptyState: Bool {
        return !hasAnyProducts
    }

    // MARK: - 折扣

    /// 百分比折扣選項，升冪排列（§6.4）
    var percentageDiscounts: [DiscountModel] {
        event.discounts.filter { $0.type == .percentage }.sorted { $0.value < $1.value }
    }

    /// 定額折扣選項，升冪排列
    var amountDiscounts: [DiscountModel] {
        event.discounts.filter { $0.type == .amount }.sorted { $0.value < $1.value }
    }

    private func selected(_ type: DiscountType) -> DiscountModel? {
        guard let id = selectedDiscountIds[type] else { return nil }
        return event.discounts.first { $0.id == id && $0.type == type }
    }

    var selectedPercentage: DiscountModel? { selected(.percentage) }
    var selectedAmount: DiscountModel? { selected(.amount) }

    /// 已選的折扣，**百分比在前、定額在後** —— 與 `DiscountCalculator` 的套用順序一致
    var selectedDiscounts: [DiscountModel] {
        [selectedPercentage, selectedAmount].compactMap { $0 }
    }

    /// 點選折扣 chip：同一區再點一次等於取消
    func toggleDiscount(_ discount: DiscountModel) {
        if selectedDiscountIds[discount.type] == discount.id {
            selectedDiscountIds[discount.type] = nil
        } else {
            selectedDiscountIds[discount.type] = discount.id
        }
    }

    func isSelected(_ discount: DiscountModel) -> Bool {
        selectedDiscountIds[discount.type] == discount.id
    }

    /// 折扣總折抵金額（即時顯示用）
    func discountAmount() -> Decimal {
        DiscountCalculator.amount(for: selectedDiscounts, subtotal: subtotal())
    }

    /// 寫進流水帳的折扣快照（含實際折抵金額）
    func appliedDiscounts() -> [AppliedDiscount] {
        DiscountCalculator.applied(for: selectedDiscounts, subtotal: subtotal())
    }

    init(dataSource: EventDataSource) {
        self.dataSource = dataSource
        self.event = dataSource.event

        // 从 UserDefaults 讀取布局模式
        if let savedMode = UserDefaults.standard.string(forKey: "ProductLayoutMode"),
           let mode = ProductLayoutMode(rawValue: savedMode) {
            self.layoutMode = mode
        } else {
            self.layoutMode = .list  // 默認為列表模式
        }
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
        expandedCategories = Set(activeCategories.map { $0.id })
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
    
    /// 取得分類下已排序的商品（有庫存在前，無庫存在後；組內依 sortOrder 排序，跟管理商品頁一致）
    func getSortedProductsForCategory(_ categoryId: UUID) -> [ProductModel] {
        let categoryProducts = activeProducts.filter { $0.categoryId == categoryId }

        // 將商品分為有庫存和無庫存兩組
        let inStockProducts = categoryProducts.filter { !isOutOfStock($0) }
        let outOfStockProducts = categoryProducts.filter { isOutOfStock($0) }

        // 各組內部依 sortOrder 排序，然後合併（有庫存在前）
        let sortedInStock = inStockProducts.sorted { $0.sortOrder < $1.sortOrder }
        let sortedOutOfStock = outOfStockProducts.sorted { $0.sortOrder < $1.sortOrder }

        return sortedInStock + sortedOutOfStock
    }
    
    /// 從共用資料源重新取一份快照（跨頁回來、結帳完成時呼叫）
    func loadProducts() {
        dataSource.reload()
        event = dataSource.event
        categories = dataSource.categories
        products = dataSource.products

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
        selectedDiscountIds.removeAll()
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
        DiscountCalculator.total(subtotal: subtotal(), discounts: selectedDiscounts)
    }

    /// 檢查定額折扣是否超過「套用百分比之後」的金額。
    ///
    /// 比的是折後金額而不是原始小計 —— 小計 200 選 9 折（剩 180）再選 −200 時，
    /// 實際只能折 180，這時就該提示。
    var isDiscountExceedsLimit: Bool {
        guard let amountDiscount = selectedAmount else { return false }
        let afterPercentage = DiscountCalculator.total(
            subtotal: subtotal(),
            discounts: selectedDiscounts.filter { $0.type == .percentage }
        )
        return DiscountCalculator.exceedsSubtotal(amountDiscount, subtotal: afterPercentage)
    }

    /// 折扣超過上限的提示訊息
    var discountWarningMessage: String? {
        guard isDiscountExceedsLimit else { return nil }
        // 折扣不可超過商品金額，已自動調整
        return String.localized("productDetailDiscountExceed")
    }

    /// 取得類別名稱（從 categories 現查，不再依賴已刪除的 `Product.categoryName` 冗餘欄位）
    private func categoryName(for categoryId: UUID) -> String {
        // 未分類
        categories.first { $0.id == categoryId }?.name ?? String.localized("inventoryUncategorized")
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
                category: categoryName(for: product.categoryId),
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
