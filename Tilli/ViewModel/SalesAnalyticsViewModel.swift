//
//  SalesAnalyticsViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/16.
//

import SwiftUI
import Foundation

class SalesAnalyticsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var hourlyData: [HourlyAnalysisData] = []
    @Published var paymentMethodData: [PaymentMethodAnalysisData] = []
    @Published var salesOverview: SalesOverviewData? = nil
    @Published var isLoading = false
    @Published var showingExportAlert = false
    @Published var csvContent = ""

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
    func loadData() {
        guard transactionDataManager != nil else { return }

        isLoading = true

        Task {
            await MainActor.run {
                calculateSalesAnalytics()
                isLoading = false
            }
        }
    }

    // MARK: - CSV Export Methods

    func generateHourlyAnalysisCSV() -> String {
        var csvContent = "時段,銷售金額,交易筆數,平均客單價\n"

        for hourData in hourlyData {
            let hour = hourData.hourString
            let amount = String(format: "%.0f", hourData.amount)
            let transactions = "\(hourData.transactions)"
            let avgPrice = String(format: "%.0f", hourData.avgPrice)

            let row = "\(hour),\(amount),\(transactions),\(avgPrice)\n"
            csvContent += row
        }

        return csvContent
    }

    func generatePaymentMethodCSV() -> String {
        var csvContent = "支付方式,交易筆數,交易金額,佔比%\n"

        for paymentData in paymentMethodData {
            let name = paymentData.name.replacingOccurrences(of: ",", with: "，")
            let transactions = "\(paymentData.transactions)"
            let amount = String(format: "%.0f", paymentData.amount)
            let percentage = "\(paymentData.percentage)%"

            let row = "\(name),\(transactions),\(amount),\(percentage)\n"
            csvContent += row
        }

        return csvContent
    }


    func createHourlyAnalysisCSVFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "時段銷售分析_\(session.title)_\(DateFormatter.csvFileDate.string(from: Date())).csv"
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
        let fileName = "支付方式分析_\(session.title)_\(DateFormatter.csvFileDate.string(from: Date())).csv"
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

    /// 計算銷售分析數據
    func calculateSalesAnalytics() {
        guard let transactionDataManager = transactionDataManager else { return }

        let transactions = transactionDataManager.fetchTransactions(forSessionId: session.id)

        // 初始化 Helper Classes
        let hourlyHelper = HourlyStatsHelper()
        let paymentHelper = PaymentStatsHelper()

        // 處理每筆交易
        for transaction in transactions {
            hourlyHelper.addTransaction(
                timestamp: transaction.timestamp,
                amount: MoneyHelper.toDouble(transaction.totalAmount)
            )

            paymentHelper.addTransaction(
                paymentMethod: transaction.paymentMethod,
                amount: MoneyHelper.toDouble(transaction.totalAmount)
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
    }
}
