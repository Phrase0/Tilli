//
//  BundleValidator.swift
//  Tilli
//
//  組合與套餐的驗證規則（純函式、不碰持久層）。
//  見 docs/superpowers/specs/2026-10-27-bundles-design.md §4.2。
//

import Foundation

enum BundleValidationError: Equatable {
    case emptyName, duplicateName, nonPositivePrice
    case tooFewMembers            // fixed 成員 < 2
    case countTooSmall            // chooseAny N < 2
    case noCandidates             // chooseAny 候選 < 1
    case unknownProduct           // productIds 有不存在於 products 的 id
    case priceAboveLimit(limit: Decimal)
}

enum BundleValidator {
    /// 套餐：Σ 成員單價；組合：N × 候選最低單價。有不存在的商品（或組合沒有候選）回傳 nil。
    static func priceLimit(for bundle: BundleModel, products: [UUID: ProductModel]) -> Decimal? {
        var prices: [Decimal] = []
        for id in bundle.productIds {
            guard let product = products[id] else { return nil }
            prices.append(product.price)
        }
        switch bundle.mode {
        case .fixed:
            return MoneyHelper.sum(prices)
        case .chooseAny(let count):
            guard let cheapest = prices.min() else { return nil }
            return MoneyHelper.multiply(Decimal(count), cheapest)
        }
    }

    /// 空陣列 = 可儲存。`existing` 含自己時以 id 排除；名稱比對前 trim 空白。
    static func validate(_ bundle: BundleModel, existing: [BundleModel], products: [UUID: ProductModel]) -> [BundleValidationError] {
        var errors: [BundleValidationError] = []

        let name = trimmed(bundle.name)
        if name.isEmpty {
            errors.append(.emptyName)
        } else if existing.contains(where: { $0.id != bundle.id && trimmed($0.name) == name }) {
            errors.append(.duplicateName)
        }

        if bundle.price <= 0 { errors.append(.nonPositivePrice) }

        switch bundle.mode {
        case .fixed:
            if bundle.productIds.count < 2 { errors.append(.tooFewMembers) }
        case .chooseAny(let count):
            if count < 2 { errors.append(.countTooSmall) }
            if bundle.productIds.isEmpty { errors.append(.noCandidates) }
        }

        if bundle.productIds.contains(where: { products[$0] == nil }) {
            errors.append(.unknownProduct)
        } else if let limit = priceLimit(for: bundle, products: products), bundle.price > limit {
            errors.append(.priceAboveLimit(limit: limit))
        }
        return errors
    }

    /// price == limit（可存但提醒「沒有優惠」）
    static func hasNoDiscount(_ bundle: BundleModel, products: [UUID: ProductModel]) -> Bool {
        guard let limit = priceLimit(for: bundle, products: products) else { return false }
        return bundle.price == limit
    }

    /// 引用到此商品的套餐／組合（刪除守衛用）
    static func bundles(referencing productId: UUID, in bundles: [BundleModel]) -> [BundleModel] {
        bundles.filter { $0.productIds.contains(productId) }
    }

    /// 若把 productId 改成 newPrice，會違反價格條件的套餐／組合（改價守衛用）
    static func bundlesViolated(byPrice newPrice: Decimal, of productId: UUID, bundles: [BundleModel], products: [UUID: ProductModel]) -> [BundleModel] {
        guard var changed = products[productId] else { return [] }
        changed.price = newPrice
        var updated = products
        updated[productId] = changed
        return Self.bundles(referencing: productId, in: bundles).filter { bundle in
            guard let limit = priceLimit(for: bundle, products: updated) else { return false }
            return bundle.price > limit
        }
    }

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
