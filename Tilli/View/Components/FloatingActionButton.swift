//
//  FloatingActionButton.swift
//  Tilli
//
//  Created by Peiyun on 2026/9/4.
//

import SwiftUI

/// 右下角圓形新增按鈕，供場次頁、商品管理頁等需要「新增」入口的頁面共用。
/// 使用方式：放在 `ZStack(alignment: .bottomTrailing)` 內，呼叫端自行決定顯示/隱藏時機
/// （例如選取模式時隱藏）。
struct FloatingActionButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(DesignSystem.ColorToken.onButtonFilled)
                .frame(width: 56, height: 56)
                .background(DesignSystem.ColorToken.buttonFilled)
                .clipShape(Circle())
                .shadow(
                    color: DesignSystem.Shadow.cardColor,
                    radius: DesignSystem.Shadow.cardRadius * 2,
                    x: DesignSystem.Shadow.cardX,
                    y: DesignSystem.Shadow.cardY * 2
                )
        }
        .padding(DesignSystem.Spacing.lg)
    }
}
