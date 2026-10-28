//
//  POSBundleSection.swift
//  Tilli
//
//  收銀頁最上方的「套餐」區塊（設計 §4.5）。卡片樣式沿用 POSView 的
//  posProductCard（列表）／posGridCard（格狀）；不可賣時灰掉、顯示原因、不能加入。
//

import SwiftUI

struct POSBundleSection: View {

    @ObservedObject var viewModel: POSViewModel

    private var currency: String { viewModel.event.currency }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            // 套餐
            Text("posBundleSection")
                .font(DesignSystem.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.ColorToken.ink)
                .padding(.horizontal, DesignSystem.Spacing.md)

            if viewModel.layoutMode == .list {
                ForEach(viewModel.fixedBundles) { bundle in
                    listCard(bundle)
                }
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.xs),
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.xs),
                    GridItem(.flexible())
                ], spacing: DesignSystem.Spacing.xs) {
                    ForEach(viewModel.fixedBundles) { bundle in
                        gridCard(bundle)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
            }
        }
    }

    // MARK: - 狀態

    /// 不可賣的原因文字；可賣時為 nil
    private func unavailableText(_ bundle: BundleModel) -> String? {
        if case .failure(let reason) = viewModel.availability(of: bundle) {
            return reason.displayText
        }
        return nil
    }

    /// 成員名稱（「大福、抹茶、紅豆」），當作卡片副標
    private func memberNames(_ bundle: BundleModel) -> String {
        bundle.productIds
            .compactMap { id in viewModel.products.first { $0.id == id }?.name }
            .joined(separator: "、")
    }

    /// 照片：BundleImageStore 的本機照片；沒有時與無照片商品相同的 placeholder
    private func image(_ bundle: BundleModel) -> some View {
        BundleImageView(bundleId: bundle.id)
    }

    // MARK: - 列表卡片（同 posProductCard）

    private func listCard(_ bundle: BundleModel) -> some View {
        let reason = unavailableText(bundle)
        let isUnavailable = reason != nil
        let members = memberNames(bundle)

        return HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            image(bundle)
                .frame(width: 70, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
                .grayscale(isUnavailable ? 1.0 : 0.0)
                .opacity(isUnavailable ? 0.6 : 1.0)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bundle.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(isUnavailable ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
                        .lineLimit(1)

                    if !members.isEmpty {
                        Text(members)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MoneyHelper.format(bundle.price, currencyCode: currency))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isUnavailable ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)

                        if let reason {
                            reasonBadge(reason)
                        }
                    }

                    Spacer()

                    quantityControls(bundle, isUnavailable: isUnavailable)
                }
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(isUnavailable ? DesignSystem.ColorToken.quietFill : DesignSystem.ColorToken.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
        .shadow(
            color: DesignSystem.Shadow.cardColor,
            radius: DesignSystem.Shadow.cardRadius,
            x: DesignSystem.Shadow.cardX,
            y: DesignSystem.Shadow.cardY
        )
        .padding(.horizontal, DesignSystem.Spacing.md)
        .onTapGesture { tapCard(bundle, isUnavailable: isUnavailable) }
    }

    // MARK: - 格狀卡片（同 posGridCard）

    private func gridCard(_ bundle: BundleModel) -> some View {
        let reason = unavailableText(bundle)
        let isUnavailable = reason != nil

        return VStack(alignment: .leading, spacing: 0) {
            image(bundle)
                .aspectRatio(1, contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity)
                .clipped()
                .grayscale(isUnavailable ? 1.0 : 0.0)
                .opacity(isUnavailable ? 0.6 : 1.0)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(bundle.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isUnavailable ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
                    .lineLimit(1)

                Text(MoneyHelper.format(bundle.price, currencyCode: currency))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isUnavailable ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)

                if let reason {
                    reasonBadge(reason)
                        .lineLimit(1)
                }

                HStack {
                    Spacer()
                    quantityControls(bundle, isUnavailable: isUnavailable, compact: true)
                    Spacer()
                }
            }
            .padding(DesignSystem.Spacing.xs)
        }
        .background(isUnavailable ? DesignSystem.ColorToken.quietFill : DesignSystem.ColorToken.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
        .shadow(
            color: DesignSystem.Shadow.cardColor,
            radius: DesignSystem.Shadow.cardRadius,
            x: DesignSystem.Shadow.cardX,
            y: DesignSystem.Shadow.cardY
        )
        .onTapGesture { tapCard(bundle, isUnavailable: isUnavailable) }
    }

    // MARK: - 共用元件

    /// 點卡片即加入一份（設計 §4.5）；不可賣時不能點
    private func tapCard(_ bundle: BundleModel, isUnavailable: Bool) {
        guard !isUnavailable else { return }
        viewModel.addBundle(bundle)
    }

    /// 與商品卡片的「無庫存」標籤同樣式
    private func reasonBadge(_ text: String) -> some View {
        Text(text)
            .font(DesignSystem.Typography.caption)
            .foregroundColor(DesignSystem.ColorToken.alertRed)
            .padding(.horizontal, DesignSystem.Spacing.xxs)
            .padding(.vertical, 2)
            .background(DesignSystem.ColorToken.alertRed.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// 不可賣時 ＋ 停用；已在購物車的份數仍可用 － 減少
    private func quantityControls(_ bundle: BundleModel, isUnavailable: Bool, compact: Bool = false) -> some View {
        let currentQty = viewModel.bundleQuantity(bundle.id)
        let iconSize: CGFloat = compact ? 20 : 22
        return HStack(spacing: compact ? DesignSystem.Spacing.xs : DesignSystem.Spacing.sm) {
            Button {
                viewModel.removeBundle(bundle.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: iconSize))
                    .foregroundColor(currentQty == 0
                                    ? DesignSystem.ColorToken.quietFill
                                    : DesignSystem.ColorToken.ink.opacity(0.6))
            }
            .disabled(currentQty == 0)

            Text("\(currentQty)")
                .font(.system(size: 14, weight: .medium))
                .frame(minWidth: 18)
                .foregroundColor(isUnavailable ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)

            Button {
                viewModel.addBundle(bundle)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: iconSize))
                    .foregroundColor(isUnavailable
                                    ? DesignSystem.ColorToken.quietFill
                                    : DesignSystem.ColorToken.ink.opacity(0.6))
            }
            .disabled(isUnavailable)
        }
    }
}
