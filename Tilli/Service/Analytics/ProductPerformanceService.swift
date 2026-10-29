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
    /// 同一個商品可能有多種成交單價（改價、組合、套餐），所以顯示平均值，
    /// 不取任何一筆的單價。`originalRevenue` 是用每筆快照單價逐筆累加的。
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