//
//  DiscountBreakdownView.swift
//  Tilli
//
//  「優惠明細」卡片內容（交易明細、訂單摘要共用）：小計 → 每條組合優惠 → 百分比／減額折扣 → 大字總計
//  （有優惠時折扣前金額劃線）。外層卡片與區塊標題由各頁自己放。
//  組合取消／恢復時列的位置與高度不變，只換金額樣式與按鈕文字。
//

import SwiftUI

struct DiscountBreakdownView: View {
    struct ComboLine: Identifiable {
        let id: UUID
        let name: String
        /// 折抵金額；已取消時為恢復後可省的金額
        let amount: Decimal
        /// 組數；舊交易沒有快照時為 nil（不顯示「× N 組」）
        let groupCount: Int?
        /// 本筆交易已取消（訂單摘要）：名稱與金額劃線、灰字，按鈕為「恢復」
        let isCancelled: Bool
    }

    let subtotal: Decimal
    let comboLines: [ComboLine]
    let discounts: [AppliedDiscount]
    let total: Decimal
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
            comboLabel(combo)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.ColorToken.muted)
                .strikethrough(combo.isCancelled)
                .lineLimit(1)
            Spacer()
            Text(formatDeduction(combo.amount))
                .font(DesignSystem.Typography.body)
                .foregroundColor(combo.isCancelled ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
                .strikethrough(combo.isCancelled)

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

    /// 「組合優惠 名稱 × N 組」；沒有組數時「組合優惠 名稱」
    private func comboLabel(_ combo: ComboLine) -> Text {
        if let count = combo.groupCount {
            // 組合優惠 %@ × %lld 組
            return Text("discountBreakdownComboGroups \(combo.name) \(count)")
        }
        // 組合優惠 %@
        return Text("transactionDetailComboLine \(combo.name)")
    }

    /// 總計：大字；有優惠時折扣前金額劃線
    private var totalRow: some View {
        let hasSavings = MoneyHelper.subtract(subtotal, total) > 0

        return HStack(alignment: .firstTextBaseline) {
            // 總計
            Text("transactionDetailTotal")
                .font(DesignSystem.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.ColorToken.ink)

            Spacer()

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
