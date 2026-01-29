//
//  DecimalHelper.swift
//  Tilli
//
//  Created for CoreData + Firebase Sync
//  用於 Decimal ↔ Integer（分）轉換，避免 Firestore 浮點精度問題
//

import Foundation

// MARK: - Decimal ↔ Cents 轉換

/// 將 Decimal 轉換為整數（分）
/// - Parameter value: 金額（元）
/// - Returns: 金額（分），例如 100.50 → 10050
func decimalToCents(_ value: Decimal) -> Int {
    return NSDecimalNumber(decimal: value * 100).intValue
}

/// 將整數（分）轉換為 Decimal
/// - Parameter cents: 金額（分）
/// - Returns: 金額（元），例如 10050 → 100.50
func centsToDecimal(_ cents: Int) -> Decimal {
    return Decimal(cents) / 100
}

// MARK: - Optional Decimal 轉換

/// 將可選 Decimal 轉換為可選整數（分）
/// - Parameter value: 金額（元）
/// - Returns: 金額（分），nil 則回傳 nil
func decimalToCentsOptional(_ value: Decimal?) -> Int? {
    guard let value = value else { return nil }
    return decimalToCents(value)
}

/// 將可選整數（分）轉換為可選 Decimal
/// - Parameter cents: 金額（分）
/// - Returns: 金額（元），nil 則回傳 nil
func centsToDecimalOptional(_ cents: Int?) -> Decimal? {
    guard let cents = cents else { return nil }
    return centsToDecimal(cents)
}

// MARK: - Decimal Extension

extension Decimal {
    /// 轉換為整數（分）
    var cents: Int {
        return decimalToCents(self)
    }

    /// 從整數（分）建立 Decimal
    /// - Parameter cents: 金額（分）
    /// - Returns: 金額（元）
    static func fromCents(_ cents: Int) -> Decimal {
        return centsToDecimal(cents)
    }
}
