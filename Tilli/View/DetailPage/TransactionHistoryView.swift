//
//  TransactionHistoryView.swift
//  Tilli
//
//  Created by Peiyun on 2025/8/27.
//

import SwiftUI
import UniformTypeIdentifiers

struct TransactionHistoryView: View {
    @ObservedObject var transactionViewModel: TransactionViewModel
    @Binding var session: SessionModel
    @State private var showingShareSheet = false
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if transactionViewModel.transactions.isEmpty {
                    EmptyStateView(
                        systemImage: "list.clipboard",
                        title: "尚無交易記錄",
                        message: "完成結帳後，交易記錄會顯示在這裡"
                    )
                } else {
                    ForEach(transactionViewModel.transactions.sorted { $0.timestamp > $1.timestamp }) { transaction in
                        transactionCard(transaction)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            transactionViewModel.loadTransactions()
        }
        .refreshable {
            transactionViewModel.loadTransactions()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    transactionViewModel.exportCSV()
                    showingShareSheet = true
                }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(transactionViewModel.transactions.isEmpty)
            }
        }
        .alert("CSV 導出成功", isPresented: $transactionViewModel.showingExportAlert) {
            Button("確定") { }
        } message: {
            Text("交易明細已成功導出為 CSV 檔案")
        }
        .shareSheet(
            isPresented: $showingShareSheet,
            activityItems: [
                CustomActivityItemSource(
                    csvContent: transactionViewModel.csvContent,
                    csvFileURL: transactionViewModel.createTempCSVFileURL()
                )
            ],
            excludedTypes: UIActivity.ActivityType.defaultExcludedTypes,
            onComplete: { completed in
                if completed {
                    transactionViewModel.showExportSuccessAlert()
                }
            }
        )
    }
    
    private func transactionCard(_ transaction: TransactionModel) -> some View {
        let isExpanded = transactionViewModel.isTransactionExpanded(transaction.id)
        
        return VStack(spacing: 0) {
            // 交易總覽卡片
            Button(action: {
                transactionViewModel.toggleTransactionExpansion(transaction.id)
            }) {
                VStack(alignment: .leading, spacing: 8) {
                    // 第一行：交易編號和支付方式
                    HStack {
                        Text(transactionViewModel.formatTransactionId(transaction.id.uuidString))
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        
                        Spacer()
                        
                        Text(transactionViewModel.paymentMethodText(transaction.paymentMethod))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(transactionViewModel.paymentMethodColor(transaction.paymentMethod))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    
                    // 第二行：日期時間
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2)  {
                            Text(transactionViewModel.formatDateTime(transaction.timestamp))
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Text("共 \(transaction.items.count) 項商品")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        
                        Spacer()
                        
                        HStack(alignment: .center)  {
                            Text("NT$\(transactionViewModel.formatAmount(transaction.totalAmount))")
                                .font(.headline)
                                .bold()
                                .foregroundColor(.primary)
                            
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
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
                            .frame(width: 50, alignment: .center)
                        
                        Text("單價")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(width: 50, alignment: .center)
                        
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
                            .frame(width: 50, alignment: .center)
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
            Text(item.name)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // 類別
            Text(item.category)
                .font(.subheadline)
                .foregroundColor(.gray)
                .frame(width: 50, alignment: .center)
                .lineLimit(1)
            
            
            Text("\(transactionViewModel.formatAmount(item.price))")
                .font(.subheadline)
                .foregroundColor(.blue)
                .frame(width: 50, alignment: .center)
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
            Text("\(transactionViewModel.formatAmount(item.total))")
                .font(.subheadline)
                .bold()
                .foregroundColor(.primary)
                .frame(width: 50, alignment: .center)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.white)
    }
}

// MARK: - Document Picker for CSV Export

struct DocumentPicker: UIViewControllerRepresentable {
    let transactionViewModel: TransactionViewModel
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let tempURL = transactionViewModel.createTempCSVFileURL()
        let picker = UIDocumentPickerViewController(forExporting: [tempURL])
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(transactionViewModel)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let transactionViewModel: TransactionViewModel
        
        init(_ transactionViewModel: TransactionViewModel) {
            self.transactionViewModel = transactionViewModel
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            transactionViewModel.showExportSuccessAlert()
        }
    }
}
