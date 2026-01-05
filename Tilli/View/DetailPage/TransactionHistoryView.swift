//
//  TransactionHistoryView.swift
//  Tilli
//
//  Created by Peiyun on 2025/8/27.
//

import SwiftUI

struct TransactionHistoryView: View {
    @ObservedObject var transactionViewModel: TransactionViewModel
    @Binding var session: SessionModel
    let timeRange: ReportTimeRange?

    init(transactionViewModel: TransactionViewModel,
         session: Binding<SessionModel>,
         timeRange: ReportTimeRange? = nil) {
        self.transactionViewModel = transactionViewModel
        self._session = session
        self.timeRange = timeRange
    }

    var body: some View {
        VStack(spacing: 0) {
            // 排序和篩選工具列
            sortFilterToolbar
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))

            // 交易列表
            if transactionViewModel.filteredTransactions.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        EmptyStateView(
                            systemImage: "list.clipboard",
                            title: emptyStateMessage.title,
                            message: emptyStateMessage.message,
                            topPadding: 85
                        )
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if transactionViewModel.sortType == .time {
                            // 時間排序：按日期分組顯示
                            ForEach(transactionViewModel.filteredGroupedTransactions) { dailyGroup in
                                dailyTransactionSection(dailyGroup)
                            }
                        } else {
                            // 金額排序：打平列表顯示（使用相同的卡片樣式）
                            ForEach(transactionViewModel.sortedFlatTransactions) { transaction in
                                transactionCard(transaction)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .refreshable {
            transactionViewModel.loadData(timeRange: timeRange)
        }
        .onAppear {
            transactionViewModel.loadData(timeRange: timeRange)
        }
        .background(Color(.systemGray6))
        .alert("CSV 導出成功", isPresented: $transactionViewModel.showingExportAlert) {
            Button("確定") { }
        } message: {
            Text("交易明細已成功導出為 CSV 檔案")
        }
    }

    // MARK: - 排序和篩選工具列

    private var sortFilterToolbar: some View {
        HStack(spacing: 12) {
            // 時間排序按鈕
            sortButton(type: .time, label: "時間")

            // 金額排序按鈕
            sortButton(type: .amount, label: "金額")

            Spacer()

            // 篩選選擇器（Menu 樣式）
            Menu {
                Button("全部") {
                    transactionViewModel.paymentFilter = .all
                }
                Button("現金") {
                    transactionViewModel.paymentFilter = .cash
                }
                Button("電子支付") {
                    transactionViewModel.paymentFilter = .ePayment
                }
            } label: {
                HStack(spacing: 4) {
                    Text(transactionViewModel.paymentFilter.label)
                        .font(.subheadline)
                        .frame(width: 100, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(transactionViewModel.hasActiveFilter ? .blue : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    transactionViewModel.hasActiveFilter
                        ? Color.blue.opacity(0.1)
                        : Color(.systemGray5)
                )
                .cornerRadius(8)
            }
        }
    }

    /// 排序按鈕
    private func sortButton(type: TransactionSortType, label: String) -> some View {
        let isSelected = transactionViewModel.sortType == type

        return Button(action: {
            transactionViewModel.toggleSort(type)
        }) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.subheadline)

                if isSelected {
                    Image(systemName: transactionViewModel.sortAscending ? "arrow.up" : "arrow.down")
                        .font(.caption)
                }
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.systemGray5))
            .cornerRadius(8)
        }
    }

    // MARK: - 空狀態訊息
    
    /// 根據時間範圍顯示不同的空狀態訊息
    private var emptyStateMessage: (title: String, message: String) {
        if let timeRange = timeRange {
            return (
                title: "此時間段尚無交易記錄",
                message: "在 \(timeRange.displayText) 期間沒有交易記錄"
            )
        } else {
            return (
                title: "尚無交易記錄", 
                message: "完成結帳後，交易記錄會顯示在這裡"
            )
        }
    }
    
    // MARK: - 按日分組視圖

    /// 每日交易區塊
    private func dailyTransactionSection(_ dailyGroup: DailyTransactionGroup) -> some View {
        let isExpanded = transactionViewModel.isDailyGroupExpanded(dailyGroup.date)
        
        return VStack(alignment: .leading, spacing: 8) {
            // 日期標題（整個區域可點擊）
            Button(action: {
                transactionViewModel.toggleDailyGroupExpansion(dailyGroup.date)
            }) {
                HStack {
                    Text(dailyGroup.dateText)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(transactionViewModel.formatAmount(dailyGroup.totalAmount))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        
                        Text("\(dailyGroup.count) 筆交易")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // 沿用現有的 chevron 圖示
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray5))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())  // 沿用現有樣式
            
            // 該日的交易列表（條件顯示）
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(dailyGroup.transactions) { transaction in
                        transactionCard(transaction)
                    }
                }
            }
        }
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
                            HStack(spacing: 4) {
                                Text(DateFormatter.dateTime.string(from: transaction.displayDate))
                                    .font(.caption)
                                    .foregroundColor(.gray)

                                // 補記帳標記
                                if transaction.isBackdated {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }

                            Text("共 \(transaction.items.count) 項商品")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        
                        Spacer()

                        HStack(alignment: .center, spacing: 8)  {
                            // 顯示折扣標籤
                            if let discountType = transaction.discountType,
                               let discountValue = transaction.discountValue {
                                Text(formatDiscount(type: discountType, value: discountValue))
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }

                            Text(transactionViewModel.formatAmount(transaction.totalAmount))
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
                    HStack(spacing: 8) {
                        Text("商品")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("類別")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text("單價")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text("數量")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text("小計")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
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
        HStack(spacing: 8) {
            // 商品名稱
            Text(item.name)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 類別
            Text(item.category)
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            // 單價
            Text(transactionViewModel.formatAmount(item.price))
                .font(.caption)
                .foregroundColor(.blue)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            // 數量
            Text("\(item.quantity)")
                .font(.caption)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .center)

            // 小計
            Text(transactionViewModel.formatAmount(item.total))
                .font(.caption)
                .bold()
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    // MARK: - Helper Methods

    /// 格式化折扣顯示文字
    private func formatDiscount(type: DiscountType, value: Decimal) -> String {
        switch type {
        case .percentage:
            return "\(value)%"
        case .amount:
            return "-\(value)"
        }
    }
}

