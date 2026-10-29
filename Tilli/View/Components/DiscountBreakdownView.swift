//
//  DiscountBreakdownView.swift
//  Tilli
//
//  「優惠明細」卡片內容（交易明細、訂單摘要共用）：小計 → 每條組合優惠 → 百分比／減額折扣 → 大字總計
//  （有優惠時折扣前金額劃線並顯示「共省」）。外層卡片與區塊標題由各頁自己放。
//

import SwiftUI

struct DiscountBreakdownView: View {
    struct ComboLine: Identifiable {
        let id: UUID
        let name: String
        let amount: Decimal
        /// 本筆交易已取消（訂單摘要）：名稱劃線、不顯示金額、按鈕為「恢復」
        let isCancelled: Bool
    }

    let subtotal: Decimal
    let comboLines: [ComboLine]
    let discounts: [AppliedDiscount]
    let total: Decimal
    let savings: Decimal
    let currency: String
    /// nil：唯讀（交易明細）；非 nil：組合行右側顯示「取消」／「恢復」
    var onToggleCombo: ((UUID) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            // 小計
            amountRow(Text("transactionDetailSubtotal"), value: format(subtotal))

            ForEach(comboLines) { combo in
                comboRow(combo)
            }

            ForEach(discounts) { discount in
                // 「百分比折扣 10%」／「減額折扣 -25」（依型別選字在 DiscountCalculator）
                amountRow(Text(DiscountCalculator.detailLineText(type: discount.type, value: discount.value)),
                          value: formatDeduction(discount.amount))
            }

            Divider()

            totalRow
        }
    }

    // MARK: - 列

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

    private func comboRow(_ combo: ComboLine) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if combo.isCancelled {
                Text(combo.name)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.ColorToken.muted)
                    .strikethrough()
                    .lineLimit(1)
                Spacer()
            } else {
                // 組合優惠 %@
                Text("transactionDetailComboLine \(combo.name)")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.ColorToken.muted)
                    .lineLimit(1)
                Spacer()
                Text(formatDeduction(combo.amount))
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.ColorToken.ink)
            }

            if let onToggleCombo {
                Button {
                    onToggleCombo(combo.id)
                } label: {
                    // 恢復／取消
                    Text(combo.isCancelled ? "checkoutComboRestore" : "checkoutComboCancel")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.ink)
                        .padding(.horizontal, DesignSystem.Spacing.xs)
                        .padding(.vertical, DesignSystem.Spacing.xxs)
                        .background(Capsule().fill(DesignSystem.ColorToken.quietFill))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 總計：大字；有優惠時折扣前金額劃線，並顯示「共省」
    private var totalRow: some View {
        let hasSavings = savings > 0

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
                        Text(format(subtotal))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .strikethrough()
                    }
                    Text(format(total))
                        .font(DesignSystem.Typography.title2)
                        .fontWeight(.bold)
                        .foregroundColor(DesignSystem.ColorToken.ink)
                }

                if hasSavings {
                    // 共省 %@
                    Text("transactionDetailSavings \(format(savings))")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.marketGreen)
                }
            }
        }
    }

    // MARK: - 金額格式

    private func format(_ amount: Decimal) -> String {
        MoneyHelper.format(amount, currencyCode: currency)
    }

    private func formatDeduction(_ amount: Decimal) -> String {
        "-" + format(amount)
    }
}
