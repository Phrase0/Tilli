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
    var unitPrice: Decimal = 0

    init(productId: UUID, name: String, category: String, categoryId: UUID) {
        self.productId = productId
        self.name = name
        self.category = category
        self.categoryId = categoryId
    }

    func addSale(quantity: Int, unitPrice: Decimal, discount: Int, actualTotal: Decimal) {
        self.totalQuantity += quantity
        self.unitPrice = unitPrice // 假設同商品單價一致
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