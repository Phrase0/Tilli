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
    var items: [SummaryItemModel]     // 多筆商品銷售記錄
    var totalAmount: Double
    var paymentMethod: PaymentMethod
    var timestamp: Date
}

enum PaymentMethod: String, Codable {
    case cash
    case ePayment
}
