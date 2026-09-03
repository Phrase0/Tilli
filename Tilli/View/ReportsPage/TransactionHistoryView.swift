//
//  TransactionHistoryView.swift
//  Tilli
//
//  Created by Peiyun on 2025/8/27.
//

import SwiftUI

struct TransactionHistoryView: View {
    @ObservedObject var transactionViewModel: TransactionHistoryViewModel
    @Binding var event: EventModel
    let timeRange: ReportTimeRange?

    init(transactionViewModel: TransactionHistoryViewModel,
         event: Binding<EventModel>,
         timeRange: ReportTimeRange? = nil) {
        self.transactionViewModel = transactionViewModel
        self._event = event
        self.timeRange = timeRange
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
                    LazyVStack(spacing: DesignSystem.Spacing.md) {
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
                    .padding(DesignSystem.Spacing.md)
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

    private func transactionCard(_ transaction: TransactionModel) -> some View {
        let isExpanded = transactionViewModel.isTransactionExpanded(transaction.id)

        return VStack(spacing: 0) {
            // 交易總覽卡片
            Button(action: {
                transactionViewModel.toggleTransactionExpansion(transaction.id)
            }) {
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
                            Text("transactionItemCount \(transaction.items.count)")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }

                        Spacer()

                        HStack(alignment: .center, spacing: DesignSystem.Spacing.xs) {
                            // 顯示折扣標籤
                            if let discountType = transaction.discountType,
                               let discountValue = transaction.discountValue {
                                Text(formatDiscount(type: discountType, value: discountValue))
                                    .font(DesignSystem.Typography.caption)
                                    .padding(.horizontal, DesignSystem.Spacing.xxs)
                                    .padding(.vertical, 2)
                                    .background(DesignSystem.ColorToken.quietFill)
                                    .foregroundColor(DesignSystem.ColorToken.ink)
                                    .cornerRadius(DesignSystem.Radius.sm)
                            }

                            Text(transactionViewModel.formatAmount(transaction.totalAmount))
                                .font(.headline)
                                .bold()
                                .foregroundColor(DesignSystem.ColorToken.ink)

                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .foregroundColor(DesignSystem.ColorToken.muted)
                                .font(DesignSystem.Typography.caption)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.md)
            }
            .buttonStyle(PlainButtonStyle())

            // 交易明細（展開時顯示）
            if isExpanded {
                VStack(spacing: 0) {
                    // 表頭
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        // 商品
                        Text("transactionHeaderProduct")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // 類別
                        Text("transactionHeaderCategory")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .frame(maxWidth: .infinity, alignment: .center)

                        // 單價
                        Text("transactionHeaderUnitPrice")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .frame(maxWidth: .infinity, alignment: .center)

                        // 數量
                        Text("transactionHeaderQuantity")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .frame(maxWidth: .infinity, alignment: .center)

                        // 小計
                        Text("transactionHeaderSubtotal")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(DesignSystem.ColorToken.quietFill)

                    // 商品明細列表
                    ForEach(transaction.items) { item in
                        transactionItemRow(item)
                    }
                }
            }
        }
        .background(DesignSystem.ColorToken.cardSurface)
        .cornerRadius(DesignSystem.Radius.md)
        .shadow(
            color: DesignSystem.Shadow.cardColor,
            radius: DesignSystem.Shadow.cardRadius,
            x: DesignSystem.Shadow.cardX,
            y: DesignSystem.Shadow.cardY
        )
    }

    private func transactionItemRow(_ item: SummaryItemModel) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            // 商品名稱
            Text(item.name)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 類別
            Text(item.category)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            // 單價
            Text(transactionViewModel.formatAmount(item.price))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            // 數量
            Text("\(item.quantity)")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.ink)
                .frame(maxWidth: .infinity, alignment: .center)

            // 小計
            Text(transactionViewModel.formatAmount(item.total))
                .font(DesignSystem.Typography.caption)
                .bold()
                .foregroundColor(DesignSystem.ColorToken.ink)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.ColorToken.cardSurface)
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
