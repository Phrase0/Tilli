//
//  SalesAnalyticsViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/16.
//

import SwiftUI
import Foundation

// MARK: - Revenue Trend Data Models

/// 每日營收資料
struct DailyRevenueData: Identifiable {
    let id = UUID()
    let date: Date
    let amount: Decimal
    let count: Int

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }

    var fullDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}

/// 每月營收資料
struct MonthlyRevenueData: Identifiable {
    let id = UUID()
    let year: Int
    let month: Int
    let amount: Decimal
    let count: Int

    var monthString: String {
        return "\(month)月"
    }

    var fullMonthString: String {
        return "\(year)/\(month)月"
    }
}

class SalesAnalyticsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var hourlyData: [HourlyAnalysisData] = []
    @Published var paymentMethodData: [PaymentMethodAnalysisData] = []
    @Published var salesOverview: SalesOverviewData? = nil
    @Published var isLoading = false
    @Published var showingExportAlert = false
    @Published var csvContent = ""

    // MARK: - Revenue Trend Properties
    @Published var dailyRevenue: [DailyRevenueData] = []
    @Published var monthlyRevenue: [MonthlyRevenueData] = []
    @Published var trendViewMode: TrendViewMode = .daily

    enum TrendViewMode {
        case daily
        case monthly
    }

    /// 最大日營收金額（用於圖表比例）
    var maxDailyAmount: Decimal {
        dailyRevenue.map { $0.amount }.max() ?? 1
    }

    /// 最大月營收金額（用於圖表比例）
    var maxMonthlyAmount: Decimal {
        monthlyRevenue.map { $0.amount }.max() ?? 1
    }

    // MARK: - Dependencies
    private var transactionDataManager: TransactionDataManager?
    @Binding var session: SessionModel

    // MARK: - Initialization
    init(session: Binding<SessionModel>) {
        self._session = session
    }

    // MARK: - DataManager 管理

    /// 更新 DataManager 引用
    func updateDataManagers(transactionDataManager: TransactionDataManager) {
        self.transactionDataManager = transactionDataManager
    }

    // MARK: - Public Methods

    /// 載入資料（支援時間範圍）
    func loadData(timeRange: ReportTimeRange? = nil) {
        guard transactionDataManager != nil else { return }

        isLoading = true

        Task {
            await MainActor.run {
                calculateSalesAnalytics(timeRange: timeRange)
                isLoading = false
            }
        }
    }

    // MARK: - CSV Export Methods

    func generateHourlyAnalysisCSV() -> String {
        let currencyCode = session.currency
        var csvContent = "時段,銷售金額(\(currencyCode)),交易筆數,平均客單價(\(currencyCode))\n"

        for hourData in hourlyData {
            let hour = hourData.hourString
            let currency = Currency(rawValue: currencyCode) ?? .twd
            let amount = MoneyHelper.toDisplayString(hourData.amount, currency: currency)
            let transactions = "\(hourData.transactions)"
            let avgPrice = MoneyHelper.toDisplayString(hourData.avgPrice, currency: currency)

            let row = "\(hour),\(amount),\(transactions),\(avgPrice)\n"
            csvContent += row
        }

        return csvContent
    }

    func generatePaymentMethodCSV() -> String {
        let currencyCode = session.currency
        var csvContent = "支付方式,交易筆數,交易金額(\(currencyCode)),佔比%\n"

        for paymentData in paymentMethodData {
            let name = paymentData.name.replacingOccurrences(of: ",", with: "，")
            let transactions = "\(paymentData.transactions)"
            let currency = Currency(rawValue: currencyCode) ?? .twd
            let amount = MoneyHelper.toDisplayString(paymentData.amount, currency: currency)
            let percentage = "\(paymentData.percentage)%"

            let row = "\(name),\(transactions),\(amount),\(percentage)\n"
            csvContent += row
        }

        return csvContent
    }


    func createHourlyAnalysisCSVFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        // 過濾檔名中的非法字符
        let safeTitle = session.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let fileName = "時段銷售分析_\(safeTitle)_\(DateFormatter.csvFileDate.string(from: Date())).csv"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            let csvContent = generateHourlyAnalysisCSV()
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error creating Hourly Analysis CSV file: \(error)")
        }

        return fileURL
    }

    func createPaymentMethodCSVFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        // 過濾檔名中的非法字符
        let safeTitle = session.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let fileName = "支付方式分析_\(safeTitle)_\(DateFormatter.csvFileDate.string(from: Date())).csv"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            let csvContent = generatePaymentMethodCSV()
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error creating Payment Method CSV file: \(error)")
        }

        return fileURL
    }

    func showExportSuccessAlert() {
        showingExportAlert = true
    }
}

// MARK: - Business Logic Calculations
private extension SalesAnalyticsViewModel {

    /// 計算銷售分析數據（支援時間範圍）
    func calculateSalesAnalytics(timeRange: ReportTimeRange? = nil) {
        guard let transactionDataManager = transactionDataManager else { return }

        // 根據時間範圍查詢交易
        let transactions: [TransactionModel]
        if let timeRange = timeRange {
            transactions = transactionDataManager.fetchTransactions(
                forSessionId: session.id,
                dateRange: timeRange.dateInterval
            )
        } else {
            transactions = transactionDataManager.fetchTransactions(forSessionId: session.id)
        }

        // 初始化 Helper Classes
        let hourlyHelper = HourlyStatsHelper()
        let paymentHelper = PaymentStatsHelper()

        // 處理每筆交易
        for transaction in transactions {
            hourlyHelper.addTransaction(
                timestamp: transaction.timestamp,
                amount: transaction.totalAmount
            )

            paymentHelper.addTransaction(
                paymentMethod: transaction.paymentMethod,
                amount: transaction.totalAmount
            )
        }

        // 獲取時段數據
        hourlyData = hourlyHelper.getHourlyData()

        // 獲取支付方式數據
        paymentMethodData = paymentHelper.getPaymentMethodData()

        // 計算總覽數據
        let peakHourData = hourlyHelper.getPeakHour()
        let totalStats = paymentHelper.getTotalStats()

        salesOverview = SalesOverviewData(
            totalAmount: totalStats.amount,
            totalTransactions: totalStats.transactions,
            peakHour: peakHourData.hour,
            peakHourAmount: peakHourData.amount,
            paymentMethodStats: paymentMethodData
        )

        // 計算營收趨勢數據
        if let timeRange = timeRange {
            dailyRevenue = calculateDailyRevenue(transactions: transactions, timeRange: timeRange)
            monthlyRevenue = calculateMonthlyRevenue(transactions: transactions)
        }
    }

    // MARK: - Revenue Trend Calculations

    /// 計算每日營收（包含無交易的日期）
    func calculateDailyRevenue(
        transactions: [TransactionModel],
        timeRange: ReportTimeRange
    ) -> [DailyRevenueData] {
        let calendar = Calendar.current

        // 按日期分組交易
        let grouped = Dictionary(grouping: transactions) { transaction in
            calendar.startOfDay(for: transaction.timestamp)
        }

        // 生成時間範圍內的所有日期
        var allDates: [Date] = []
        var currentDate = timeRange.actualStart
        let endDate = timeRange.actualEnd

        while currentDate <= endDate {
            allDates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        // 為每個日期創建資料（沒有交易的日期金額為 0）
        return allDates.map { date in
            let dayTransactions = grouped[date] ?? []
            let amount = dayTransactions.reduce(Decimal(0)) { MoneyHelper.add($0, $1.totalAmount) }
            return DailyRevenueData(
                date: date,
                amount: amount,
                count: dayTransactions.count
            )
        }
    }

    /// 計算每月營收
    func calculateMonthlyRevenue(transactions: [TransactionModel]) -> [MonthlyRevenueData] {
        let calendar = Calendar.current

        let grouped = Dictionary(grouping: transactions) { transaction in
            let components = calendar.dateComponents([.year, .month], from: transaction.timestamp)
            return "\(components.year!)-\(components.month!)"
        }

        var result: [MonthlyRevenueData] = []

        for (key, txs) in grouped {
            let parts = key.split(separator: "-")
            guard parts.count == 2,
                  let year = Int(parts[0]),
                  let month = Int(parts[1]) else { continue }

            let amount = txs.reduce(Decimal(0)) { MoneyHelper.add($0, $1.totalAmount) }

            result.append(MonthlyRevenueData(
                year: year,
                month: month,
                amount: amount,
                count: txs.count
            ))
        }

        return result.sorted { ($0.year, $0.month) < ($1.year, $1.month) }
    }
}
