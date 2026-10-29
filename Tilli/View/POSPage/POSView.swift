//
//  POSView.swift
//  Tilli
//
//  Created by Peiyun on 2026/7/31.
//

import SwiftUI

struct POSView: View {

    @ObservedObject var viewModel: POSViewModel

    @State private var showCheckoutSheet = false
    @State private var checkoutCompleted = false
    @State private var showClearAlert = false

    /// 場次一律從 ViewModel 的共用快照取，View 不另外持有一份
    private var event: EventModel { viewModel.event }

    init(viewModel: POSViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Group {
            if viewModel.shouldShowEmptyState {
                emptyState
            } else {
                VStack(spacing: 0) {
                    productListSection
                    checkoutFooter
                }
            }
        }
        .background(DesignSystem.ColorToken.paper)
        .alert(isPresented: $viewModel.showAlert) {
            viewModel.createAlert()
        }
        // 確定要清除所有已選數量嗎？
        .alert("posClearAlertTitle", isPresented: $showClearAlert) {
            // 取消
            Button("commonCancel", role: .cancel) { }
            // 清除
            Button("posClearAlertConfirm", role: .destructive) {
                viewModel.clearAllQuantities()
            }
        }
        // 以下品項無法照原數量結帳（先通知，確定後才移除或降量）
        .alert("posInvalidCartTitle", isPresented: invalidLinesAlertBinding) {
            // 確定
            Button("commonConfirm", role: .cancel) {
                viewModel.confirmInvalidLines()
            }
        } message: {
            Text(viewModel.invalidLinesMessage)
        }
        .sheet(isPresented: $showCheckoutSheet) {
            CheckoutFlowView(
                isPresented: $showCheckoutSheet,
                checkoutCompleted: $checkoutCompleted,
                posViewModel: viewModel
            )
        }
        .onChange(of: checkoutCompleted) {
            // 先清購物車再重新載入：否則剛結帳的套餐行會對著已扣過的庫存被判成「庫存不足」而跳通知
            viewModel.clearAllQuantities()
            viewModel.loadProducts()
            DispatchQueue.main.async {
                checkoutCompleted = false
            }
        }
        .onAppear {
            viewModel.loadProducts()
        }
    }

    /// 有失效的套餐行或單點商品就顯示通知；關閉只能經「確定」（由 confirmInvalidLines 清空陣列）
    private var invalidLinesAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.hasInvalidLines },
            set: { _ in }
        )
    }

    // MARK: - 折扣（兩區各自單選，可同時一個百分比 + 一個減額）

    private var discountSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            if !viewModel.percentageDiscounts.isEmpty {
                discountRow(
                    title: "discountPercentageHeader",
                    discounts: viewModel.percentageDiscounts
                )
            }
            if !viewModel.amountDiscounts.isEmpty {
                discountRow(
                    title: "discountAmountHeader",
                    discounts: viewModel.amountDiscounts
                )
            }

            // 小計 → 折後，只在真的有折抵時顯示
            if viewModel.discountAmount() > 0 {
                HStack(spacing: DesignSystem.Spacing.xxs) {
                    Spacer()
                    Text(MoneyHelper.format(viewModel.subtotal(), currencyCode: event.currency))
                        .strikethrough()
                        .foregroundColor(DesignSystem.ColorToken.muted)
                    Image(systemName: "arrow.right")
                        .foregroundColor(DesignSystem.ColorToken.muted)
                    Text(MoneyHelper.format(viewModel.totalAmount(), currencyCode: event.currency))
                        .foregroundColor(DesignSystem.ColorToken.ink)
                }
                .font(DesignSystem.Typography.caption)
            }
        }
    }

    /// 一列折扣：左邊固定標籤，右邊 chip 可水平捲動
    private func discountRow(title: LocalizedStringKey, discounts: [DiscountModel]) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.muted)
                .fixedSize()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(discounts) { discount in
                        discountChip(discount)
                    }
                }
            }
        }
    }

    private func discountChip(_ discount: DiscountModel) -> some View {
        let isSelected = viewModel.isSelected(discount)
        return Button {
            viewModel.toggleDiscount(discount)
        } label: {
            // 減額折扣顯示成 -5 而不是 NT$5 —— chip 要短，幣別由下方總計表達
            Text(DiscountCalculator.deductionText(type: discount.type, value: discount.value))
                .font(DesignSystem.Typography.caption)
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(isSelected ? DesignSystem.ColorToken.ink : DesignSystem.ColorToken.quietFill)
                .foregroundColor(isSelected ? DesignSystem.ColorToken.paper : DesignSystem.ColorToken.ink)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                EmptyStateView(
                    systemImage: "cube.box",
                    // 尚無商品
                    title: String.localized("posEmptyTitle"),
                    // 請先在管理商品中新增商品
                    message: String.localized("posEmptyMessage"),
                    topPadding: 90
                )
            }
        }
    }

    // MARK: - Product List

    private var productListSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                if !viewModel.fixedBundles.isEmpty {
                    POSBundleSection(viewModel: viewModel)
                }

                ForEach(viewModel.activeCategories, id: \.id) { category in
                    let items = viewModel.getSortedProductsForCategory(category.id)
                    if !items.isEmpty {
                        categorySection(category: category, products: items)
                    }
                }
            }
            .padding(.top, DesignSystem.Spacing.md)
            // 點空白處收合展開中的增減元件
            .contentShape(Rectangle())
            .onTapGesture { viewModel.collapseControls() }
        }
        .collapsesControlsOnScroll(viewModel)
    }

    // MARK: - Category Section

    private func categorySection(category: CategoryModel, products: [ProductModel]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(category.name)
                .font(DesignSystem.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.ColorToken.ink)
                .padding(.horizontal, DesignSystem.Spacing.md)

            if viewModel.layoutMode == .list {
                ForEach(products) { product in
                    posProductCard(product)
                }
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.xs),
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.xs),
                    GridItem(.flexible())
                ], spacing: DesignSystem.Spacing.xs) {
                    ForEach(products) { product in
                        posGridCard(product)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
            }
        }
    }

    // MARK: - Checkout Footer

    private var checkoutFooter: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            if !event.discounts.isEmpty {
                discountSection
            }

            if let warning = viewModel.discountWarningMessage {
                HStack {
                    Spacer()
                    Image(systemName: "info.circle")
                        .foregroundColor(DesignSystem.ColorToken.alertRed)
                    Text(warning)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.alertRed)
                }
            }

            HStack {
                // 總計
                Text("posTotalLabel")
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.semibold)
                Spacer()
                Text(MoneyHelper.format(viewModel.totalAmount(), currencyCode: event.currency))
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.bold)
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                Button {
                    showClearAlert = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundColor(DesignSystem.ColorToken.ink)
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.ColorToken.quietFill)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
                }
                .disabled(viewModel.subtotal() == 0)

                Button {
                    // 有失效的套餐行就不開結帳（由 invalidBundleLines 通知使用者）
                    if viewModel.prepareCheckout() {
                        showCheckoutSheet = true
                    }
                } label: {
                    Text("posCheckoutButton")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.ColorToken.onButtonFilled)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        .background(viewModel.subtotal() > 0
                                    ? DesignSystem.ColorToken.buttonFilled
                                    : DesignSystem.ColorToken.muted)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
                }
                .disabled(viewModel.subtotal() == 0)
            }
        }
        .padding(DesignSystem.Spacing.md)
    }

    // MARK: - List Product Card

    private func posProductCard(_ product: ProductModel) -> some View {
        let isOutOfStock = viewModel.isOutOfStock(product)

        return HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            EntityImageView(
                imageData: product.imageData,
                imageURL: product.imageURL,
                entityId: product.id,
                entityType: .product,
                contentMode: .fill
            )
            .frame(width: 70, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
            .grayscale(isOutOfStock ? 1.0 : 0.0)
            .opacity(isOutOfStock ? 0.6 : 1.0)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(isOutOfStock ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
                        .lineLimit(1)

                    if let note = product.note, !note.isEmpty {
                        Text(note)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MoneyHelper.format(product.price, currencyCode: event.currency))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isOutOfStock ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)

                        if isOutOfStock {
                            // 無庫存
                            Text("posOutOfStock")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.alertRed)
                                .padding(.horizontal, DesignSystem.Spacing.xxs)
                                .padding(.vertical, 2)
                                .background(DesignSystem.ColorToken.alertRed.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            // 庫存: %d
                            Text("posStockCount \(product.stock)")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }
                    }

                    Spacer()

                    POSItemStepper(item: .product(product.id), viewModel: viewModel)
                }
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(isOutOfStock ? DesignSystem.ColorToken.quietFill : DesignSystem.ColorToken.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
        .shadow(
            color: DesignSystem.Shadow.cardColor,
            radius: DesignSystem.Shadow.cardRadius,
            x: DesignSystem.Shadow.cardX,
            y: DesignSystem.Shadow.cardY
        )
        .padding(.horizontal, DesignSystem.Spacing.md)
        .onTapGesture { tapCard(product, isOutOfStock: isOutOfStock) }
    }

    /// 點卡片不加入：收合展開中的增減元件；缺貨時提醒
    private func tapCard(_ product: ProductModel, isOutOfStock: Bool) {
        viewModel.collapseControls()
        if isOutOfStock { viewModel.showOutOfStockAlert(for: product.name) }
    }

    // MARK: - Grid Product Card

    private func posGridCard(_ product: ProductModel) -> some View {
        let isOutOfStock = viewModel.isOutOfStock(product)

        return VStack(alignment: .leading, spacing: 0) {
            EntityImageView(
                imageData: product.imageData,
                imageURL: product.imageURL,
                entityId: product.id,
                entityType: .product,
                contentMode: .fill
            )
            .aspectRatio(1, contentMode: .fill)
            .frame(minWidth: 0, maxWidth: .infinity)
            .clipped()
            .grayscale(isOutOfStock ? 1.0 : 0.0)
            .opacity(isOutOfStock ? 0.6 : 1.0)
            .overlay(alignment: .bottomTrailing) {
                POSItemStepper(item: .product(product.id), viewModel: viewModel)
                    .padding(DesignSystem.Spacing.xxs)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(product.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isOutOfStock ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
                    .lineLimit(1)

                Text(MoneyHelper.format(product.price, currencyCode: event.currency))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isOutOfStock ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)

                if isOutOfStock {
                    Text("posOutOfStock")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.alertRed)
                        .padding(.horizontal, DesignSystem.Spacing.xxs)
                        .padding(.vertical, 2)
                        .background(DesignSystem.ColorToken.alertRed.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text("posStockCount \(product.stock)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.xs)
        }
        .background(isOutOfStock ? DesignSystem.ColorToken.quietFill : DesignSystem.ColorToken.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
        .shadow(
            color: DesignSystem.Shadow.cardColor,
            radius: DesignSystem.Shadow.cardRadius,
            x: DesignSystem.Shadow.cardX,
            y: DesignSystem.Shadow.cardY
        )
        .onTapGesture { tapCard(product, isOutOfStock: isOutOfStock) }
    }
}

// MARK: - 增減元件（商品卡片、套餐卡片共用）

/// 把 `QuantityStepper` 接到 `POSViewModel`：展開狀態、能不能再加、加減都由 VM 決定
struct POSItemStepper: View {
    let item: CartItemID
    @ObservedObject var viewModel: POSViewModel

    var body: some View {
        QuantityStepper(
            quantity: viewModel.quantity(of: item),
            isExpanded: viewModel.expandedItem == item,
            canIncrement: viewModel.canIncrement(item),
            onIncrement: { viewModel.increment(item) },
            onDecrement: { viewModel.decrement(item) },
            onExpand: { viewModel.expand(item) }
        )
    }
}

private extension View {
    /// 開始捲動就收合展開中的增減元件
    @ViewBuilder
    func collapsesControlsOnScroll(_ viewModel: POSViewModel) -> some View {
        if #available(iOS 18.0, *) {
            onScrollPhaseChange { _, phase in
                if phase == .interacting { viewModel.collapseControls() }
            }
        } else {
            // iOS 17 沒有捲動狀態；用同時進行的拖曳手勢偵測，不影響捲動本身
            simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in
                viewModel.collapseControls()
            })
        }
    }
}
