//
//  TransactionHistoryView.swift
//  Tilli
//
//  Created by Peiyun on 2025/8/27.
//

import SwiftUI

struct TransactionHistoryView: View {
    @ObservedObject var transactionViewModel: TransactionHistoryViewModel
    let event: EventModel
    let timeRange: ReportTimeRange?
    /// 點卡片要開的交易明細，由 EventWorkspaceView 持有並宣告 navigationDestination
    @Binding var selectedTransaction: TransactionModel?

    init(transactionViewModel: TransactionHistoryViewModel,
         event: EventModel,
         timeRange: ReportTimeRange? = nil,
         selectedTransaction: Binding<TransactionModel?>) {
        self.transactionViewModel = transactionViewModel
        self.event = event
        self.timeRange = timeRange
        self._selectedTransaction = selectedTransaction
    }

    var body: some View {
        VStack(spacing: 0) {
            // 排序和篩選工具列
            sortFilterToolbar
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(DesignSystem.ColorToken.paper)

            // 交易列表
            if transactionViewModel.filteredTransactions.isEmpty {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.sm) {
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
                    if transactionViewModel.sortType == .time {
                        // 時間排序：按日期分組。一般 VStack：展開一整天的交易時 LazyVStack 會估錯未顯示的高度，捲動位置跳動
                        VStack(spacing: DesignSystem.Spacing.md) {
                            ForEach(transactionViewModel.filteredGroupedTransactions) { dailyGroup in
                                dailyTransactionSection(dailyGroup)
                            }
                        }
                        .padding(DesignSystem.Spacing.md)
                    } else {
                        // 金額排序：打平列表、沒有展開收合，交易多時用 LazyVStack 只建看得到的卡片
                        LazyVStack(spacing: DesignSystem.Spacing.md) {
                            ForEach(transactionViewModel.sortedFlatTransactions) { transaction in
                                transactionCard(transaction)
                            }
                        }
                        .padding(DesignSystem.Spacing.md)
                    }
                }
            }
        }
        .refreshable {
            transactionViewModel.loadData(timeRange: timeRange)
        }
        .onAppear {
            transactionViewModel.loadData(timeRange: timeRange)
        }
        .background(DesignSystem.ColorToken.paper)
    }

    // MARK: - 排序和篩選工具列

    private var sortFilterToolbar: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // 時間排序按鈕
            sortButton(type: .time, titleKey: "transactionSortTime")

            // 金額排序按鈕
            sortButton(type: .amount, titleKey: "transactionSortAmount")

            Spacer()

            // 篩選選擇器（Menu 樣式）
            Menu {
                // 全部
                Button("transactionFilterAll") {
                    transactionViewModel.paymentFilter = .all
                }
                // 現金
                Button("transactionFilterCash") {
                    transactionViewModel.paymentFilter = .cash
                }
                // 電子支付
                Button("transactionFilterEPayment") {
                    transactionViewModel.paymentFilter = .ePayment
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.xxs) {
                    Text(transactionViewModel.paymentFilter.label)
                        .font(.subheadline)
                        .frame(width: 100, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(DesignSystem.Typography.caption)
                }
                .foregroundColor(transactionViewModel.hasActiveFilter ? DesignSystem.ColorToken.onButtonFilled : DesignSystem.ColorToken.ink)
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xxs)
                .background(
                    transactionViewModel.hasActiveFilter
                        ? DesignSystem.ColorToken.buttonFilled
                        : DesignSystem.ColorToken.quietFill
                )
                .cornerRadius(DesignSystem.Radius.sm)
            }
        }
    }

    /// 排序按鈕
    private func sortButton(type: TransactionSortType, titleKey: LocalizedStringKey) -> some View {
        let isSelected = transactionViewModel.sortType == type

        return Button(action: {
            transactionViewModel.toggleSort(type)
        }) {
            HStack(spacing: DesignSystem.Spacing.xxs) {
                Text(titleKey)
                    .font(.subheadline)

                if isSelected {
                    Image(systemName: transactionViewModel.sortAscending ? "arrow.up" : "arrow.down")
                        .font(DesignSystem.Typography.caption)
                }
            }
            .foregroundColor(isSelected ? DesignSystem.ColorToken.onButtonFilled : DesignSystem.ColorToken.ink)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xxs)
            .background(isSelected ? DesignSystem.ColorToken.buttonFilled : DesignSystem.ColorToken.quietFill)
            .cornerRadius(DesignSystem.Radius.sm)
        }
    }

    // MARK: - 空狀態訊息

    /// 根據時間範圍顯示不同的空狀態訊息
    private var emptyStateMessage: (title: String, message: String) {
        if let timeRange = timeRange {
            return (
                title: String.localized("transactionEmptyRangeTitle"),
                message: String.localized("transactionEmptyRangeMessage \(timeRange.displayText)")
            )
        } else {
            return (
                title: String.localized("transactionEmptyTitle"),
                message: String.localized("transactionEmptyMessage")
            )
        }
    }

    // MARK: - 按日分組視圖

    /// 每日交易區塊
    private func dailyTransactionSection(_ dailyGroup: DailyTransactionGroup) -> some View {
        let isExpanded = transactionViewModel.isDailyGroupExpanded(dailyGroup.date)

        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // 日期標題（整個區域可點擊）
            Button(action: {
                transactionViewModel.toggleDailyGroupExpansion(dailyGroup.date)
            }) {
                HStack {
                    Text(dailyGroup.dateText)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.ColorToken.ink)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(transactionViewModel.formatAmount(dailyGroup.totalAmount))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignSystem.ColorToken.ink)

                        // N 筆交易
                        Text("transactionDailyCount \(dailyGroup.count)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    }

                    // 沿用現有的 chevron 圖示
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(DesignSystem.ColorToken.muted)
                        .font(DesignSystem.Typography.caption)
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(DesignSystem.ColorToken.quietFill)
                .cornerRadius(DesignSystem.Radius.sm)
            }
            .buttonStyle(PlainButtonStyle())  // 沿用現有樣式

            // 該日的交易列表（條件顯示）
            if isExpanded {
                VStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(dailyGroup.transactions) { transaction in
                        transactionCard(transaction)
                    }
                }
            }
        }
    }

    /// 交易卡片：點整張卡片 push 進交易明細頁（destination 在 EventWorkspaceView）。
    /// 不用 NavigationLink(value:)：場次工作區是以 navigationDestination(item:) 推進來的，
    /// 兩種導航混用時 SwiftUI 會把明細頁排到工作區下面並重建工作區。
    private func transactionCard(_ transaction: TransactionModel) -> some View {
        Button {
            selectedTransaction = transaction
        } label: {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                // 第一行：交易編號和支付方式
                HStack {
                    Text(transactionViewModel.formatTransactionId(transaction.id.uuidString))
                        .font(.subheadline)
                        .foregroundColor(DesignSystem.ColorToken.ink)

                    Spacer()

                    Text(transactionViewModel.paymentMethodText(transaction.paymentMethod))
                        .font(DesignSystem.Typography.caption)
                        .padding(.horizontal, DesignSystem.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(DesignSystem.ColorToken.quietFill)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                        .cornerRadius(DesignSystem.Radius.sm)
                }

                // 第二行：日期時間
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: DesignSystem.Spacing.xxs) {
                            Text(DateFormatter.dateTime.string(from: transaction.displayDate))
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.muted)

                            // 補記帳標記
                            if transaction.isBackdated {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }

                        // 共 N 項商品
                        Text("transactionItemCount \(transactionViewModel.itemCount(for: transaction))")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    }

                    Spacer()

                    // 折扣細節只在交易明細頁顯示，卡片只放總額
                    HStack(alignment: .center, spacing: DesignSystem.Spacing.xs) {
                        Text(transactionViewModel.formatAmount(transaction.totalAmount))
                            .font(.headline)
                            .bold()
                            .foregroundColor(DesignSystem.ColorToken.ink)

                        Image(systemName: "chevron.right")
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .font(DesignSystem.Typography.caption)
                    }
                }
            }
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.ColorToken.cardSurface)
            .cornerRadius(DesignSystem.Radius.md)
            .shadow(
                color: DesignSystem.Shadow.cardColor,
                radius: DesignSystem.Shadow.cardRadius,
                x: DesignSystem.Shadow.cardX,
                y: DesignSystem.Shadow.cardY
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

}
