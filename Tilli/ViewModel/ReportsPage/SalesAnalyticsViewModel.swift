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
        DateFormatter.shortDate.string(from: date)
    }

    var fullDateString: String {
        DateFormatter.dateWithWeekday.string(from: date)
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
        // %lld月
        return String.localized("analyticsMonthFormat \(month)")
    }

    var fullMonthString: String {
        // %lld年%lld月
        return String.localized("analyticsYearMonthFormat \(year) \(month)")
    }
}

class SalesAnalyticsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var hourlyData: [HourlyAnalysisData] = []
    @Published var paymentMethodData: [PaymentMethodAnalysisData] = []
    @Published var salesOverview: SalesOverviewData? = nil
    @Published var isLoading = false

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
    private var transactionDataManager: TransactionRepository?
    @Binding var event: EventModel
    private(set) var currentTimeRange: ReportTimeRange?

    // MARK: - Initialization
    init(event: Binding<EventModel>) {
        self._event = event
    }

    // MARK: - DataManager 管理

    /// 更新 DataManager 引用
    func updateDataManagers(transactionDataManager: TransactionRepository) {
        self.transactionDataManager = transactionDataManager
    }

    // MARK: - Public Methods

    /// 載入資料（支援時間範圍）
    func loadData(timeRange: ReportTimeRange? = nil) {
        // 儲存當前時間範圍（用於 CSV 匯出）- 即使 DataManager 未設定也要保存
        self.currentTimeRange = timeRange

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
        let currencyCode = event.currency
        var csvContent = ""

        // 時段銷售分析
        let csvTitle = String.localized("csvHourlyAnalysisTitle")
        if let timeRange = currentTimeRange {
            csvContent += "\(csvTitle)_\(event.title), \(timeRange.csvDateRangeText)\n"
        } else {
            csvContent += "\(csvTitle)_\(event.title)\n"
        }
        csvContent += "\n"

        // 時段,銷售金額,交易筆數,平均客單價
        let h1 = String.localized("csvTimePeriod")
        let h2 = String.localized("csvSalesAmount \(currencyCode)")
        let h3 = String.localized("csvTransactionCount")
        let h4 = String.localized("csvAvgOrderValue \(currencyCode)")
        csvContent += "\(h1),\(h2),\(h3),\(h4)\n"

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
        let currencyCode = event.currency
        var csvContent = ""

        // 支付方式分析
        let csvTitle = String.localized("csvPaymentMethodTitle")
        if let timeRange = currentTimeRange {
            csvContent += "\(csvTitle)_\(event.title), \(timeRange.csvDateRangeText)\n"
        } else {
            csvContent += "\(csvTitle)_\(event.title)\n"
        }
        csvContent += "\n"

        // 支付方式,交易金額,交易筆數,佔比%
        let h1 = String.localized("csvPaymentMethod")
        let h2 = String.localized("csvTransactionAmount \(currencyCode)")
        let h3 = String.localized("csvTransactionCount")
        let h4 = String.localized("csvPercentage")
        csvContent += "\(h1),\(h2),\(h3),\(h4)\n"

        for paymentData in paymentMethodData {
            let name = paymentData.name.replacingOccurrences(of: ",", with: "，")
            let currency = Currency(rawValue: currencyCode) ?? .twd
            let amount = MoneyHelper.toDisplayString(paymentData.amount, currency: currency)
            let transactions = "\(paymentData.transactions)"
            let percentage = "\(paymentData.percentage)%"

            let row = "\(name),\(amount),\(transactions),\(percentage)\n"
            csvContent += row
        }

        return csvContent
    }

    func generateDailyRevenueTrendCSV() -> String {
        let currencyCode = event.currency
        let currency = Currency(rawValue: currencyCode) ?? .twd
        var csvContent = ""

        // 日營收趨勢
        let csvTitle = String.localized("csvDailyRevenueTitle")
        if let timeRange = currentTimeRange {
            csvContent += "\(csvTitle)_\(event.title), \(timeRange.csvDateRangeText)\n"
        } else {
            csvContent += "\(csvTitle)_\(event.title)\n"
        }
        csvContent += "\n"

        // 日期,交易筆數,營收
        let h1 = String.localized("csvDate")
        let h2 = String.localized("csvTransactionCount")
        let h3 = String.localized("csvRevenue \(currencyCode)")
        csvContent += "\(h1),\(h2),\(h3)\n"

        for data in dailyRevenue {
            let date = data.fullDateString
            let count = "\(data.count)"
            let amount = MoneyHelper.toDisplayString(data.amount, currency: currency)

            let row = "\(date),\(count),\(amount)\n"
            csvContent += row
        }

        return csvContent
    }

    func generateMonthlyRevenueTrendCSV() -> String {
        let currencyCode = event.currency
        let currency = Currency(rawValue: currencyCode) ?? .twd
        var csvContent = ""

        // 月營收趨勢
        let csvTitle = String.localized("csvMonthlyRevenueTitle")
        if let timeRange = currentTimeRange {
            csvContent += "\(csvTitle)_\(event.title), \(timeRange.csvDateRangeText)\n"
        } else {
            csvContent += "\(csvTitle)_\(event.title)\n"
        }
        csvContent += "\n"

        // 月份,交易筆數,營收
        let h1 = String.localized("csvMonth")
        let h2 = String.localized("csvTransactionCount")
        let h3 = String.localized("csvRevenue \(currencyCode)")
        csvContent += "\(h1),\(h2),\(h3)\n"

        for data in monthlyRevenue {
            let month = data.fullMonthString
            let count = "\(data.count)"
            let amount = MoneyHelper.toDisplayString(data.amount, currency: currency)

            let row = "\(month),\(count),\(amount)\n"
            csvContent += row
        }

        return csvContent
    }


    func createHourlyAnalysisCSVFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let safeTitle = event.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        // 時段銷售分析
        let csvFileLabel = String.localized("csvFileHourlyAnalysis")
        let fileName = "\(csvFileLabel)_\(safeTitle)_\(DateFormatter.fileTimestamp.string(from: Date())).csv"
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
        let safeTitle = event.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        // 支付方式分析
        let csvFileLabel = String.localized("csvFilePaymentMethod")
        let fileName = "\(csvFileLabel)_\(safeTitle)_\(DateFormatter.fileTimestamp.string(from: Date())).csv"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            let csvContent = generatePaymentMethodCSV()
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error creating Payment Method CSV file: \(error)")
        }

        return fileURL
    }

    func createDailyRevenueTrendCSVFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        // 過濾檔名中的非法字符
        let safeTitle = event.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        // 日營收趨勢
        let csvFileLabel = String.localized("csvFileDailyRevenue")
        let fileName = "\(csvFileLabel)_\(safeTitle)_\(DateFormatter.fileTimestamp.string(from: Date())).csv"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            let csvContent = generateDailyRevenueTrendCSV()
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error creating Daily Revenue Trend CSV file: \(error)")
        }

        return fileURL
    }

    func createMonthlyRevenueTrendCSVFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        // 過濾檔名中的非法字符
        let safeTitle = event.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        // 月營收趨勢
        let csvFileLabel = String.localized("csvFileMonthlyRevenue")
        let fileName = "\(csvFileLabel)_\(safeTitle)_\(DateFormatter.fileTimestamp.string(from: Date())).csv"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            let csvContent = generateMonthlyRevenueTrendCSV()
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error creating Monthly Revenue Trend CSV file: \(error)")
        }

        return fileURL
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
                forEventId: event.id,
                dateRange: timeRange.dateInterval
            )
        } else {
            transactions = transactionDataManager.fetchTransactions(forEventId: event.id)
        }

        // 初始化 Helper Classes
        let hourlyHelper = HourlyStatsHelper()
        let paymentHelper = PaymentStatsHelper()

        // 處理每筆交易（使用 displayDate 進行時段統計）
        for transaction in transactions {
            hourlyHelper.addTransaction(
                displayDate: transaction.displayDate,
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

        // 按日期分組交易（使用 displayDate）
        let grouped = Dictionary(grouping: transactions) { transaction in
            calendar.startOfDay(for: transaction.displayDate)
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
            let components = calendar.dateComponents([.year, .month], from: transaction.displayDate)
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
