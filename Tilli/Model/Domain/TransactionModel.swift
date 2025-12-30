//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/23.
//
import SwiftUI

struct TransactionModel: Identifiable, Codable, Hashable {
    var id = UUID()
    var sessionId: UUID
    var sessionTitle: String          // Session 名稱
    var currency: String              // 幣別
    var items: [SummaryItemModel]     // 多筆商品銷售記錄
    var totalAmount: Decimal
    var paymentMethod: PaymentMethod
    var timestamp: Date               // 記錄建立時間
    var occurredAt: Date?             // 補記帳時的實際發生時間
    var discountType: DiscountType?   // 套用的折扣類型（整筆訂單）
    var discountValue: Decimal?       // 套用的折扣數值

    /// 顯示用日期（優先使用 occurredAt，否則用 timestamp）
    var displayDate: Date {
        return occurredAt ?? timestamp
    }

    /// 是否為補記帳（有設定 occurredAt）
    var isBackdated: Bool {
        return occurredAt != nil
    }
}

enum PaymentMethod: String, Codable {
    case cash
    case ePayment
}
