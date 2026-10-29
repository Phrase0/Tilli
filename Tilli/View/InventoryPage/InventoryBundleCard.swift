//
//  InventoryBundleCard.swift
//  Tilli
//
//  管理商品頁的套餐／組合卡片。
//

import SwiftUI

struct InventoryBundleCard: View {
    let bundle: BundleModel
    let summary: String
    let warning: String?
    let currency: String
    let onEdit: () -> Void
    let onToggleDisabled: () -> Void
    let onDelete: () -> Void

    private var isFixed: Bool { bundle.kind == .fixed }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if isFixed {
                BundleImageView(bundleId: bundle.id)
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
                    .grayscale(bundle.isDisabled ? 1.0 : 0.0)
                    .opacity(bundle.isDisabled ? 0.6 : 1.0)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(bundle.name)
                        .font(DesignSystem.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(bundle.isDisabled ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
                        .lineLimit(1)

                    if bundle.isDisabled {
                        // 已下架
                        TagLabel("bundleMemberDisabledTag", onQuietFill: true)
                    }
                }

                Text(bundle.price.money(currency: currency))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)

                if !summary.isEmpty {
                    Text(summary)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                        .lineLimit(2)
                }

                if let warning {
                    HStack(spacing: DesignSystem.Spacing.xxs) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(warning)
                    }
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.alertRed)
                }
            }

            Spacer()

            menu
        }
        .padding(DesignSystem.Spacing.sm)
        .background(bundle.isDisabled ? DesignSystem.ColorToken.quietFill : DesignSystem.ColorToken.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Border.cardColor, lineWidth: DesignSystem.Border.cardWidth)
        )
        .shadow(
            color: DesignSystem.Shadow.cardColor,
            radius: DesignSystem.Shadow.cardRadius,
            x: DesignSystem.Shadow.cardX,
            y: DesignSystem.Shadow.cardY
        )
    }

    /// 編輯／下架（或上架）／刪除
    private var menu: some View {
        Menu {
            Button(action: onEdit) {
                // 編輯
                Label("inventoryMenuEdit", systemImage: "pencil")
            }
            Button(action: onToggleDisabled) {
                if bundle.isDisabled {
                    // 上架
                    Label("bundleMenuEnable", systemImage: "arrow.uturn.backward")
                } else {
                    // 下架
                    Label("inventoryMenuDisable", systemImage: "minus.circle")
                }
            }
            Button(role: .destructive, action: onDelete) {
                // 刪除
                Label("inventoryMenuDelete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .foregroundColor(DesignSystem.ColorToken.muted)
                .padding(DesignSystem.Spacing.xxs)
        }
    }
}
