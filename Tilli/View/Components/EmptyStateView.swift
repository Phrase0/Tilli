//
//  EmptyStateView.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/16.
//

import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    let topPadding: CGFloat

    init(systemImage: String, title: String, message: String, topPadding: CGFloat = 100) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.topPadding = topPadding
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundColor(DesignSystem.ColorToken.muted)

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(DesignSystem.ColorToken.muted)

            Text(message)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, topPadding)
        .frame(maxWidth: .infinity)
    }
}
