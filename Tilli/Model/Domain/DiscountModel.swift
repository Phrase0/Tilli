//
//  DiscountModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/12/26.
//

import Foundation

// MARK: - DiscountType

enum DiscountType: String, Codable, CaseIterable {
    case percentage    // 百分比
    case amount        // 金額
}

// MARK: - DiscountModel

struct DiscountModel: Identifiable, Codable, Hashable {
    var id = UUID()
    var type: DiscountType
    var value: Decimal      // 5 = 5% 或 5元

    /// 顯示文字，例如 "5%" 或 "NT$5"
    ///
    /// 實作在 `DiscountCalculator` —— 全專案的折扣 switch 只准出現在那一處。
    func displayText(currency: String = "") -> String {
        DiscountCalculator.displayText(type: type, value: value, currency: currency)
    }
}
