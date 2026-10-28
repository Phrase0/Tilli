//
//  ComboApplier.swift
//  Tilli
//
//  組合（任選 N 個固定價）的自動套用：純函式，無狀態。
//  見 docs/superpowers/specs/2026-10-27-bundles-design.md §5.3。
//

import Foundation

/// 一個組合在購物車上的套用結果。
struct ComboApplication: Equatable {
    let bundleId: UUID
    let name: String
    let groupCount: Int
    let coveredQuantities: [UUID: Int]   // productId → 被此組合涵蓋的數量
    let deduction: Decimal               // Σ(每組原價合計 − 組合價)
}

enum ComboApplier {

    /// 只看 cart.productQuantities（套餐成員不計入）；排除 cancelledComboIds、isDisabled、非 chooseAny 的 bundle；
    /// 不可販售的候選不計入。回傳順序 = 套用順序。
    ///
    /// 套用順序：每件平均價（price ÷ N）低者先；同分 N 大者先；再以 id.uuidString 升冪。
    /// 單位順序：單價高到低；同價以 productId.uuidString 升冪。每滿 N 個成一組，不足 N 不套用。
    static func apply(
        cart: Cart,
        combos: [BundleModel],
        products: [UUID: ProductModel],
        categories: [CategoryModel]
    ) -> [ComboApplication] {
        let eligible = combos.compactMap { combo -> (combo: BundleModel, count: Int)? in
            guard !combo.isDisabled,
                  !cart.cancelledComboIds.contains(combo.id),
                  case .chooseAny(let count) = combo.mode,
                  count > 0 else { return nil }
            return (combo, count)
        }

        let ordered = eligible.sorted { lhs, rhs in
            // price/N 比較改用交叉相乘，避免除法精度問題
            let left = MoneyHelper.multiply(lhs.combo.price, Decimal(rhs.count))
            let right = MoneyHelper.multiply(rhs.combo.price, Decimal(lhs.count))
            if left != right { return left < right }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.combo.id.uuidString < rhs.combo.id.uuidString
        }

        var remaining = cart.productQuantities
        var results: [ComboApplication] = []

        for (combo, count) in ordered {
            var seen = Set<UUID>()
            let candidates = combo.productIds.compactMap { id -> ProductModel? in
                guard seen.insert(id).inserted,
                      (remaining[id] ?? 0) > 0,
                      let product = products[id],
                      product.saleAvailability(in: categories) == .available else { return nil }
                return product
            }.sorted { lhs, rhs in
                if lhs.price != rhs.price { return lhs.price > rhs.price }
                return lhs.id.uuidString < rhs.id.uuidString
            }

            let available = candidates.reduce(0) { $0 + (remaining[$1.id] ?? 0) }
            let groups = available / count
            guard groups > 0 else { continue }

            var toTake = groups * count
            var covered: [UUID: Int] = [:]
            var originalTotal: Decimal = 0
            for product in candidates where toTake > 0 {
                let take = min(remaining[product.id] ?? 0, toTake)
                guard take > 0 else { continue }
                covered[product.id] = take
                remaining[product.id, default: 0] -= take
                toTake -= take
                originalTotal = MoneyHelper.add(originalTotal, MoneyHelper.multiply(product.price, Decimal(take)))
            }

            let comboTotal = MoneyHelper.multiply(combo.price, Decimal(groups))
            results.append(ComboApplication(
                bundleId: combo.id,
                name: combo.name,
                groupCount: groups,
                coveredQuantities: covered,
                deduction: MoneyHelper.subtract(originalTotal, comboTotal)
            ))
        }
        return results
    }
}
