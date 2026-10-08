//
//  RevenueAllocator.swift
//  Tilli
//
//  Created by Peiyun on 2026/10/8.
//
//  結帳當下把套餐差額與整筆折扣攤提到每個項目，取代報表端重複 3 次的攤提。
//  見 FEATURE_PLAN_V1.md §2.4、§7.3（解 A6、B1、B2）。
//
//  ⭐ 保證（RevenueAllocatorTests 用隨機輸入鎖住）：
//    - Σ allocatedDiscount == Σ 套餐差額 + Σ 折扣 amount（clamp 到可攤金額內）
//      → 搭配 DiscountCalculator 的不變式，Σ actualRevenue == totalAmount
//    - 每一項 0 ≤ allocatedDiscount ≤ 原價小計（不會出現負營收）
//

import Foundation

enum RevenueAllocator {

    /// 一個組合／套餐帶來的差額（原價合計 − 組合價），只攤給 `bundleId` 相同的項目。
    struct BundleDeduction: Hashable {
        let bundleId: UUID
        let amount: Decimal
    }

    /// 依 §7.3 的順序攤提，回傳寫好 `allocatedDiscount` 的項目（順序不變）。
    ///
    /// ① 原價小計 → ② 套餐差額（只攤給成員）→ ③④ 整筆折扣依序攤給所有項目
    /// 每一步都按「前一步之後」的剩餘金額比例分配。
    ///
    /// - Parameters:
    ///   - discounts: 已經過 `DiscountCalculator.sanitized` 的快照，依陣列順序攤（百分比在前）
    ///   - currency: 決定捨入單位（TWD 到元、USD 到分）
    static func allocate(
        _ items: [SummaryItemModel],
        bundles: [BundleDeduction] = [],
        discounts: [AppliedDiscount],
        currency: String
    ) -> [SummaryItemModel] {
        let scale = (Currency(rawValue: currency) ?? .twd).decimalPlaces
        var allocated = [Decimal](repeating: 0, count: items.count)
        let originals = items.map { max($0.total, 0) }

        func distribute(_ amount: Decimal, among indices: [Int]) {
            let remaining = indices.map { MoneyHelper.subtract(originals[$0], allocated[$0]) }
            let shares = split(amount, by: remaining, scale: scale)
            for (index, share) in zip(indices, shares) {
                allocated[index] = MoneyHelper.add(allocated[index], share)
            }
        }

        // ② 套餐差額
        for bundle in bundles {
            let members = items.indices.filter { items[$0].bundleId == bundle.bundleId }
            distribute(bundle.amount, among: members)
        }

        // ③ 百分比 → ④ 定額（順序由 discounts 陣列決定）
        for discount in discounts {
            distribute(discount.amount, among: Array(items.indices))
        }

        return zip(items, allocated).map { item, discount in
            var item = item
            item.allocatedDiscount = discount
            return item
        }
    }

    /// 把 `amount` 按 `weights` 比例拆開，每份不超過自己的 weight，總和剛好等於 `amount`
    /// （`amount` 超過 Σ weights 時先 clamp）。
    ///
    /// ⑤ 捨入：每份先**捨去**到幣別最小單位，餘額再依序給「剩餘空間最大」的項目。
    /// 不用「最後一項吃掉」—— 最後一項若是贈品或金額很小，會被吃成負數。
    private static func split(_ amount: Decimal, by weights: [Decimal], scale: Int) -> [Decimal] {
        let pool = MoneyHelper.sum(weights)
        let target = min(max(amount, 0), pool)
        guard target > 0 else { return weights.map { _ in 0 } }
        guard target < pool else { return weights }   // 全額折抵：每份就是它自己

        var shares = weights.map { weight in
            MoneyHelper.roundDown(
                MoneyHelper.divide(MoneyHelper.multiply(target, weight), pool),
                scale: scale
            )
        }

        var leftover = MoneyHelper.subtract(target, MoneyHelper.sum(shares))
        // 剩餘空間大的優先；同額時取前面的，結果才穩定
        let order = weights.indices.sorted { lhs, rhs in
            let l = MoneyHelper.subtract(weights[lhs], shares[lhs])
            let r = MoneyHelper.subtract(weights[rhs], shares[rhs])
            return l != r ? l > r : lhs < rhs
        }
        for index in order where leftover > 0 {
            let room = MoneyHelper.subtract(weights[index], shares[index])
            let take = min(leftover, room)
            shares[index] = MoneyHelper.add(shares[index], take)
            leftover = MoneyHelper.subtract(leftover, take)
        }
        return shares
    }
}
