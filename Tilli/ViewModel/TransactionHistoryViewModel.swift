//
//  TransactionViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/4.
//

import SwiftUI
import Foundation

class TransactionViewModel: ObservableObject {
    
    @Binding var session: SessionModel
    
    // Transaction History 相關狀態
    @Published var transactions: [TransactionModel] = []
    @Published var groupedTransactions: [DailyTransactionGroup] = []
    @Published var expandedTransactionIds: Set<UUID> = []
    @Published var showingExportAlert = false
    @Published var csvContent = ""
    @Published var currentTimeRange: ReportTimeRange?
    
    // 用於獲取最新狀態的 DataManager
    private var transactionDataManager: TransactionDataManager?
    
    var sessionTotalAmount: Decimal {
        if let transactionManager = transactionDataManager {
            let transactions = transactionManager.fetchTransactions(forSessionId: session.id)
            return transactions.reduce(0) { MoneyHelper.add($0, $1.totalAmount) }
        } else {
            return 0
        }
    }
    
    init(session: Binding<SessionModel>) {
        self._session = session
    }
    
    // MARK: - DataManager 管理
    
    /// 更新 DataManager 引用
    func updateDataManagers(
        transactionDataManager: TransactionDataManager
    ) {
        self.transactionDataManager = transactionDataManager
    }
    
    // MARK: - Transaction History 相關方法

    /// 載入交易資料（支援時間範圍）
    func loadData(timeRange: ReportTimeRange? = nil) {
        guard let transactionManager = transactionDataManager else { return }

        // 儲存當前時間範圍（用於 CSV 匯出）
        self.currentTimeRange = timeRange

        if let timeRange = timeRange {
            // 使用時間範圍查詢
            transactions = transactionManager.fetchTransactions(
                forSessionId: session.id,
                dateRange: timeRange.dateInterval
            )
        } else {
            // 查詢所有交易（向後兼容）
            transactions = transactionManager.fetchTransactions(forSessionId: session.id)
        }

        // 按日分組交易
        groupTransactionsByDate()
    }
    
    /// 將交易按日期分組
    private func groupTransactionsByDate() {
        let calendar = Calendar.current
        
        // 按日期分組
        let grouped = Dictionary(grouping: transactions) { transaction in
            calendar.startOfDay(for: transaction.timestamp)
        }
        
        // 轉換為 DailyTransactionGroup 並排序
        groupedTransactions = grouped.map { date, txs in
            DailyTransactionGroup(
                date: date,
                transactions: txs.sorted { $0.timestamp > $1.timestamp }
            )
        }.sorted { $0.date > $1.date }
    }
    
    func generateCSVContent() -> String {
        let currencyCode = session.currency
        var csvContent = ""
        
        // 在表格上方加入時間範圍資訊
        if let timeRange = currentTimeRange {
            csvContent += "\(session.title),\(timeRange.displayText)\n"
            csvContent += "\n"
        }
        
        csvContent += "交易編號,日期時間,支付方式,商品名稱,類別,單價(\(currencyCode)),數量,折扣%,小計(\(currencyCode)),總金額(\(currencyCode))\n"

        for transaction in transactions.sorted(by: { $0.timestamp > $1.timestamp }) {
            let transactionId = formatTransactionId(transaction.id.uuidString)
            let dateTime = formatDateTime(transaction.timestamp)
            let paymentMethod = paymentMethodText(transaction.paymentMethod)
            let totalAmount = formatAmount(transaction.totalAmount)
            
            for item in transaction.items {
                let productName = item.name.replacingOccurrences(of: ",", with: "，") // 避免CSV格式問題
                let category = item.category.replacingOccurrences(of: ",", with: "，")
                let unitPrice = formatAmount(item.price)
                let quantity = "\(item.quantity)"
                let discount = item.discount > 0 ? "\(item.discount)%" : "0%"
                let subtotal = formatAmount(item.total)
                
                let row = "\(transactionId),\(dateTime),\(paymentMethod),\(productName),\(category),\(unitPrice),\(quantity),\(discount),\(subtotal),\(totalAmount)\n"
                csvContent += row
            }
        }
        
        return csvContent
    }
    
    func exportCSV() {
        csvContent = generateCSVContent()
    }
    
    func createTempCSVFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "交易明細_\(session.title)_\(DateFormatter.csvFileDate.string(from: Date())).csv"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            let content = generateCSVContent()  // 自動生成內容
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error creating CSV file: \(error)")
        }
        
        return fileURL
    }
    
    
    func showExportSuccessAlert() {
        showingExportAlert = true
    }
    
    func toggleTransactionExpansion(_ transactionId: UUID) {
        withAnimation(.easeInOut(duration: 0.3)) {
            if expandedTransactionIds.contains(transactionId) {
                expandedTransactionIds.remove(transactionId)
            } else {
                expandedTransactionIds.insert(transactionId)
            }
        }
    }
    
    func isTransactionExpanded(_ transactionId: UUID) -> Bool {
        return expandedTransactionIds.contains(transactionId)
    }
    
    func formatTransactionId(_ id: String) -> String {
        let prefix = String(id.prefix(8)).uppercased()
        return "TXN\(prefix)"
    }
    
    func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
    
    func formatAmount(_ amount: Decimal, currency: String? = nil) -> String {
        let currencyCode = currency ?? session.currency
        return MoneyHelper.format(amount, currencyCode: currencyCode)
    }
    
    func paymentMethodText(_ method: PaymentMethod) -> String {
        switch method {
        case .cash:
            return "現金"
        case .ePayment:
            return "電子支付"
        }
    }
    
    func paymentMethodColor(_ method: PaymentMethod) -> Color {
        switch method {
        case .cash:
            return .pink
        case .ePayment:
            return .purple
        }
    }
}

// MARK: - 資料模型

/// 每日交易分組
struct DailyTransactionGroup: Identifiable {
    let id = UUID()
    let date: Date
    let transactions: [TransactionModel]
    
    /// 當日總金額
    var totalAmount: Decimal {
        transactions.reduce(0) { MoneyHelper.add($0, $1.totalAmount) }
    }
    
    /// 當日交易筆數
    var count: Int {
        transactions.count
    }
    
    /// 日期顯示文字
    var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy/MM/dd (E)"
        return formatter.string(from: date)
    }
}
