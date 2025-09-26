//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/13.
//
import SwiftUI
import Foundation

struct SummaryItemModel: Identifiable, Codable, Hashable {
    var id = UUID()
    var productId: UUID              // 對應的 Product ID（為了避免資料冗長，僅存 ID）
    var name: String                 // 快照：交易當下商品名稱（避免名稱變動）
    var price: Decimal               // 快照：單價
    var categoryId: UUID             // 分類ID（分析用）
    var category: String             // 顯示用快照名稱
    var quantity: Int
    var discount: Int               // 0~100 百分比折扣
    var timestamp: Date             // 交易發生時間

    var total: Decimal {
        return MoneyHelper.calculateTotal(
            price: price,
            quantity: quantity,
            discountPercentage: discount
        )
    }
}

