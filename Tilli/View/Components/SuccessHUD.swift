//
//  SuccessHUD.swift
//  Tilli
//
//  畫面正中間的成功方塊：綠色勾勾＋標題＋重點金額。只負責外觀，顯示多久由呼叫端控制。
//  目前用在 POS 頁「付款完成」；綠色依 DESIGN.md 只用於結帳完成的成功勾勾。
//

import SwiftUI

struct SuccessHUD: View {
    let title: LocalizedStringKey
    /// 標題下方的重點金額（已格式化）
    let detail: String

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(DesignSystem.ColorToken.marketGreen)

            Text(title)
                .font(DesignSystem.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.ColorToken.ink)

            Text(detail)
                .font(DesignSystem.Typography.display)
                .foregroundColor(DesignSystem.ColorToken.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(minWidth: 160)
        .background(DesignSystem.ColorToken.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.lg))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }
}
