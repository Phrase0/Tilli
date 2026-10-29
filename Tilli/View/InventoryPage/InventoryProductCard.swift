//
//  InventoryProductCard.swift
//  Tilli
//
//  管理商品頁的商品卡片（可展開看庫存與異動紀錄）。
//  已下架的商品留在原類別、原位置：卡片灰掉、名稱後標「已下架」，⋯ 選單為「編輯／上架」（與套餐／組合一致）。
//

import SwiftUI

struct InventoryProductCard: View {
    let item: InventoryProductItem
    let filteredChanges: [InventoryChangeModel]
    let currency: String
    let onToggle: () -> Void
    let actionType: ProductActionType
    let onEdit: () -> Void
    let onDisableOrDelete: () -> Void
    let onRestore: () -> Void

    private var isDisabled: Bool { item.product.isDisabled }

    var body: some View {
        VStack(spacing: 0) {
            // 商品基本資訊（可點擊展開）
            productHeader

            // 展開內容
            if item.isExpanded {
                Divider()
                    .padding(.horizontal, DesignSystem.Spacing.sm)

                expandedContent
            }
        }
        .background(isDisabled ? DesignSystem.ColorToken.quietFill : DesignSystem.ColorToken.cardSurface)
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

    // MARK: - 商品標題區

    private var productHeader: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Button(action: onToggle) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    // 商品圖片
                    productImage

                    // 商品資訊
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Text(item.product.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isDisabled ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
                                .lineLimit(1)

                            if isDisabled {
                                // 已下架
                                TagLabel("bundleMemberDisabledTag", onQuietFill: true)
                            }
                        }

                        Text(item.product.price.money(currency: currency))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    }

                    Spacer()

                    // 庫存狀態（收起時顯示）
                    if !item.isExpanded {
                        stockBadge
                    }
                }
            }
            .buttonStyle(.plain)

            // 編輯／下架（或上架）／刪除選單
            productMenu
        }
        .padding(DesignSystem.Spacing.sm)
    }

    private var productMenu: some View {
        Menu {
            // 編輯
            Button {
                onEdit()
            } label: {
                Label("inventoryMenuEdit", systemImage: "pencil")
            }

            if isDisabled {
                Button {
                    onRestore()
                } label: {
                    // 上架
                    Label("bundleMenuEnable", systemImage: "arrow.uturn.backward")
                }
            } else {
                switch actionType {
                case .disable:
                    Button {
                        onDisableOrDelete()
                    } label: {
                        // 下架
                        Label("inventoryMenuDisable", systemImage: "minus.circle")
                    }
                case .delete:
                    Button(role: .destructive) {
                        onDisableOrDelete()
                    } label: {
                        // 刪除
                        Label("inventoryMenuDelete", systemImage: "trash")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .foregroundColor(DesignSystem.ColorToken.muted)
                .padding(DesignSystem.Spacing.xxs)
        }
    }

    private var productImage: some View {
        EntityImageView(
            imageData: item.product.imageData,
            imageURL: item.product.imageURL,
            entityId: item.product.id,
            entityType: .product,
            contentMode: .fill
        )
        .frame(width: 70, height: 70)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
        .grayscale(isDisabled ? 1.0 : 0.0)
        .opacity(isDisabled ? 0.6 : 1.0)
    }

    /// 已下架的商品不提示低庫存（不會被賣），一律灰字
    private var showsLowStock: Bool { item.isLowStock && !isDisabled }

    private var stockBadge: some View {
        HStack(spacing: DesignSystem.Spacing.xxs) {
            if showsLowStock {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(DesignSystem.Typography.caption)
            }
            // %lld 件
            Text("inventoryChangePieceCount \(item.currentStock)")
                .font(DesignSystem.Typography.caption)
        }
        .foregroundColor(showsLowStock ? DesignSystem.ColorToken.alertRed : DesignSystem.ColorToken.muted)
    }

    // MARK: - 展開內容

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // 現有庫存卡片
            stockCard

            // 異動紀錄
            if !filteredChanges.isEmpty {
                changesSection
            } else {
                // 此時間範圍內無異動紀錄
                Text("inventoryChangeNoRecord")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)
            }
        }
        .padding(DesignSystem.Spacing.sm)
    }

    private var stockCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                // 現有庫存
                Text("inventoryChangeCurrentStock")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)

                HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xxs) {
                    Text("\(item.currentStock)")
                        .font(DesignSystem.Typography.display)
                        .foregroundColor(isDisabled ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
                    // 件
                    Text("inventoryChangeUnit")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
            }

            Spacer()

            // 庫存狀態標籤（已下架不顯示）
            if !isDisabled {
                HStack(spacing: DesignSystem.Spacing.xxs) {
                    Image(systemName: item.isLowStock ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    // 庫存不足 / 庫存正常
                    Text(item.isLowStock ? "inventoryChangeLowStock" : "inventoryChangeNormalStock")
                }
                .font(DesignSystem.Typography.caption)
                .foregroundColor(item.isLowStock ? DesignSystem.ColorToken.alertRed : DesignSystem.ColorToken.muted)
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xxs)
                .background(
                    Capsule()
                        .fill(item.isLowStock ? DesignSystem.ColorToken.alertRed.opacity(0.1) : DesignSystem.ColorToken.quietFill)
                )
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(isDisabled ? DesignSystem.ColorToken.cardSurface : DesignSystem.ColorToken.quietFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
    }

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // 異動紀錄
            Text("inventoryChangeRecords")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.muted)

            ForEach(filteredChanges) { change in
                changeRow(change)
            }
        }
    }

    private func changeRow(_ change: InventoryChangeModel) -> some View {
        HStack {
            // 原因標籤（顯示自定義原因或預設名稱）
            Text(change.displayReasonName)
                .font(DesignSystem.Typography.caption)
                .fontWeight(.medium)
                .foregroundColor(isDisabled ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
                .padding(.horizontal, DesignSystem.Spacing.xs)
                .padding(.vertical, DesignSystem.Spacing.xxs)
                .background(
                    Capsule()
                        .fill(isDisabled ? DesignSystem.ColorToken.cardSurface : DesignSystem.ColorToken.quietFill)
                )

            // 變化量
            Text(change.changeText)
                .font(DesignSystem.Typography.caption)
                .fontWeight(.semibold)
                .foregroundColor(isDisabled ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)

            // 來自〈套餐名〉
            if let bundleName = change.bundleName {
                Text("inventoryChangeFromBundle \(bundleName)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)
                    .lineLimit(1)
            }

            Spacer()

            // 時間
            Text(DateFormatter.dateTime.string(from: change.timestamp))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.muted)
        }
        .padding(.vertical, DesignSystem.Spacing.xxs)
    }
}
