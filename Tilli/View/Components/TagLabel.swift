//
//  TagLabel.swift
//  Tilli
//
//  小標籤（已下架／套餐／含組合）：Caption、靜音灰字、滿膠囊（中性狀態標籤樣式）。
//

import SwiftUI

struct TagLabel: View {
    let key: LocalizedStringKey
    /// 卡片本身是灰底（例如已下架的卡片）時，標籤用卡片白底才看得出來
    var onQuietFill = false

    init(_ key: LocalizedStringKey, onQuietFill: Bool = false) {
        self.key = key
        self.onQuietFill = onQuietFill
    }

    var body: some View {
        Text(key)
            .font(DesignSystem.Typography.caption)
            .foregroundColor(DesignSystem.ColorToken.muted)
            .padding(.horizontal, DesignSystem.Spacing.xs)
            .padding(.vertical, DesignSystem.Spacing.xxs)
            .background(Capsule().fill(onQuietFill ? DesignSystem.ColorToken.cardSurface : DesignSystem.ColorToken.quietFill))
    }
}
