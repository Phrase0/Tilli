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

extension Array where Element == DiscountModel {

    /// 儲存用的順序：**百分比升冪在前，減額升冪在後**。
    ///
    /// 只在按下儲存時套用 —— 編輯中即時排序會讓剛輸入的那一列在清單裡跳動。
    /// POS 的 chip 另外自己排，不依賴這個順序。
    var sortedForStorage: [DiscountModel] {
        let byValue: (DiscountModel, DiscountModel) -> Bool = { $0.value < $1.value }
        return filter { $0.type == .percentage }.sorted(by: byValue)
             + filter { $0.type == .amount }.sorted(by: byValue)
    }
}

// MARK: - AppliedDiscount

/// 實際套用在某一筆交易上的折扣（寫進流水帳）。
///
/// 與 `DiscountModel`（場次的折扣**設定**）的差別在 `amount` ——
/// 那是**快照**：交易當下實際折抵了多少錢，clamp 之後的值。
///
/// ⭐ 沒有這個快照的話，之後改了場次的折扣設定，
/// 歷史交易的折抵金額會被重算成錯的。見 FEATURE_PLAN_V1.md §6.1。
struct AppliedDiscount: Codable, Hashable, Identifiable {
    /// 對應 `event.discounts` 的設定；設定被刪除後仍保留這個 id 以供追溯
    var discountId: UUID
    var type: DiscountType
    /// 快照：折扣設定的值（5 = 5% 或 5 元）
    var value: Decimal
    /// ⭐ 快照：實際折抵金額（已 clamp）
    var amount: Decimal

    var id: UUID { discountId }
}
