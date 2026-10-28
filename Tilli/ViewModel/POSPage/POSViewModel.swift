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
    /// 購物車：單點商品、套餐行、本筆交易已取消的組合（設計 §5.6、§9.1 第 1 點）
    @Published private(set) var cart = Cart()
    /// 回到收銀頁（或按結帳）時發現無法結帳的套餐行；非空時由 View 通知，使用者確定後才清除（§9.1 第 5 點）
    @Published var invalidBundleLines: [InvalidBundleLine] = []
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

    /// 折扣總折抵金額（即時顯示用）。基礎是「小計 − 組合差額」，與 `pricing` 同一份計算
    func discountAmount() -> Decimal {
        MoneyHelper.sum(pricing.discounts.map(\.amount))
    }

    /// 寫進流水帳的折扣快照（含實際折抵金額）
    func appliedDiscounts() -> [AppliedDiscount] {
        pricing.discounts
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

        // 進行中的購物車可能有套餐已被刪除／下架／改價／缺貨（§9.1 第 5 點）
        refreshInvalidBundleLines()
    }
    
    func increaseQuantity(for product: ProductModel) {
        // 檢查是否無庫存
        if isOutOfStock(product) {
            showOutOfStockAlert(for: product.name)
            return
        }
        
        // 剩餘庫存要扣掉套餐行佔用的數量（雙向佔用，§5.6）
        if BundleAvailability.remainingStock(of: product, cart: cart) > 0 {
            cart.productQuantities[product.id, default: 0] += 1
        }
    }
    
    func decreaseQuantity(for product: ProductModel) {
        // 無庫存商品也不能減少數量
        if isOutOfStock(product) {
            return
        }
        
        let current = cart.productQuantities[product.id, default: 0]
        if current > 1 {
            cart.productQuantities[product.id] = current - 1
        } else {
            cart.productQuantities[product.id] = nil
        }
    }
    
    func quantity(for product: ProductModel) -> Int {
        cart.productQuantities[product.id, default: 0]
    }
    
    func clearAllQuantities() {
        cart = Cart()
        selectedDiscountIds.removeAll()
    }

    // MARK: - 套餐與組合

    private var productsById: [UUID: ProductModel] {
        Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var bundlesById: [UUID: BundleModel] {
        Dictionary(event.bundles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 收銀頁顯示的套餐（未停用的 `.fixed`，依建立時間；組合不出現在收銀頁，§5.2）
    var fixedBundles: [BundleModel] {
        event.bundles
            .filter { $0.kind == .fixed && !$0.isDisabled }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// 還能再加幾份；不可賣時回傳原因（已扣掉購物車佔用的庫存）
    func availability(of bundle: BundleModel) -> Result<Int, BundleUnavailableReason> {
        BundleAvailability.check(bundle, products: productsById, categories: categories, cart: cart)
    }

    /// 加一份套餐。不可賣（含份數不足）時只提示原因、不加入。
    func addBundle(_ bundle: BundleModel) {
        switch availability(of: bundle) {
        case .failure(let reason):
            alertMessage = unavailableReasonText(reason)
            showAlert = true
        case .success:
            if var line = cart.bundleLines[bundle.id] {
                line.quantity += 1
                cart.bundleLines[bundle.id] = line
            } else {
                // 快照加入當下的名稱／價格／成員，回到收銀頁時用來偵測套餐被改過
                cart.bundleLines[bundle.id] = BundleCartLine(
                    quantity: 1,
                    nameAtAdd: bundle.name,
                    priceAtAdd: bundle.price,
                    productIdsAtAdd: bundle.productIds
                )
            }
        }
    }

    /// 減一份，到 0 移除該行
    func removeBundle(_ bundleId: UUID) {
        guard var line = cart.bundleLines[bundleId] else { return }
        if line.quantity > 1 {
            line.quantity -= 1
            cart.bundleLines[bundleId] = line
        } else {
            cart.bundleLines[bundleId] = nil
        }
    }

    func bundleQuantity(_ bundleId: UUID) -> Int {
        cart.bundleLines[bundleId]?.quantity ?? 0
    }

    /// 取消／恢復某個組合，只對這一筆交易有效（§5.4）
    func toggleComboCancelled(_ bundleId: UUID) {
        if cart.cancelledComboIds.contains(bundleId) {
            cart.cancelledComboIds.remove(bundleId)
        } else {
            cart.cancelledComboIds.insert(bundleId)
        }
    }

    /// 不可賣原因的顯示文字（加入失敗的 alert、套餐卡片共用）
    func unavailableReasonText(_ reason: BundleUnavailableReason) -> String {
        switch reason {
        case .bundleDisabled:
            // 套餐已下架
            return String.localized("bundleReasonDisabled")
        case .memberMissing:
            // 套餐內有商品已不存在
            return String.localized("bundleReasonMemberMissing")
        case .memberUnavailable(let productName):
            // 「%@」已下架
            return String.localized("bundleReasonUnavailable \(productName)")
        case .memberOutOfStock(let productName):
            // 「%@」缺貨
            return String.localized("bundleReasonOutOfStock \(productName)")
        }
    }

    /// 套餐行無法結帳的原因文字（失效通知用）
    func invalidReasonText(_ reason: InvalidBundleReason) -> String {
        switch reason {
        case .deleted:
            // 套餐已刪除
            return String.localized("bundleReasonDeleted")
        case .disabled:
            // 套餐已下架
            return String.localized("bundleReasonDisabled")
        case .priceChanged:
            // 套餐價格已變更
            return String.localized("bundleReasonPriceChanged")
        case .membersChanged:
            // 套餐內容已變更
            return String.localized("bundleReasonMembersChanged")
        case .unavailable(let reason):
            return unavailableReasonText(reason)
        case .insufficientStock:
            // 庫存不足
            return String.localized("bundleReasonInsufficientStock")
        }
    }

    /// 失效通知的內文：每行「名稱：原因」
    var invalidBundleLinesMessage: String {
        invalidBundleLines
            // %@：%@
            .map { String.localized("posInvalidBundleLine \($0.name) \(invalidReasonText($0.reason))") }
            .joined(separator: "\n")
    }

    /// 本筆交易已取消的組合（訂單摘要以灰色劃線顯示並可「恢復」）；已刪除或已停用的組合不列
    var cancelledCombos: [BundleModel] {
        event.bundles
            .filter { cart.cancelledComboIds.contains($0.id) && $0.kind == .chooseAny && !$0.isDisabled }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// 移除 `invalidBundleLines` 列出的套餐行（使用者在通知上按確定後呼叫），其餘商品保留
    func confirmInvalidBundleLines() {
        for line in invalidBundleLines {
            cart.bundleLines[line.bundleId] = nil
        }
        invalidBundleLines = []
    }

    /// 按結帳前重新驗證套餐行；有失效行就不開結帳（`pricing` 會略過失效行，不能帶著它們結帳）
    func prepareCheckout() -> Bool {
        refreshInvalidBundleLines()
        return invalidBundleLines.isEmpty
    }

    private func refreshInvalidBundleLines() {
        invalidBundleLines = BundleAvailability.invalidLines(
            in: cart,
            bundles: bundlesById,
            products: productsById,
            categories: categories
        )
    }

    /// 購物車的定價明細（小計、組合、折扣、總計）。
    ///
    /// 單點商品只用可販售的商品計價 —— 與原本 `subtotal()` 只看 `activeProducts` 一致；
    /// 套餐行若成員不可販售會被 `invalidBundleLines` 擋下，不會進結帳。
    var pricing: CartPricing {
        CartPricing.price(
            cart: cart,
            products: Dictionary(activeProducts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            bundles: bundlesById,
            categories: categories,
            selectedDiscounts: selectedDiscounts
        )
    }

    /// 計算小計（未套用折扣；套餐以套餐價計）
    func subtotal() -> Decimal {
        pricing.subtotal
    }

    /// 計算總金額（組合差額 → 百分比 → 減額）
    func totalAmount() -> Decimal {
        pricing.total
    }

    /// 檢查定額折扣是否超過「套用百分比之後」的金額。
    ///
    /// 比的是折後金額而不是原始小計 —— 小計 200 選 9 折（剩 180）再選 −200 時，
    /// 實際只能折 180，這時就該提示。
    var isDiscountExceedsLimit: Bool {
        guard let amountDiscount = selectedAmount else { return false }
        let current = pricing
        // 整筆折扣的基礎 = 小計 − 組合差額（與 CartPricing 一致）
        let discountBase = MoneyHelper.subtract(current.subtotal, MoneyHelper.sum(current.combos.map(\.deduction)))
        let afterPercentage = DiscountCalculator.total(
            subtotal: discountBase,
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

    /// 取得類別名稱（從 categories 現查，不再依賴已刪除的 `Product.categoryName` 冗餘欄位）；
    /// 結帳時交給 `pricing.summaryItems(categoryName:timestamp:)`
    func categoryName(for categoryId: UUID) -> String {
        // 未分類
        categories.first { $0.id == categoryId }?.name ?? String.localized("inventoryUncategorized")
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
