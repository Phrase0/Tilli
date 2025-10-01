//
//  SalesAnalyticsService.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/16.
//

import Foundation

// MARK: - Helper Classes for Sales Analytics Statistics

class HourlyStatsHelper {
    private var hourlyStats: [Int: (amount: Decimal, transactions: Int)] = [:]

    init() {
        // 初始化 24 小時數據（0-23）
        for hour in 0...23 {
            hourlyStats[hour] = (amount: 0, transactions: 0)
        }
    }

    func addTransaction(timestamp: Date, amount: Decimal) {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: timestamp)

        let current = hourlyStats[hour] ?? (amount: 0, transactions: 0)
        hourlyStats[hour] = (
            amount: MoneyHelper.add(current.amount, amount),
            transactions: current.transactions + 1
        )
    }

    func getHourlyData() -> [HourlyAnalysisData] {
        return hourlyStats.keys.sorted().map { hour in
            let stats = hourlyStats[hour]!
            return HourlyAnalysisData(
                hour: hour,
                amount: stats.amount,
                transactions: stats.transactions
            )
        }
    }

    func getPeakHour() -> (hour: Int, amount: Decimal) {
        let maxEntry = hourlyStats.max { $0.value.amount < $1.value.amount }
        return (hour: maxEntry?.key ?? 0, amount: maxEntry?.value.amount ?? 0)
    }
}

class PaymentStatsHelper {
    private var paymentStats: [PaymentMethod: (transactions: Int, amount: Decimal)] = [:]

    init() {
        paymentStats[.cash] = (transactions: 0, amount: 0)
        paymentStats[.ePayment] = (transactions: 0, amount: 0)
    }

    func addTransaction(paymentMethod: PaymentMethod, amount: Decimal) {
        let current = paymentStats[paymentMethod] ?? (transactions: 0, amount: 0)
        paymentStats[paymentMethod] = (
            transactions: current.transactions + 1,
            amount: MoneyHelper.add(current.amount, amount)
        )
    }

    func getPaymentMethodData() -> [PaymentMethodAnalysisData] {
        let totalTransactions = paymentStats.values.reduce(0) { $0 + $1.transactions }

        return PaymentMethod.allCases.compactMap { method in
            guard let stats = paymentStats[method], stats.transactions > 0 else { return nil }

            return PaymentMethodAnalysisData(
                method: method,
                transactions: stats.transactions,
                amount: stats.amount,
                totalTransactions: totalTransactions
            )
        }
    }

    func getTotalStats() -> (transactions: Int, amount: Decimal) {
        let totalTransactions = paymentStats.values.reduce(0) { $0 + $1.transactions }
        let amounts = paymentStats.values.map { $0.amount }
        let totalAmount = MoneyHelper.sum(amounts)
        return (transactions: totalTransactions, amount: totalAmount)
    }
}

// MARK: - PaymentMethod Extension
extension PaymentMethod: CaseIterable {
    public static var allCases: [PaymentMethod] {
        return [.cash, .ePayment]
    }
}