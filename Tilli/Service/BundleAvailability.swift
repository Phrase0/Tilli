//
//  BundleAvailability.swift
//  Tilli
//
//  套餐可賣份數與購物車庫存佔用（雙向佔用，設計 §5.6）。純函式，無副作用。
//

import Foundation

enum BundleUnavailableReason: Error, Equatable {
    case bundleDisabled
    case memberMissing
    case memberUnavailable(productName: String)     // 商品下架或類別停用／不存在
    case memberOutOfStock(productName: String)
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

    /// 單點商品還能再加幾個（stock − reservedQuantity）
    static func remainingStock(of product: ProductModel, cart: Cart) -> Int {
        max(0, product.stock - cart.reservedQuantity(of: product.id))
    }

    /// 回到收銀頁時重新驗證（設計 §9.1 第 5 點）
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
