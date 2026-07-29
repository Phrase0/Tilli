//
//  DesignSystem.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/28.
//

import SwiftUI

enum DesignSystem {
    enum Spacing {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
    }

    enum Radius {
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let pill: CGFloat = 999
    }

    enum Border {
        static let cardColor = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.08)
                : UIColor.black.withAlphaComponent(0.06)
        })
        static let cardWidth: CGFloat = 0.5
    }

    enum ColorToken {
        static let ink = Color.primary
        static let paper = Color(.systemGroupedBackground)
        static let cardSurface = Color(.secondarySystemGroupedBackground)
        static let muted = Color.secondary
        static let quietFill = Color(.systemGray5)
        static let alertRed = Color(.systemRed)

        // MARK: - 需手動適配深色模式的顏色
        static let marketGreen = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x30/255, green: 0xD1/255, blue: 0x58/255, alpha: 1)
                : UIColor(red: 0x34/255, green: 0xC7/255, blue: 0x59/255, alpha: 1)
        })
        static let marketGreenLight = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x13/255, green: 0x32/255, blue: 0x1C/255, alpha: 1)
                : UIColor(red: 0xD8/255, green: 0xF5/255, blue: 0xDE/255, alpha: 1)
        })
    }

    enum Typography {
        static let display = Font.system(size: 34, weight: .bold)
        static let title1 = Font.system(size: 28, weight: .bold)
        static let title2 = Font.system(size: 22, weight: .semibold)
        static let body = Font.system(size: 16, weight: .regular)
        static let caption = Font.system(size: 12, weight: .regular)
    }

    enum Shadow {
        static let cardColor = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.06)
                : UIColor.black.withAlphaComponent(0.05)
        })
        static let cardRadius: CGFloat = 2
        static let cardX: CGFloat = 0
        static let cardY: CGFloat = 1
    }
}
