//
//  ProductPerformanceModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/16.
//

import SwiftUI

// MARK: - Data Models
struct ProductPerformanceData: Identifiable {
    let id = UUID()
    let productId: UUID
    var rank: Int
    let name: String
    let category: String
    let salesCount: Int
    let contributionRate: Int
    /// 平均成交單價（原價總額 ÷ 總銷量）
    let averageUnitPrice: Decimal
    let originalPrice: Decimal
    let discount: Decimal
    let actualRevenue: Decimal
}

/// 本期未售出的商品。
///
/// 只需要「是誰」—— 營收、名次這些欄位對它們一律是 0／沒有意義，
/// 給了反而讓收攤時的主表變難讀。見 FEATURE_PLAN_V1.md §5.1。
struct UnsoldProductData: Identifiable {
    let id: UUID              // = productId
    let name: String
    let category: String
    let isDisabled: Bool      // 已下架的商品在 UI 上要標示出來
}

struct CategoryAnalysisData: Identifiable {
    let id = UUID()
    let name: String
    let amount: Decimal
    let percentage: Int
    let color: Color
}

struct SalesInsightsData {
    let hotProductTitle: String
    let hotProductDescription: String
    let discountTitle: String?
    let discountDescription: String?
    let suggestionTitle: String
    let suggestionDescription: String

    init() {
        // 熱銷商品
        self.hotProductTitle = String.localized("insightHotProduct")
        // 暫無資料
        self.hotProductDescription = String.localized("insightNoData")
        self.discountTitle = nil
        self.discountDescription = nil
        // 優化建議
        self.suggestionTitle = String.localized("insightSuggestion")
        // 暫無資料
        self.suggestionDescription = String.localized("insightNoData")
    }

    init(
        hotProductTitle: String,
        hotProductDescription: String,
        discountTitle: String? = nil,
        discountDescription: String? = nil,
        suggestionTitle: String,
        suggestionDescription: String
    ) {
        self.hotProductTitle = hotProductTitle
        self.hotProductDescription = hotProductDescription
        self.discountTitle = discountTitle
        self.discountDescription = discountDescription
        self.suggestionTitle = suggestionTitle
        self.suggestionDescription = suggestionDescription
    }
}