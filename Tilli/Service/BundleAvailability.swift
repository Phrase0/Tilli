//
//  BundleAvailability.swift
//  Tilli
//
//  套餐可賣份數與購物車庫存佔用（單點與套餐雙向佔用）。純函式，無副作用。
//

import Foundation

enum BundleUnavailableReason: Error, Equatable {
    case bundleDisabled
    case memberMissing
    case memberUnavailable(productName: String)     // 商品下架或類別停用／不存在
    case memberOutOfStock(productName: String)
}

extension BundleUnavailableReason {
    /// 不可賣原因的顯示文字（收銀頁加入失敗、套餐卡片、管理頁 ⚠️ 共用，唯一一份）
    var displayText: String {
        switch self {
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
}

/// 組合（chooseAny）湊不成一組的警告：可賣候選的庫存合計 < N（管理頁 ⚠️）
struct ComboWarning: Equatable {
    let availableStock: Int
    let required: Int

    var displayText: String {
        // 可湊組的商品庫存不足 %lld 個
        String.localized("bundleComboStockWarning \(required)")
    }
}

enum InvalidBundleReason: Equatable {
    case deleted, disabled, priceChanged, membersChanged
    case unavailable(BundleUnavailableReason)
    case insufficientStock
}

struct InvalidBundleLine: Equatable {
    let bundleId: UUID
    let name: String           // 用 nameAtAdd，套餐已刪除也能顯示
    let reason: InvalidBundleReason
}

enum InvalidProductReason: Equatable {
    case deleted
    case unavailable                          // 商品下架或類別停用／不存在
    case insufficientStock(remaining: Int)    // remaining = 扣掉留下的套餐行後還能單點的數量
}

struct InvalidProductLine: Equatable {
    let productId: UUID
    let name: String
    let reason: InvalidProductReason
}

enum BundleAvailability {

    /// 可再加入的份數；不可賣時回傳原因。`cart` 用來扣掉已佔用的庫存。
    static func check(
        _ bundle: BundleModel,
        products: [UUID: ProductModel],
        categories: [CategoryModel],
        cart: Cart
    ) -> Result<Int, BundleUnavailableReason> {
        if bundle.isDisabled { return .failure(.bundleDisabled) }
        if let reason = memberProblem(of: bundle, products: products, categories: categories) {
            return .failure(reason)
        }

        var portions = Int.max
        for id in bundle.productIds {
            guard let product = products[id] else { return .failure(.memberMissing) }
            let left = product.stock - cart.reservedQuantity(of: id)
            if left <= 0 { return .failure(.memberOutOfStock(productName: product.name)) }
            portions = min(portions, left)
        }
        // 沒有成員的套餐沒有可賣內容
        guard portions != Int.max else { return .failure(.memberMissing) }
        return .success(portions)
    }

    /// 收銀頁要不要列出這個套餐：**下架就藏、缺貨就灰**。
    /// 套餐下架、成員不存在／下架／類別停用 → 不列（攤商決定現在不賣，與下架單品一致）；
    /// 只是缺貨（含被購物車佔用）→ 照列，由 `check` 給原因讓卡片灰掉。
    static func isListedOnPOS(
        _ bundle: BundleModel,
        products: [UUID: ProductModel],
        categories: [CategoryModel]
    ) -> Bool {
        !bundle.isDisabled
            && !bundle.productIds.isEmpty
            && memberProblem(of: bundle, products: products, categories: categories) == nil
    }

    /// 組合的管理頁警告（下架候選只是不計入，組合本身不失效）。
    /// 只有「可賣候選的庫存合計 < N」才警告（含沒有任何可賣候選）；不看購物車。
    static func comboWarning(
        _ combo: BundleModel,
        products: [UUID: ProductModel],
        categories: [CategoryModel]
    ) -> ComboWarning? {
        guard case .chooseAny(let count) = combo.mode else { return nil }
        let available = Set(combo.productIds).reduce(0) { sum, id in
            guard let product = products[id],
                  product.saleAvailability(in: categories) == .available else { return sum }
            return sum + max(0, product.stock)
        }
        return available < count ? ComboWarning(availableStock: available, required: count) : nil
    }

    /// 單點商品還能再加幾個（stock − reservedQuantity）
    static func remainingStock(of product: ProductModel, cart: Cart) -> Int {
        max(0, product.stock - cart.reservedQuantity(of: product.id))
    }

    /// 回到收銀頁時重新驗證購物車裡的套餐行
    static func invalidLines(
        in cart: Cart,
        bundles: [UUID: BundleModel],
        products: [UUID: ProductModel],
        categories: [CategoryModel]
    ) -> [InvalidBundleLine] {
        var result: [InvalidBundleLine] = []
        for (bundleId, line) in cart.bundleLines.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            func invalid(_ reason: InvalidBundleReason) {
                result.append(InvalidBundleLine(bundleId: bundleId, name: line.nameAtAdd, reason: reason))
            }
            guard let bundle = bundles[bundleId] else { invalid(.deleted); continue }
            if bundle.isDisabled { invalid(.disabled); continue }
            if bundle.price != line.priceAtAdd { invalid(.priceChanged); continue }
            if bundle.productIds != line.productIdsAtAdd { invalid(.membersChanged); continue }
            if let reason = memberProblem(of: bundle, products: products, categories: categories) {
                invalid(.unavailable(reason)); continue
            }
            let oversold = bundle.productIds.contains { id in
                guard let product = products[id] else { return false }
                return cart.reservedQuantity(of: id) > product.stock
            }
            if oversold { invalid(.insufficientStock) }
        }
        return result
    }

    /// 回到收銀頁時重新驗證購物車裡的單點商品。
    /// 庫存只扣「會留下的」套餐行（`removingBundleLines` 是即將移除的失效套餐行）；
    /// `previousNames` 提供已刪除商品的名稱（購物車只存 id）。
    static func invalidProductLines(
        in cart: Cart,
        removingBundleLines: Set<UUID>,
        products: [UUID: ProductModel],
        categories: [CategoryModel],
        previousNames: [UUID: String] = [:]
    ) -> [InvalidProductLine] {
        var keptCart = cart
        keptCart.productQuantities = [:]
        keptCart.bundleLines = cart.bundleLines.filter { !removingBundleLines.contains($0.key) }

        var result: [InvalidProductLine] = []
        for (productId, quantity) in cart.productQuantities where quantity > 0 {
            guard let product = products[productId] else {
                result.append(InvalidProductLine(productId: productId, name: previousNames[productId] ?? "", reason: .deleted))
                continue
            }
            if product.saleAvailability(in: categories) != .available {
                result.append(InvalidProductLine(productId: productId, name: product.name, reason: .unavailable))
                continue
            }
            let remaining = remainingStock(of: product, cart: keptCart)
            if quantity > remaining {
                result.append(InvalidProductLine(productId: productId, name: product.name, reason: .insufficientStock(remaining: remaining)))
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    /// 成員不存在或不可賣（商品下架、類別停用／不存在）。不用 isAvailableForSale（缺類別會 assertionFailure）。
    private static func memberProblem(
        of bundle: BundleModel,
        products: [UUID: ProductModel],
        categories: [CategoryModel]
    ) -> BundleUnavailableReason? {
        for id in bundle.productIds {
            guard let product = products[id] else { return .memberMissing }
            if product.saleAvailability(in: categories) != .available {
                return .memberUnavailable(productName: product.name)
            }
        }
        return nil
    }
}
