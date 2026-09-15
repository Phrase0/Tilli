//
//  ProductPerformanceService.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/16.
//

import Foundation

// MARK: - Helper Classes for Statistics
class ProductSalesStats {
    let productId: UUID
    let name: String
    let category: String
    let categoryId: UUID
    var totalQuantity: Int = 0
    var originalRevenue: Decimal = 0
    var actualRevenue: Decimal = 0
    var totalDiscount: Decimal = 0

    /// 平均成交單價 = 原價總額 ÷ 總銷量。
    ///
    /// 取代原本的 `unitPrice` —— 它每次 `addSale` 都覆蓋成最後一筆的單價，
    /// 註解直接寫「假設同商品單價一致」。那個假設在組合優惠與套餐（§8）之後
    /// 必然不成立：同一個商品會有多種成交單價。見 FEATURE_PLAN_V1.md §4.2（D5）。
    ///
    /// `originalRevenue` 本來就是用每筆快照單價逐筆累加，總額一直是對的，
    /// 這裡只是換一個不會失真的顯示方式。
    var averageUnitPrice: Decimal {
        totalQuantity > 0
            ? MoneyHelper.divide(originalRevenue, Decimal(totalQuantity))
            : 0
    }

    init(productId: UUID, name: String, category: String, categoryId: UUID) {
        self.productId = productId
        self.name = name
        self.category = category
        self.categoryId = categoryId
    }

    func addSale(quantity: Int, unitPrice: Decimal, actualTotal: Decimal) {
        self.totalQuantity += quantity
        let originalTotal = MoneyHelper.multiply(unitPrice, Decimal(quantity))
        self.originalRevenue = MoneyHelper.add(self.originalRevenue, originalTotal)
        self.actualRevenue = MoneyHelper.add(self.actualRevenue, actualTotal)
        // 折扣總額 = 原價 - 實際價格
        let discountAmount = MoneyHelper.subtract(originalTotal, actualTotal)
        self.totalDiscount = MoneyHelper.add(self.totalDiscount, discountAmount)
    }
}

class CategorySalesStats {
    let categoryId: UUID
    let name: String
    var totalAmount: Decimal = 0

    init(categoryId: UUID, name: String) {
        self.categoryId = categoryId
        self.name = name
    }

    func addSale(amount: Decimal) {
        self.totalAmount = MoneyHelper.add(self.totalAmount, amount)
    }
}