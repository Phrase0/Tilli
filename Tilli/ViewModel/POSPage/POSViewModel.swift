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

/// 收銀頁與訂單摘要的一個可增減品項：單點商品或套餐
enum CartItemID: Hashable {
    case product(UUID)
    case bundle(UUID)
}

@MainActor
class POSViewModel: ObservableObject {

    /// 場次工作區的共用資料源
    private let dataSource: EventDataSource

    /// ⭐ event / categories / products 一律一起從 dataSource 取同一份快照，
    /// 商品與類別永遠是同一個時間點的資料
    @Published private(set) var event: EventModel {
        didSet { bundlesById = Self.index(event.bundles) }
    }
    @Published private(set) var categories: [CategoryModel] = []
    @Published private(set) var products: [ProductModel] = [] {
        didSet { productsById = Self.index(products) }
    }
    /// 依 id 查商品／套餐；隨 `products`／`event` 更新，不在每次存取時重建
    private(set) var productsById: [UUID: ProductModel] = [:]
    private(set) var bundlesById: [UUID: BundleModel] = [:]
    /// 購物車：單點商品、套餐行、本筆交易已取消的組合
    @Published private(set) var cart = Cart() {
        didSet {
            // 購物車空了＝這位客人結束；取消組合只對這一筆有效，不可帶到下一位客人
            if cart.isEmpty && !cart.cancelledComboIds.isEmpty {
                cart.cancelledComboIds = []
            }
        }
    }
    /// 回到收銀頁（或按結帳）時發現無法結帳的套餐行；非空時由 View 通知，使用者確定後才清除
    @Published var invalidBundleLines: [InvalidBundleLine] = []
    /// 同上，單點商品（下架、刪除、超過目前庫存）；與套餐行同一個通知
    @Published var invalidProductLines: [InvalidProductLine] = []
    /// 折扣：每個型別各自單選，可同時一個百分比 + 一個定額。
    ///
    /// 用型別當 key 而不是兩個獨立欄位 —— 之後多一種折扣型別時，
    /// 這裡與 `toggleDiscount` / `isSelected` 都不用改。
    @Published private(set) var selectedDiscountIds: [DiscountType: UUID] = [:]
    /// 目前展開成「− 數量 ＋」的品項；同一時間最多一個，其餘收合成數量圓形
    @Published private(set) var expandedItem: CartItemID?

    // Alert 相關狀態（僅無庫存提醒使用）
    @Published var showAlert = false
    @Published var alertMessage = ""

    // Product Detail 相關狀態

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

    /// 啟用中的類別（POS 的區塊順序；View 也用這個，不各自過濾 event.categories）
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

    /// 百分比折扣選項，升冪排列
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
        self.bundlesById = Self.index(dataSource.event.bundles)

        // 从 UserDefaults 讀取布局模式
        if let savedMode = UserDefaults.standard.string(forKey: "ProductLayoutMode"),
           let mode = ProductLayoutMode(rawValue: savedMode) {
            self.layoutMode = mode
        } else {
            self.layoutMode = .list  // 默認為列表模式
        }
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
        let previousNames = Dictionary(products.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        dataSource.reload()
        event = dataSource.event
        categories = dataSource.categories
        products = dataSource.products

        // 進行中的購物車可能有套餐或商品已被刪除／下架／改價／庫存變少
        refreshInvalidLines(previousNames: previousNames)
    }
    
    func increaseQuantity(for product: ProductModel) {
        // 檢查是否無庫存
        if isOutOfStock(product) {
            showOutOfStockAlert(for: product.name)
            return
        }
        
        // 剩餘庫存要扣掉套餐行佔用的數量（雙向佔用）
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
        expandedItem = nil
    }

    var isCartEmpty: Bool {
        cart.isEmpty
    }

    // MARK: - 增減元件（商品與套餐共用）

    func quantity(of item: CartItemID) -> Int {
        switch item {
        case .product(let id): return cart.productQuantities[id, default: 0]
        case .bundle(let id): return bundleQuantity(id)
        }
    }

    /// 還能不能再加一個：商品要可販售且扣掉購物車佔用後還有庫存；套餐要可賣
    func canIncrement(_ item: CartItemID) -> Bool {
        switch item {
        case .product(let id):
            guard let product = productsById[id], product.saleAvailability(in: categories) == .available else { return false }
            return BundleAvailability.remainingStock(of: product, cart: cart) > 0
        case .bundle(let id):
            guard let bundle = bundlesById[id], case .success = availability(of: bundle) else { return false }
            return true
        }
    }

    /// 加一個；`expand` 為 true 時讓這一項展開（訂單摘要不需要展開狀態）
    func increment(_ item: CartItemID, expand: Bool = true) {
        switch item {
        case .product(let id):
            guard let product = productsById[id] else { return }
            increaseQuantity(for: product)
        case .bundle(let id):
            guard let bundle = bundlesById[id] else { return }
            addBundle(bundle)
        }
        if expand { expandedItem = item }
    }

    /// 減一個；減到 0 時收合
    func decrement(_ item: CartItemID) {
        switch item {
        case .product(let id):
            guard let product = productsById[id] else { return }
            decreaseQuantity(for: product)
        case .bundle(let id):
            removeBundle(id)
        }
        if quantity(of: item) == 0 && expandedItem == item {
            expandedItem = nil
        }
    }

    func expand(_ item: CartItemID) {
        expandedItem = item
    }

    /// 捲動時每一幀都會呼叫；沒有展開時不寫入，避免觸發整頁重繪
    func collapseControls() {
        guard expandedItem != nil else { return }
        expandedItem = nil
    }

    // MARK: - 套餐與組合

    private static func index<T: Identifiable>(_ items: [T]) -> [UUID: T] where T.ID == UUID {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 收銀頁顯示的套餐（`.fixed`，依建立時間；組合不出現在收銀頁）。
    /// 下架類（套餐／成員下架、類別停用）不列；缺貨照列、卡片灰掉（`BundleAvailability.isListedOnPOS`）
    var fixedBundles: [BundleModel] {
        let products = productsById
        return event.bundles
            .filter { $0.kind == .fixed && BundleAvailability.isListedOnPOS($0, products: products, categories: categories) }
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
            alertMessage = reason.displayText
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

    /// 套餐本來就不能賣的原因（不看購物車：只有成員庫存本來就不足時才有）。
    /// 收銀頁用它決定卡片要不要變灰；被購物車用完只讓 ＋ 停用（`canIncrement`），卡片不變
    func soldOutReason(of bundle: BundleModel) -> BundleUnavailableReason? {
        if case .failure(let reason) = BundleAvailability.check(bundle, products: productsById, categories: categories, cart: Cart()) {
            return reason
        }
        return nil
    }

    /// 套餐本來就不能賣時，點卡片提醒原因
    func showUnavailableAlert(for bundle: BundleModel) {
        guard let reason = soldOutReason(of: bundle) else { return }
        alertMessage = reason.displayText
        showAlert = true
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

    /// 取消／恢復某個組合，只對這一筆交易有效
    func toggleComboCancelled(_ bundleId: UUID) {
        if cart.cancelledComboIds.contains(bundleId) {
            cart.cancelledComboIds.remove(bundleId)
        } else {
            cart.cancelledComboIds.insert(bundleId)
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
            return reason.displayText
        case .insufficientStock:
            // 庫存不足
            return String.localized("bundleReasonInsufficientStock")
        }
    }

    /// 單點商品無法結帳的原因文字（失效通知用）
    func invalidReasonText(_ reason: InvalidProductReason) -> String {
        switch reason {
        case .deleted:
            // 商品已刪除
            return String.localized("posProductReasonDeleted")
        case .unavailable:
            // 已下架
            return String.localized("bundleMemberDisabledTag")
        case .insufficientStock(let remaining) where remaining == 0:
            // 無庫存
            return String.localized("posOutOfStock")
        case .insufficientStock(let remaining):
            // 庫存只剩 %lld 個
            return String.localized("posProductReasonStockLeft \(remaining)")
        }
    }

    /// 失效通知是否要顯示
    var hasInvalidLines: Bool {
        !invalidBundleLines.isEmpty || !invalidProductLines.isEmpty
    }

    /// 失效通知的內文：每行「名稱：原因」，套餐在前、單點在後
    var invalidLinesMessage: String {
        // %@：%@
        let bundles = invalidBundleLines.map { String.localized("posInvalidCartLine \($0.name) \(invalidReasonText($0.reason))") }
        let singles = invalidProductLines.map { String.localized("posInvalidCartLine \($0.name) \(invalidReasonText($0.reason))") }
        return (bundles + singles).joined(separator: "\n")
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

    /// 使用者在通知上按確定後呼叫：移除失效套餐行；單點商品下架／刪除就移除，
    /// 超過庫存就降到剩餘數量（0 即移除）。其餘商品保留
    func confirmInvalidLines() {
        for line in invalidBundleLines {
            cart.bundleLines[line.bundleId] = nil
        }
        for line in invalidProductLines {
            switch line.reason {
            case .deleted, .unavailable:
                cart.productQuantities[line.productId] = nil
            case .insufficientStock(let remaining):
                cart.productQuantities[line.productId] = remaining > 0 ? remaining : nil
            }
        }
        invalidBundleLines = []
        invalidProductLines = []
    }

    /// 按結帳前重新驗證購物車；有失效行就不開結帳（`pricing` 會略過失效套餐行，不能帶著它們結帳）
    func prepareCheckout() -> Bool {
        refreshInvalidLines(previousNames: [:])
        return !hasInvalidLines
    }

    private func refreshInvalidLines(previousNames: [UUID: String]) {
        let products = productsById
        invalidBundleLines = BundleAvailability.invalidLines(
            in: cart,
            bundles: bundlesById,
            products: products,
            categories: categories
        )
        invalidProductLines = BundleAvailability.invalidProductLines(
            in: cart,
            removingBundleLines: Set(invalidBundleLines.map(\.bundleId)),
            products: products,
            categories: categories,
            previousNames: previousNames
        )
    }

    /// 購物車的定價明細（小計、組合、折扣、總計）。
    ///
    /// 單點商品只用可販售的商品（`activeProducts`）計價；
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
        let afterPercentage = DiscountCalculator.total(
            subtotal: pricing.discountBase,
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

    /// 取得類別名稱（從 categories 現查，商品不另存類別名稱）；
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
