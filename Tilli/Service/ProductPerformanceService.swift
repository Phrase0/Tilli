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
    var originalRevenue: Double = 0
    var actualRevenue: Double = 0
    var totalDiscount: Double = 0
    var unitPrice: Double = 0

    init(productId: UUID, name: String, category: String, categoryId: UUID) {
        self.productId = productId
        self.name = name
        self.category = category
        self.categoryId = categoryId
    }

    func addSale(quantity: Int, unitPrice: Double, discount: Int, actualTotal: Double) {
        self.totalQuantity += quantity
        self.unitPrice = unitPrice // 假設同商品單價一致
        let originalTotal = unitPrice * Double(quantity)
        self.originalRevenue += originalTotal
        self.actualRevenue += actualTotal
        self.totalDiscount += Double(discount)
    }
}

class CategorySalesStats {
    let categoryId: UUID
    let name: String
    var totalAmount: Double = 0

    init(categoryId: UUID, name: String) {
        self.categoryId = categoryId
        self.name = name
    }

    func addSale(amount: Double) {
        self.totalAmount += amount
    }
}