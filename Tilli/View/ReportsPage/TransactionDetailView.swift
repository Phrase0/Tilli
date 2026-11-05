//
//  TransactionDetailView.swift
//  Tilli
//
//  交易明細頁：（已作廢卡片）→ 資訊區 → 商品 → 優惠明細 →（作廢交易按鈕）。
//  商品與優惠區塊由 `TransactionBreakdown` 從交易快照還原，版面與訂單摘要相同；作廢後快照照常顯示。
//  「作廢交易」開作廢視窗（`VoidTransactionView`）；視窗關閉後（onDismiss）重新讀取作廢狀態。
//

import SwiftUI

struct TransactionDetailView: View {
    @StateObject private var viewModel: TransactionDetailViewModel

    @State private var showVoidSheet = false

    init(transaction: TransactionModel, dataSource: EventDataSource) {
        _viewModel = StateObject(wrappedValue: TransactionDetailViewModel(transaction: transaction, dataSource: dataSource))
    }

    private var transaction: TransactionModel { viewModel.transaction }

    var body: some View {
        let breakdown = viewModel.breakdown

        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                if let voidRecord = viewModel.voidRecord {
                    voidedCard(voidRecord)
                }
                infoSection
                productSection(breakdown)
                discountSection(breakdown)
                if !viewModel.isVoided {
                    voidButton
                }
            }
            .padding(DesignSystem.Spacing.md)
        }
        .background(DesignSystem.ColorToken.paper)
        // 交易明細
        .navigationTitle("transactionDetailTitle")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showVoidSheet, onDismiss: { viewModel.refreshVoidState() }) {
            VoidTransactionView(transaction: transaction, dataSource: viewModel.dataSource)
        }
    }

    // MARK: - 已作廢卡片

    private func voidedCard(_ record: TransactionVoidModel) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            // 已作廢
            Text("voidedTitle")
                .font(DesignSystem.Typography.body)
                .fontWeight(.bold)
                .foregroundColor(DesignSystem.ColorToken.alertRed)

            // 作廢時間
            infoRow("voidedAt", value: DateFormatter.dateTime.string(from: record.voidedAt))
            // 原因
            infoRow("voidedReason", value: record.reason.displayName)
            if let note = record.note {
                // 說明
                infoRow("voidedNote", value: note)
            }
            // 庫存
            infoRow("voidedRestock", value: viewModel.restockText)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.ColorToken.cardSurface)
        // 左側警示紅細條
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DesignSystem.ColorToken.alertRed)
                .frame(width: DesignSystem.Spacing.xxs)
        }
        .cornerRadius(DesignSystem.Radius.md)
        .shadow(
            color: DesignSystem.Shadow.cardColor,
            radius: DesignSystem.Shadow.cardRadius,
            x: DesignSystem.Shadow.cardX,
            y: DesignSystem.Shadow.cardY
        )
    }

    // MARK: - 作廢交易按鈕（靜謐填色底＋警示紅字）

    private var voidButton: some View {
        Button {
            showVoidSheet = true
        } label: {
            // 作廢交易
            Text("voidTransactionButton")
                .font(DesignSystem.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.ColorToken.alertRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.md)
                .background(DesignSystem.ColorToken.quietFill)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 資訊區

    private var infoSection: some View {
        card {
            // 交易編號
            infoRow("transactionDetailId", value: viewModel.transactionNumber)

            if let occurredAt = transaction.occurredAt {
                // 補記帳：實際發生時間＋記錄時間
                // 實際發生時間
                infoRow("transactionDetailOccurredAt", value: DateFormatter.dateTime.string(from: occurredAt))
                // 記錄時間
                infoRow("transactionDetailRecordedAt", value: DateFormatter.dateTime.string(from: transaction.timestamp))
            } else {
                // 時間
                infoRow("transactionDetailTime", value: DateFormatter.dateTime.string(from: transaction.timestamp))
            }

            // 付款方式
            infoRow("transactionDetailPaymentMethod", value: viewModel.paymentMethodText)
            // 場次
            infoRow("transactionDetailEvent", value: transaction.eventTitle)
        }
    }

    private func infoRow(_ titleKey: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(titleKey)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.ColorToken.muted)
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.ColorToken.ink)
        }
    }

    // MARK: - 商品

    private func productSection(_ breakdown: TransactionBreakdown) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // 商品
            sectionTitle("transactionDetailProducts")

            card {
                ForEach(Array(breakdown.rows.enumerated()), id: \.offset) { _, row in
                    switch row {
                    case let .bundle(_, name, quantity, lineTotal, memberNames):
                        bundleRow(name: name, quantity: quantity, lineTotal: lineTotal, memberNames: memberNames)
                    case let .product(item, isInCombo):
                        productRow(item, isInCombo: isInCombo)
                    }
                }
            }
        }
    }

    private func bundleRow(name: String, quantity: Int, lineTotal: Decimal, memberNames: [String]) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(name)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.ColorToken.ink)
                    // 套餐
                    TagLabel("transactionDetailBundleTag")
                }

                // × %lld
                Text("transactionDetailQuantity \(quantity)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)

                Text(memberNames.joinedAsBundleMembers())
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)
            }

            Spacer()

            Text(viewModel.formatAmount(lineTotal))
                .font(DesignSystem.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.ColorToken.ink)
        }
    }

    private func productRow(_ item: SummaryItemModel, isInCombo: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(item.name)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.ColorToken.ink)
                    if isInCombo {
                        // 含組合
                        TagLabel("transactionDetailInComboTag")
                    }
                }

                HStack(spacing: DesignSystem.Spacing.xs) {
                    // × %lld
                    Text("transactionDetailQuantity \(item.quantity)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)

                    Text(viewModel.formatAmount(item.price))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
            }

            Spacer()

            Text(viewModel.formatAmount(item.total))
                .font(DesignSystem.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.ColorToken.ink)
        }
    }

    // MARK: - 優惠明細

    private func discountSection(_ breakdown: TransactionBreakdown) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // 優惠明細
            sectionTitle("transactionDetailDiscounts")

            card {
                DiscountBreakdownView(
                    subtotal: breakdown.subtotal,
                    comboLines: breakdown.comboLines.map {
                        .init(id: $0.bundleId, name: $0.name, amount: $0.amount, groupCount: $0.groupCount, isCancelled: false)
                    },
                    discounts: breakdown.discounts,
                    total: breakdown.total,
                    currency: viewModel.currency
                )
            }
        }
    }

    // MARK: - 共用外觀

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(DesignSystem.Typography.caption)
            .foregroundColor(DesignSystem.ColorToken.muted)
            .padding(.horizontal, DesignSystem.Spacing.xxs)
    }

    /// 與交易紀錄卡片相同的卡片外觀
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            content()
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
}
