//
//  TransactionDetailView.swift
//  Tilli
//
//  交易明細頁（唯讀）：資訊區 → 商品 → 優惠明細。
//  商品與優惠區塊由 `TransactionBreakdown` 從交易快照還原，版面沿用訂單摘要。
//  見 docs/superpowers/specs/2026-10-27-bundles-design.md §7.0。
//

import SwiftUI

struct TransactionDetailView: View {
    let transaction: TransactionModel
    @ObservedObject var viewModel: TransactionHistoryViewModel

    private var currency: String { transaction.currency }

    var body: some View {
        let breakdown = viewModel.breakdown(for: transaction)

        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                infoSection
                productSection(breakdown)
                discountSection(breakdown)
            }
            .padding(DesignSystem.Spacing.md)
        }
        .background(DesignSystem.ColorToken.paper)
        // 交易明細
        .navigationTitle("transactionDetailTitle")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 資訊區

    private var infoSection: some View {
        card {
            // 交易編號
            infoRow("transactionDetailId", value: viewModel.formatTransactionId(transaction.id.uuidString))

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
            infoRow("transactionDetailPaymentMethod", value: viewModel.paymentMethodText(transaction.paymentMethod))
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

            Text(viewModel.formatAmount(lineTotal, currency: currency))
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

                    Text(viewModel.formatAmount(item.price, currency: currency))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
            }

            Spacer()

            Text(viewModel.formatAmount(item.total, currency: currency))
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
                // 小計
                amountRow(Text("transactionDetailSubtotal"),
                          value: viewModel.formatAmount(breakdown.subtotal, currency: currency))

                ForEach(breakdown.comboLines, id: \.bundleId) { combo in
                    // 組合優惠 %@
                    amountRow(Text("transactionDetailComboLine \(combo.name)"),
                              value: viewModel.formatDeduction(combo.amount, currency: currency))
                }

                ForEach(breakdown.discounts) { discount in
                    amountRow(discountLabel(discount),
                              value: viewModel.formatDeduction(discount.amount, currency: currency))
                }

                Divider()

                totalRow(breakdown)
            }
        }
    }

    /// 「百分比折扣 10%」／「減額折扣 -25」（依型別選字在 DiscountCalculator，View 不 switch 折扣型別）
    private func discountLabel(_ discount: AppliedDiscount) -> Text {
        Text(DiscountCalculator.detailLineText(type: discount.type, value: discount.value))
    }

    private func amountRow(_ label: Text, value: String) -> some View {
        HStack {
            label
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.ColorToken.muted)
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.ColorToken.ink)
        }
    }

    /// 總計：大字；有優惠時折扣前金額劃線，並顯示「共省」
    private func totalRow(_ breakdown: TransactionBreakdown) -> some View {
        let hasSavings = breakdown.savings > 0

        return HStack(alignment: .firstTextBaseline) {
            // 總計
            Text("transactionDetailTotal")
                .font(DesignSystem.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.ColorToken.ink)

            Spacer()

            VStack(alignment: .trailing, spacing: DesignSystem.Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xs) {
                    if hasSavings {
                        Text(viewModel.formatAmount(breakdown.subtotal, currency: currency))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .strikethrough()
                    }
                    Text(viewModel.formatAmount(breakdown.total, currency: currency))
                        .font(DesignSystem.Typography.title2)
                        .fontWeight(.bold)
                        .foregroundColor(DesignSystem.ColorToken.ink)
                }

                if hasSavings {
                    // 共省 %@
                    Text("transactionDetailSavings \(viewModel.formatAmount(breakdown.savings, currency: currency))")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.marketGreen)
                }
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
