//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/23.
//
import SwiftUI

struct TransactionModel: Identifiable, Codable, Hashable {
    var id = UUID()
    var eventId: UUID
    var eventTitle: String          // Event 名稱
    var currency: String              // 幣別
    var items: [SummaryItemModel]     // 多筆商品銷售記錄
    var totalAmount: Decimal
    var paymentMethod: PaymentMethod
    var timestamp: Date               // 記錄建立時間
    var occurredAt: Date?             // 補記帳時的實際發生時間
    /// 套用在整筆訂單上的折扣（最多一個百分比 + 一個定額）。
    /// 每一筆都帶 `amount` 快照，改了場次的折扣設定也不會影響歷史交易。
    var appliedDiscounts: [AppliedDiscount] = []

    /// 小計（折扣前，所有項目的 total 相加）
    var subtotal: Decimal { items.subtotal }

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

// MARK: - 顯示文字（交易紀錄、交易明細、CSV 共用，唯一一份）

extension TransactionModel {
    /// 交易編號：`TXN` ＋ id 前 8 碼（大寫）
    static func displayNumber(for id: UUID) -> String {
        "TXN\(id.uuidString.prefix(8).uppercased())"
    }

    var displayNumber: String { Self.displayNumber(for: id) }
}

extension PaymentMethod {
    var displayName: String {
        switch self {
        case .cash:
            // 現金
            return String.localized("transactionPaymentCash")
        case .ePayment:
            // 電子支付
            return String.localized("transactionPaymentEPayment")
        }
    }
}

// MARK: - CoreData 轉換
extension TransactionModel {
    init(entity: CDTransactionEntity) {
        self.id = entity.id
        self.eventId = entity.eventId
        self.eventTitle = entity.eventTitle
        self.currency = entity.currency
        self.totalAmount = entity.totalAmount.decimalValue
        self.paymentMethod = PaymentMethod(rawValue: entity.paymentMethod) ?? .cash
        self.timestamp = entity.timestamp
        self.occurredAt = entity.occurredAt

        // 解碼 items
        if let data = entity.itemsData,
           let decoded = try? JSONDecoder().decode([SummaryItemModel].self, from: data) {
            self.items = decoded
        } else {
            self.items = []
        }

        // 解碼折扣（舊資料或空值一律視為沒有折扣）
        if let data = entity.appliedDiscountsData,
           let decoded = try? JSONDecoder().decode([AppliedDiscount].self, from: data) {
            self.appliedDiscounts = decoded
        } else {
            self.appliedDiscounts = []
        }
    }
}
