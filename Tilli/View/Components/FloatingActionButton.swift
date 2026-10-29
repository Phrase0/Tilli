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
            FloatingActionButtonLabel(systemImage: systemImage)
        }
        .padding(DesignSystem.Spacing.lg)
    }
}

/// 右下角圓形新增選單：點了從按鈕旁彈出原生 Menu（選單會貼著按鈕，不像 confirmationDialog 跑到別處）。
/// 外觀與 `FloatingActionButton` 相同。
struct FloatingActionMenu<MenuContent: View>: View {
    let systemImage: String
    @ViewBuilder let content: () -> MenuContent

    var body: some View {
        Menu(content: content) {
            FloatingActionButtonLabel(systemImage: systemImage)
        }
        .padding(DesignSystem.Spacing.lg)
    }
}

/// 圓形新增按鈕的外觀，按鈕版與選單版共用
private struct FloatingActionButtonLabel: View {
    let systemImage: String

    var body: some View {
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
}
