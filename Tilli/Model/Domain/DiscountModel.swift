//
//  DiscountModel.swift
//  Tilli
//
//  Created by Claude on 2025/12/26.
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

    /// 顯示文字，例如 "5%" 或 "-5元"
    func displayText(currency: String = "") -> String {
        switch type {
        case .percentage:
            return "\(value)%"
        case .amount:
            let suffix = Self.currencySuffix(for: currency)
            return "-\(value)\(suffix)"
        }
    }

    /// 根據幣別取得單位後綴
    private static func currencySuffix(for currencyCode: String) -> String {
        switch currencyCode {
        case "TWD": return "元"
        case "JPY": return "円"
        case "EUR": return "€"
        case "GBP": return "£"
        case "USD": return "$"
        default: return "元"
        }
    }
}
