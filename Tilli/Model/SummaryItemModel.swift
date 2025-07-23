//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/13.
//
import SwiftUI

struct SummaryItemModel: Identifiable, Codable {
    let id = UUID()
    let productId: UUID              // 對應的 Product ID（為了避免資料冗長，僅存 ID）
    let name: String                 // 快照：交易當下商品名稱（避免名稱變動）
    let price: Double                // 快照：單價
    let quantity: Int
    let discount: Int               // 0~100 百分比折扣
    let timestamp: Date             // 交易發生時間

    var total: Double {
        let discountedPrice = price * (1 - Double(discount) / 100)
        return (discountedPrice * Double(quantity)).rounded()
    }
}

