//
//  SalesAnalyticsModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/16.
//

import SwiftUI

// MARK: - Data Models

struct HourlyAnalysisData: Identifiable {
    let id = UUID()
    let hour: Int  // 0-23
    let hourString: String  // "09:00"
    let amount: Decimal  // 該時段總金額
    let transactions: Int  // 該時段交易筆數
    let avgPrice: Decimal  // 平均客單價

    init(hour: Int, amount: Decimal, transactions: Int) {
        self.hour = hour
        self.hourString = String(format: "%02d:00", hour)
        self.amount = amount
        self.transactions = transactions
        self.avgPrice = transactions > 0 ? amount / Decimal(transactions) : 0
    }
}

struct PaymentMethodAnalysisData: Identifiable {
    let id = UUID()
    let method: PaymentMethod
    let name: String
    let transactions: Int
    let amount: Decimal
    let percentage: Int
    let color: Color

    init(method: PaymentMethod, transactions: Int, amount: Decimal, totalTransactions: Int) {
        self.method = method
        self.transactions = transactions
        self.amount = amount
        self.percentage = totalTransactions > 0 ? Int((Double(transactions) / Double(totalTransactions)) * 100) : 0

        switch method {
        case .cash:
            self.name = "現金"
            self.color = .pink
        case .ePayment:
            self.name = "電子支付"
            self.color = .purple
        }
    }
}

struct SalesOverviewData {
    let totalAmount: Decimal
    let totalTransactions: Int
    let avgTransactionValue: Decimal
    let peakHour: Int
    let peakHourAmount: Decimal
    let paymentMethodStats: [PaymentMethodAnalysisData]

    init(totalAmount: Decimal, totalTransactions: Int, peakHour: Int, peakHourAmount: Decimal, paymentMethodStats: [PaymentMethodAnalysisData]) {
        self.totalAmount = totalAmount
        self.totalTransactions = totalTransactions
        self.avgTransactionValue = totalTransactions > 0 ? totalAmount / Decimal(totalTransactions) : 0
        self.peakHour = peakHour
        self.peakHourAmount = peakHourAmount
        self.paymentMethodStats = paymentMethodStats
    }
}