//
//  ReportDataManager.swift
//  Tilli
//
//  Created by Claude on 2025/11/18.
//

import Foundation

/// 報表資料管理器：處理時間範圍內的交易查詢和統計
class ReportDataManager {
    private let transactionDataManager: TransactionDataManager

    init(transactionDataManager: TransactionDataManager) {
        self.transactionDataManager = transactionDataManager
    }

    // MARK: - 交易查詢

    /// 根據場次和時間範圍查詢交易
    func getTransactions(session: SessionModel, timeRange: ReportTimeRange) -> [TransactionModel] {
        return transactionDataManager.fetchTransactions(
            forSessionId: session.id,
            dateRange: timeRange.dateInterval
        )
    }

    // MARK: - 統計計算

    /// 每日營收統計
    func getDailyRevenue(session: SessionModel, timeRange: ReportTimeRange) -> [DailyRevenueData] {
        let transactions = getTransactions(session: session, timeRange: timeRange)

        let grouped = Dictionary(grouping: transactions) { transaction in
            Calendar.current.startOfDay(for: transaction.timestamp)
        }

        return grouped.map { date, txs in
            DailyRevenueData(
                date: date,
                amount: txs.reduce(0) { MoneyHelper.add($0, $1.totalAmount) },
                count: txs.count
            )
        }.sorted { $0.date < $1.date }
    }

    /// 每月營收統計
    func getMonthlyRevenue(session: SessionModel, timeRange: ReportTimeRange) -> [MonthlyRevenueData] {
        let transactions = getTransactions(session: session, timeRange: timeRange)

        let grouped = Dictionary(grouping: transactions) { transaction in
            Calendar.current.dateComponents([.year, .month], from: transaction.timestamp)
        }

        return grouped.map { components, txs in
            MonthlyRevenueData(
                year: components.year!,
                month: components.month!,
                amount: txs.reduce(0) { MoneyHelper.add($0, $1.totalAmount) },
                count: txs.count
            )
        }.sorted { ($0.year, $0.month) < ($1.year, $1.month) }
    }

    /// 總金額統計
    func getTotalAmount(session: SessionModel, timeRange: ReportTimeRange) -> Decimal {
        let transactions = getTransactions(session: session, timeRange: timeRange)
        return transactions.reduce(0) { MoneyHelper.add($0, $1.totalAmount) }
    }

    /// 總交易筆數
    func getTransactionCount(session: SessionModel, timeRange: ReportTimeRange) -> Int {
        return getTransactions(session: session, timeRange: timeRange).count
    }
}

// MARK: - 資料模型

/// 每日營收資料
struct DailyRevenueData: Identifiable {
    let id = UUID()
    let date: Date
    let amount: Decimal
    let count: Int
}

/// 每月營收資料
struct MonthlyRevenueData: Identifiable {
    let id = UUID()
    let year: Int
    let month: Int
    let amount: Decimal
    let count: Int

    var displayText: String {
        "\(year) 年 \(month) 月"
    }
}
