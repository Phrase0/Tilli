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
    let amount: Double  // 該時段總金額
    let transactions: Int  // 該時段交易筆數
    let avgPrice: Double  // 平均客單價

    init(hour: Int, amount: Double, transactions: Int) {
        self.hour = hour
        self.hourString = String(format: "%02d:00", hour)
        self.amount = amount
        self.transactions = transactions
        self.avgPrice = transactions > 0 ? amount / Double(transactions) : 0
    }
}

struct PaymentMethodAnalysisData: Identifiable {
    let id = UUID()
    let method: PaymentMethod
    let name: String
    let transactions: Int
    let amount: Double
    let percentage: Int
    let color: Color

    init(method: PaymentMethod, transactions: Int, amount: Double, totalTransactions: Int) {
        self.method = method
        self.transactions = transactions
        self.amount = amount
        self.percentage = totalTransactions > 0 ? Int((Double(transactions) / Double(totalTransactions)) * 100) : 0

        switch method {
        case .cash:
            self.name = "現金"
            self.color = .red
        case .ePayment:
            self.name = "電子支付"
            self.color = .yellow
        }
    }
}

struct SalesOverviewData {
    let totalAmount: Double
    let totalTransactions: Int
    let avgTransactionValue: Double
    let peakHour: Int
    let peakHourAmount: Double
    let paymentMethodStats: [PaymentMethodAnalysisData]

    init(totalAmount: Double, totalTransactions: Int, peakHour: Int, peakHourAmount: Double, paymentMethodStats: [PaymentMethodAnalysisData]) {
        self.totalAmount = totalAmount
        self.totalTransactions = totalTransactions
        self.avgTransactionValue = totalTransactions > 0 ? totalAmount / Double(totalTransactions) : 0
        self.peakHour = peakHour
        self.peakHourAmount = peakHourAmount
        self.paymentMethodStats = paymentMethodStats
    }
}