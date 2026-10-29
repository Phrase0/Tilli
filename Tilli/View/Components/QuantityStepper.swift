//
//  QuantityStepper.swift
//  Tilli
//
//  商品／套餐的增減元件（收銀頁列表與格狀卡片、訂單摘要共用）。
//  數量 0：只有一個 ＋；有數量未展開：圓形只顯示數量（點了展開）；展開：膠囊「− 數量 ＋」。
//

import SwiftUI

struct QuantityStepper: View {
    let quantity: Int
    let isExpanded: Bool
    let canIncrement: Bool
    /// 數量 1 時 − 顯示垃圾桶（訂單摘要）
    var trashAtOne: Bool = false
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    let onExpand: () -> Void

    private let circleSize: CGFloat = 28
    private let buttonSize: CGFloat = 22

    var body: some View {
        content
            // 停用的按鈕不接點擊，會穿透到外層卡片；整個元件自己吃掉點擊
            .contentShape(Rectangle())
            .onTapGesture { }
    }

    @ViewBuilder
    private var content: some View {
        if quantity == 0 {
            plusCircle
        } else if !isExpanded {
            countCircle
        } else {
            expandedPill
        }
    }

    // MARK: - 三種外觀

    private var plusCircle: some View {
        Button(action: onIncrement) {
            Image(systemName: "plus")
                .font(DesignSystem.Typography.body.weight(.bold))
                .foregroundColor(canIncrement ? DesignSystem.ColorToken.onButtonFilled : DesignSystem.ColorToken.muted)
                .frame(width: circleSize, height: circleSize)
                .background(Circle().fill(canIncrement ? DesignSystem.ColorToken.buttonFilled : DesignSystem.ColorToken.quietFill))
        }
        .buttonStyle(.plain)
        .disabled(!canIncrement)
        // 增加
        .accessibilityLabel(Text("quantityStepperIncrease"))
    }

    private var countCircle: some View {
        Button(action: onExpand) {
            Text("\(quantity)")
                .font(DesignSystem.Typography.body.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundColor(DesignSystem.ColorToken.onButtonFilled)
                .frame(width: circleSize, height: circleSize)
                .background(Circle().fill(DesignSystem.ColorToken.buttonFilled))
        }
        .buttonStyle(.plain)
    }

    private var expandedPill: some View {
        let showsTrash = trashAtOne && quantity == 1
        return HStack(spacing: DesignSystem.Spacing.xs) {
            Button(action: onDecrement) {
                Image(systemName: showsTrash ? "trash" : "minus")
                    .font(DesignSystem.Typography.caption.weight(.bold))
                    .foregroundColor(showsTrash ? DesignSystem.ColorToken.alertRed : DesignSystem.ColorToken.onButtonFilled)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Circle().fill(showsTrash ? DesignSystem.ColorToken.cardSurface : DesignSystem.ColorToken.buttonFilled))
            }
            .buttonStyle(.plain)
            // 移除／減少
            .accessibilityLabel(Text(showsTrash ? "quantityStepperRemove" : "quantityStepperDecrease"))

            Text("\(quantity)")
                .font(DesignSystem.Typography.body.weight(.semibold))
                .monospacedDigit()
                .foregroundColor(DesignSystem.ColorToken.ink)
                .frame(minWidth: 18)

            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .font(DesignSystem.Typography.caption.weight(.bold))
                    .foregroundColor(canIncrement ? DesignSystem.ColorToken.onButtonFilled : DesignSystem.ColorToken.muted)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Circle().fill(canIncrement ? DesignSystem.ColorToken.buttonFilled : DesignSystem.ColorToken.cardSurface))
            }
            .buttonStyle(.plain)
            .disabled(!canIncrement)
            // 增加
            .accessibilityLabel(Text("quantityStepperIncrease"))
        }
        .padding(.horizontal, DesignSystem.Spacing.xxs)
        .frame(height: circleSize)
        .background(Capsule().fill(DesignSystem.ColorToken.quietFill))
    }
}
