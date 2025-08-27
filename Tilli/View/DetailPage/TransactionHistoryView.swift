//
//  TransactionHistoryView.swift
//  Tilli
//
//  Created by Assistant on 2025/8/27.
//

import SwiftUI

struct TransactionHistoryView: View {
    @EnvironmentObject var transactionDataManager: TransactionDataManager
    @Binding var session: SessionModel
    @State private var transactions: [TransactionModel] = []
    @State private var expandedTransactionIds: Set<UUID> = []
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if transactions.isEmpty {
                    // 空狀態
                    VStack(spacing: 16) {
                        Image(systemName: "list.clipboard")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text("尚無交易記錄")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                        Text("完成結帳後，交易記錄會顯示在這裡")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 100)
                } else {
                    ForEach(transactions.sorted { $0.timestamp > $1.timestamp }) { transaction in
                        transactionCard(transaction)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            loadTransactions()
        }
        .refreshable {
            loadTransactions()
        }
    }
    
    private func transactionCard(_ transaction: TransactionModel) -> some View {
        let isExpanded = expandedTransactionIds.contains(transaction.id)
        
        return VStack(spacing: 0) {
            // 交易總覽卡片
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    if isExpanded {
                        expandedTransactionIds.remove(transaction.id)
                    } else {
                        expandedTransactionIds.insert(transaction.id)
                    }
                }
            }) {
                VStack(alignment: .leading, spacing: 8) {
                    // 第一行：交易編號和支付方式
                    HStack {
                        Text(formatTransactionId(transaction.id.uuidString))
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        Spacer()
                        
                        Text(paymentMethodText(transaction.paymentMethod))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(paymentMethodColor(transaction.paymentMethod))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    
                    // 第二行：日期時間
                    HStack {
                            Text(formatDateTime(transaction.timestamp))
                                .font(.subheadline)
                                .foregroundColor(.primary)

                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("NT$\(formatAmount(transaction.totalAmount))")
                                .font(.headline)
                                .bold()
                                .foregroundColor(.primary)
                            
                            Text("共 \(transaction.items.count) 項商品")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }

                }
                .padding()
            }
            .buttonStyle(PlainButtonStyle())
            
            // 交易明細（展開時顯示）
            if isExpanded {
                VStack(spacing: 0) {
                    // 表頭
                    HStack {
                        Text("商品")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text("類別")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(width: 60, alignment: .center)
                        
                        Text("數量")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(width: 50, alignment: .center)
                        
                        Text("折扣")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(width: 50, alignment: .center)
                        
                        Text("小計")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    
                    // 商品明細列表
                    ForEach(transaction.items) { item in
                        transactionItemRow(item)
                    }
                }
            }
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func transactionItemRow(_ item: SummaryItemModel) -> some View {
        HStack {
            // 商品名稱
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Text("NT$\(formatAmount(item.price))")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 類別
            Text(item.category)
                .font(.subheadline)
                .foregroundColor(.gray)
                .frame(width: 60, alignment: .center)
                .lineLimit(1)
            
            // 數量
            Text("\(item.quantity)")
                .font(.subheadline)
                .foregroundColor(.primary)
                .frame(width: 50, alignment: .center)
            
            // 折扣
            Text(item.discount > 0 ? "\(item.discount)%" : "-")
                .font(.subheadline)
                .foregroundColor(item.discount > 0 ? .orange : .gray)
                .frame(width: 50, alignment: .center)
            
            // 小計
            Text("\(formatAmount(item.total))")
                .font(.subheadline)
                .bold()
                .foregroundColor(.primary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.white)
    }
    
    // MARK: - Helper Methods
    
    private func loadTransactions() {
        transactions = transactionDataManager.fetchTransactions(forSessionId: session.id)
    }
    
    private func formatTransactionId(_ id: String) -> String {
        let prefix = String(id.prefix(8)).uppercased()
        return "TXN\(prefix)"
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
    
    private func formatAmount(_ amount: Double) -> String {
        return String(format: "%.0f", amount)
    }
    
    private func paymentMethodText(_ method: PaymentMethod) -> String {
        switch method {
        case .cash:
            return "現金"
        case .ePayment:
            return "電子支付"
        }
    }
    
    private func paymentMethodColor(_ method: PaymentMethod) -> Color {
        switch method {
        case .cash:
            return .green
        case .ePayment:
            return .blue
        }
    }
}
