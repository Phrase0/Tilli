//
//  TransactionViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/4.
//

import SwiftUI

class TransactionViewModel: ObservableObject {
    
    @Binding var session: SessionModel
    
    // Transaction History 相關狀態
    @Published var transactions: [TransactionModel] = []
    @Published var expandedTransactionIds: Set<UUID> = []
    @Published var showingExportAlert = false
    @Published var csvContent = ""
    
    // 用於獲取最新狀態的 DataManager
    private var transactionDataManager: TransactionDataManager?
    
    var sessionTotalAmount: Double {
        session.transactions.reduce(0) { $0 + $1.totalAmount }
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
    
    func loadData() {
        guard let transactionManager = transactionDataManager else { return }
        transactions = transactionManager.fetchTransactions(forSessionId: session.id)
    }
    
    func generateCSVContent() -> String {
        var csvContent = "交易編號,日期時間,支付方式,商品名稱,類別,單價,數量,折扣%,小計,總金額\n"
        
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
    
    func formatAmount(_ amount: Double) -> String {
        return String(format: "%.0f", amount)
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
