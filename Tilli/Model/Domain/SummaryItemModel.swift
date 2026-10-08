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
    var timestamp: Date             // 交易發生時間

    /// 快照：結帳時分攤到這一項的折扣（套餐差額 + 整筆折扣），由 `RevenueAllocator` 寫入。
    /// 報表直接加總，不再重算（FEATURE_PLAN_V1.md §7）。
    var allocatedDiscount: Decimal = 0
    /// 來自哪個組合／套餐（第 5 批起才會有值）
    var bundleId: UUID? = nil
    /// 快照：組合名稱
    var bundleName: String? = nil

    /// 原價小計（折扣前）= 單價 × 數量。即 §7.2 的 `originalSubtotal`。
    var total: Decimal {
        return MoneyHelper.multiply(price, Decimal(quantity))
    }

    /// 實際營收 = 原價小計 − 分攤折扣。
    /// 由兩個快照推導，不另外存 —— 存了就可能跟另外兩個對不起來。
    var actualRevenue: Decimal {
        MoneyHelper.subtract(total, allocatedDiscount)
    }
}

// MARK: - Codable

extension SummaryItemModel {
    private enum CodingKeys: String, CodingKey {
        case id, productId, name, price, categoryId, category, quantity, timestamp
        case allocatedDiscount, bundleId, bundleName
    }

    /// 第 4 批之前寫入的 itemsData 沒有 `allocatedDiscount`，解碼成 0 而不是失敗
    /// （合成的 Decodable 不會套用屬性預設值，缺 key 會整筆交易解不出來）。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        productId = try c.decode(UUID.self, forKey: .productId)
        name = try c.decode(String.self, forKey: .name)
        price = try c.decode(Decimal.self, forKey: .price)
        categoryId = try c.decode(UUID.self, forKey: .categoryId)
        category = try c.decode(String.self, forKey: .category)
        quantity = try c.decode(Int.self, forKey: .quantity)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        allocatedDiscount = try c.decodeIfPresent(Decimal.self, forKey: .allocatedDiscount) ?? 0
        bundleId = try c.decodeIfPresent(UUID.self, forKey: .bundleId)
        bundleName = try c.decodeIfPresent(String.self, forKey: .bundleName)
    }
}

extension Array where Element == SummaryItemModel {
    /// 小計（折扣前，所有項目的 total 相加）
    var subtotal: Decimal {
        reduce(Decimal(0)) { MoneyHelper.add($0, $1.total) }
    }
}
