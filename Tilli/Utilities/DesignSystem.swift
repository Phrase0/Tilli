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
        static let md: CGFloat = 24
        static let pill: CGFloat = 999
    }

    enum ColorToken {
        static let ink = Color.primary
        static let paper = Color(.systemGroupedBackground)
        static let cardSurface = Color(.systemBackground)
        static let muted = Color.secondary
        static let quietFill = Color(.systemGray6)
        static let marketGreen = Color(red: 0x34 / 255.0, green: 0xC7 / 255.0, blue: 0x59 / 255.0)
        static let marketGreenLight = Color(red: 0xD8 / 255.0, green: 0xF5 / 255.0, blue: 0xDE / 255.0)
        static let alertRed = Color(.systemRed)
    }

    enum Typography {
        static let display = Font.system(size: 34, weight: .bold)
        static let title1 = Font.system(size: 28, weight: .bold)
        static let title2 = Font.system(size: 22, weight: .semibold)
        static let body = Font.system(size: 16, weight: .regular)
        static let caption = Font.system(size: 12, weight: .regular)
    }

    enum Shadow {
        static let cardColor = Color.black.opacity(0.05)
        static let cardRadius: CGFloat = 2
        static let cardX: CGFloat = 0
        static let cardY: CGFloat = 1
    }
}
