//
//  QuantityStepper.swift
//  Tilli
//
//  商品／套餐的增減元件（收銀頁列表與格狀卡片、訂單摘要共用）。
//  數量 0：只有一個 ＋；有數量未展開：圓形只顯示數量（點了展開）；展開：白底膠囊「− 數量 ＋」。
//  不能再加時 ＋ 淡化停用，大小不變。
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
    /// 到上限的 ＋：淡化、點了沒反應（不提醒）
    private let disabledOpacity: Double = 0.55

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
                .foregroundColor(canIncrement ? DesignSystem.ColorToken.onButtonFilled : DesignSystem.ColorToken.muted.opacity(disabledOpacity))
                .frame(width: circleSize, height: circleSize)
                // 停用時白底淡陰影（同展開膠囊），疊在佔位圖或照片上仍看得出是按鈕
                .background(
                    Circle()
                        .fill(canIncrement ? DesignSystem.ColorToken.buttonFilled : DesignSystem.ColorToken.cardSurface)
                        .shadow(color: canIncrement ? .clear : DesignSystem.Shadow.cardColor, radius: 4, x: 0, y: 1)
                )
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
                    .background(Circle().fill(showsTrash ? DesignSystem.ColorToken.quietFill : DesignSystem.ColorToken.buttonFilled))
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
                    .background(Circle().fill(canIncrement ? DesignSystem.ColorToken.buttonFilled : DesignSystem.ColorToken.quietFill))
                    .opacity(canIncrement ? 1 : disabledOpacity)
            }
            .buttonStyle(.plain)
            .disabled(!canIncrement)
            // 增加
            .accessibilityLabel(Text("quantityStepperIncrease"))
        }
        .padding(.horizontal, DesignSystem.Spacing.xxs)
        .frame(height: circleSize)
        // 卡片白底＋淡陰影：疊在灰色佔位圖或照片上都看得出膠囊
        .background(
            Capsule()
                .fill(DesignSystem.ColorToken.cardSurface)
                .shadow(color: DesignSystem.Shadow.cardColor, radius: 4, x: 0, y: 1)
        )
    }
}
