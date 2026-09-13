//
//  DiscountCalculator.swift
//  Tilli
//
//  Created by Peiyun on 2026/9/12.
//
//  折扣計算的唯一入口，取代散落 8 處的 `switch discountType`。
//  見 FEATURE_PLAN_V1.md §2.3（解 B4、B1）。
//
//  ⭐ clamp 內建在這裡，不依賴呼叫端記得做。
//  原本只有 POSViewModel.effectiveDiscount() 有做保護，換個入口（補記帳、
//  測試資料產生器、未來的批次匯入）就會存進未 clamp 的折扣，
//  報表攤提會算出【負營收】。
//

import Foundation

enum DiscountCalculator {

    // MARK: - 折扣金額

    /// 單一折扣的金額，已 clamp 到 `0...subtotal`。
    static func amount(type: DiscountType, value: Decimal, subtotal: Decimal) -> Decimal {
        guard subtotal > 0 else { return 0 }

        let raw: Decimal
        switch type {
        case .percentage:
            let rate = clampPercentage(value)
            raw = MoneyHelper.multiply(subtotal, MoneyHelper.divide(rate, 100))
        case .amount:
            raw = value
        }

        return clamp(raw, to: subtotal)
    }

    /// 多重折扣的總金額，已 clamp 到 `0...subtotal`。
    ///
    /// 順序固定為**先百分比、後定額** —— 百分比先作用於原小計，
    /// 定額再從剩餘金額扣除，避免「先扣定額再打折」讓折扣被低估。
    static func amount(for discounts: [DiscountModel], subtotal: Decimal) -> Decimal {
        guard subtotal > 0, !discounts.isEmpty else { return 0 }
        return MoneyHelper.subtract(subtotal, total(subtotal: subtotal, discounts: discounts))
    }

    /// 流水帳的折扣金額（`TransactionModel` 目前存單一折扣的 type/value）。
    static func amount(for transaction: TransactionModel) -> Decimal {
        guard let type = transaction.discountType,
              let value = transaction.discountValue else { return 0 }
        return amount(type: type, value: value, subtotal: transaction.subtotal)
    }

    // MARK: - 套用折扣後的總額

    /// 套用折扣後的應付金額，保證 `>= 0`。
    static func total(subtotal: Decimal, discounts: [DiscountModel]) -> Decimal {
        guard subtotal > 0 else { return 0 }

        // 先百分比
        var running = subtotal
        for discount in discounts where discount.type == .percentage {
            let rate = clampPercentage(discount.value)
            let cut = MoneyHelper.multiply(running, MoneyHelper.divide(rate, 100))
            running = MoneyHelper.subtract(running, cut)
        }

        // 後定額。每一筆都 clamp 到 0...running：
        // 負數折扣不可以反而加錢，單筆也不可以把總額扣成負的。
        for discount in discounts where discount.type == .amount {
            let deduction = min(max(discount.value, 0), running)
            running = MoneyHelper.subtract(running, deduction)
        }

        return max(running, 0)
    }

    /// 單一折扣版本（目前 POS 只允許選一個）
    static func total(subtotal: Decimal, discount: DiscountModel?) -> Decimal {
        guard let discount else { return max(subtotal, 0) }
        return total(subtotal: subtotal, discounts: [discount])
    }

    // MARK: - 實際套用的折扣（寫進交易前的收斂）

    /// 回傳「實際會被套用」的折扣 —— 定額折扣會先被 clamp 到不超過小計。
    ///
    /// 寫進 `TransactionModel` 前一律走這裡，這樣流水帳裡不會留下
    /// 超過小計的折扣值，報表就不可能算出負營收。
    static func effective(_ discount: DiscountModel?, subtotal: Decimal) -> DiscountModel? {
        guard let discount else { return nil }

        switch discount.type {
        case .percentage:
            let clamped = clampPercentage(discount.value)
            guard clamped != discount.value else { return discount }
            return DiscountModel(id: discount.id, type: .percentage, value: clamped)
        case .amount:
            let clamped = clamp(discount.value, to: subtotal)
            guard clamped != discount.value else { return discount }
            return DiscountModel(id: discount.id, type: .amount, value: clamped)
        }
    }

    /// 折扣是否超過小計（只有定額折扣可能發生；百分比已限制 ≤ 100%）
    static func exceedsSubtotal(_ discount: DiscountModel?, subtotal: Decimal) -> Bool {
        guard let discount, subtotal > 0 else { return false }
        switch discount.type {
        case .percentage:
            return discount.value > 100
        case .amount:
            return discount.value > subtotal
        }
    }

    // MARK: - 顯示文字

    /// 折扣本身的顯示文字，例如 `5%` 或 `NT$5`（場次設定、POS chip 用）
    static func displayText(type: DiscountType, value: Decimal, currency: String = "") -> String {
        switch type {
        case .percentage:
            return "\(value)%"
        case .amount:
            return "\(currencySymbol(for: currency))\(value)"
        }
    }

    /// 「扣了多少」的顯示文字，例如 `5%` 或 `-5`（交易紀錄、CSV 用）
    static func deductionText(type: DiscountType, value: Decimal) -> String {
        switch type {
        case .percentage:
            return "\(value)%"
        case .amount:
            return "-\(value)"
        }
    }

    /// 流水帳的折扣顯示文字；沒有折扣時回傳 nil
    static func deductionText(for transaction: TransactionModel) -> String? {
        guard let type = transaction.discountType,
              let value = transaction.discountValue else { return nil }
        return deductionText(type: type, value: value)
    }

    /// 根據幣別取得金額折扣的單位前綴
    static func currencySymbol(for currencyCode: String) -> String {
        guard let currency = Currency(rawValue: currencyCode) else {
            return String.localized("currencyDefaultSymbol") // 元
        }
        return currency.symbol
    }

    // MARK: - Clamp

    /// 折扣金額不可為負、也不可超過小計
    private static func clamp(_ value: Decimal, to subtotal: Decimal) -> Decimal {
        min(max(value, 0), subtotal)
    }

    /// 百分比限制在 0...100
    private static func clampPercentage(_ value: Decimal) -> Decimal {
        min(max(value, 0), 100)
    }
}
