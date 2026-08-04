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
    let unitPrice: Decimal
    let originalPrice: Decimal
    let discount: Decimal
    let actualRevenue: Decimal
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