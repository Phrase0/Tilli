//
//  POSView.swift
//  Tilli
//
//  Created by Peiyun on 2026/7/31.
//

import SwiftUI

struct POSView: View {

    let event: EventModel

    @StateObject private var viewModel: POSViewModel
    @EnvironmentObject var productRepository: ProductRepository

    @State private var showCheckoutSheet = false
    @State private var checkoutCompleted = false
    @State private var showClearAlert = false
    @State private var eventState: EventModel

    init(event: EventModel) {
        self.event = event
        _viewModel = StateObject(wrappedValue: POSViewModel(event: .constant(event)))
        _eventState = State(initialValue: event)
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
        // 收銀
        .navigationTitle("posTitle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.layoutMode = viewModel.layoutMode == .list ? .grid : .list
                    }
                } label: {
                    Image(systemName: viewModel.layoutMode == .list ? "square.grid.2x2" : "list.bullet")
                }
            }
        }
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
        .sheet(isPresented: $showCheckoutSheet) {
            CheckoutFlowView(
                isPresented: $showCheckoutSheet,
                checkoutCompleted: $checkoutCompleted,
                event: $eventState,
                selectedItems: viewModel.selectedProductsWithQuantity(),
                totalAmount: viewModel.totalAmount(),
                selectedDiscount: viewModel.effectiveDiscount()
            )
        }
        .onChange(of: checkoutCompleted) {
            viewModel.loadProducts()
            viewModel.clearAllQuantities()
            DispatchQueue.main.async {
                checkoutCompleted = false
            }
        }
        .onAppear {
            viewModel.updateDataManagers(productRepository: productRepository)
            viewModel.loadProducts()
        }
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
                ForEach(event.categories.filter { !$0.isDisabled }.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.id) { category in
                    let items = viewModel.getSortedProductsForCategory(category.id)
                    if !items.isEmpty {
                        categorySection(category: category, products: items)
                    }
                }

                if !viewModel.disabledProducts.isEmpty {
                    disabledSection
                }
            }
            .padding(.top, DesignSystem.Spacing.md)
        }
    }

    // MARK: - Category Section

    private func categorySection(category: CategoryModel, products: [ProductModel]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Button {
                viewModel.toggleCategoryExpansion(category.id)
            } label: {
                HStack {
                    Text(category.name)
                        .font(DesignSystem.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.ColorToken.ink)
                        .padding(.horizontal, DesignSystem.Spacing.md)

                    Spacer()

                    Image(systemName: viewModel.isCategoryExpanded(category.id) ? "chevron.up" : "chevron.down")
                        .foregroundColor(DesignSystem.ColorToken.muted)
                        .font(DesignSystem.Typography.caption)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                }
            }
            .buttonStyle(PlainButtonStyle())

            if viewModel.isCategoryExpanded(category.id) {
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
    }

    // MARK: - Disabled Products Section

    private var disabledSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.showDisabledProducts.toggle()
                }
            } label: {
                HStack {
                    // 下架商品
                    Text("posDisabledHeader")
                        .font(DesignSystem.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                        .padding(.horizontal, DesignSystem.Spacing.md)

                    Spacer()

                    Image(systemName: viewModel.showDisabledProducts ? "chevron.up" : "chevron.down")
                        .foregroundColor(DesignSystem.ColorToken.muted)
                        .font(DesignSystem.Typography.caption)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                }
            }
            .buttonStyle(PlainButtonStyle())

            if viewModel.showDisabledProducts {
                if viewModel.layoutMode == .list {
                    ForEach(viewModel.disabledProducts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { product in
                        posDisabledCard(product)
                    }
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: DesignSystem.Spacing.xs),
                        GridItem(.flexible(), spacing: DesignSystem.Spacing.xs),
                        GridItem(.flexible())
                    ], spacing: DesignSystem.Spacing.xs) {
                        ForEach(viewModel.disabledProducts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { product in
                            posDisabledGridCard(product)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                }
            }
        }
    }

    // MARK: - Checkout Footer

    private var checkoutFooter: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            if !event.discounts.isEmpty {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    // 折扣
                    Text("posDiscountLabel")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.ColorToken.muted)

                    Menu {
                        Button {
                            viewModel.selectedDiscountId = nil
                        } label: {
                            HStack {
                                Text("- -")
                                if viewModel.selectedDiscountId == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        ForEach(event.discounts) { discount in
                            Button {
                                viewModel.selectedDiscountId = discount.id
                            } label: {
                                HStack {
                                    Text(discount.displayText(currency: event.currency))
                                    if viewModel.selectedDiscountId == discount.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text(viewModel.selectedDiscount?.displayText(currency: event.currency) ?? "- -")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.ColorToken.ink)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .frame(maxWidth: .infinity)
                        .background(DesignSystem.ColorToken.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
                    }
                }
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
                    showCheckoutSheet = true
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
        let currentQty = viewModel.quantity(for: product)

        return HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            SyncableImageView(
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

                    quantityControls(product: product, isOutOfStock: isOutOfStock, currentQty: currentQty)
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
        .onTapGesture {
            if isOutOfStock { viewModel.showOutOfStockAlert(for: product.name) }
        }
    }

    // MARK: - Grid Product Card

    private func posGridCard(_ product: ProductModel) -> some View {
        let isOutOfStock = viewModel.isOutOfStock(product)
        let currentQty = viewModel.quantity(for: product)

        return VStack(alignment: .leading, spacing: 0) {
            SyncableImageView(
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

                HStack {
                    Spacer()
                    quantityControls(product: product, isOutOfStock: isOutOfStock, currentQty: currentQty, compact: true)
                    Spacer()
                }
            }
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
        .onTapGesture {
            if isOutOfStock { viewModel.showOutOfStockAlert(for: product.name) }
        }
    }

    // MARK: - Disabled Product Card (List)

    private func posDisabledCard(_ product: ProductModel) -> some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            SyncableImageView(
                imageData: product.imageData,
                imageURL: product.imageURL,
                entityId: product.id,
                entityType: .product,
                contentMode: .fill
            )
            .frame(width: 70, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
            .grayscale(1.0)
            .opacity(0.6)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignSystem.ColorToken.muted)
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
                            .foregroundColor(DesignSystem.ColorToken.muted)

                        // 庫存: %d
                        Text("posStockCount \(product.stock)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    }

                    Spacer()

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(DesignSystem.ColorToken.quietFill)
                        Text("0")
                            .font(.system(size: 14))
                            .foregroundColor(DesignSystem.ColorToken.muted)
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(DesignSystem.ColorToken.quietFill)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(DesignSystem.ColorToken.quietFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
        .padding(.horizontal, DesignSystem.Spacing.md)
    }

    // MARK: - Disabled Product Card (Grid)

    private func posDisabledGridCard(_ product: ProductModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SyncableImageView(
                imageData: product.imageData,
                imageURL: product.imageURL,
                entityId: product.id,
                entityType: .product,
                contentMode: .fill
            )
            .aspectRatio(1, contentMode: .fill)
            .frame(minWidth: 0, maxWidth: .infinity)
            .clipped()
            .grayscale(1.0)
            .opacity(0.6)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(product.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(DesignSystem.ColorToken.muted)
                    .lineLimit(1)

                Text(MoneyHelper.format(product.price, currencyCode: event.currency))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.ColorToken.muted)

                Text("posStockCount \(product.stock)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)

                HStack {
                    Spacer()
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(DesignSystem.ColorToken.quietFill)
                        Text("0")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DesignSystem.ColorToken.muted)
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(DesignSystem.ColorToken.quietFill)
                    }
                    Spacer()
                }
            }
            .padding(DesignSystem.Spacing.xs)
        }
        .background(DesignSystem.ColorToken.quietFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
        .shadow(
            color: DesignSystem.Shadow.cardColor,
            radius: DesignSystem.Shadow.cardRadius,
            x: DesignSystem.Shadow.cardX,
            y: DesignSystem.Shadow.cardY
        )
    }

    // MARK: - Quantity Controls

    private func quantityControls(product: ProductModel, isOutOfStock: Bool, currentQty: Int, compact: Bool = false) -> some View {
        let iconSize: CGFloat = compact ? 20 : 22
        return HStack(spacing: compact ? DesignSystem.Spacing.xs : DesignSystem.Spacing.sm) {
            Button {
                viewModel.decreaseQuantity(for: product)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: iconSize))
                    .foregroundColor(isOutOfStock || currentQty == 0
                                    ? DesignSystem.ColorToken.quietFill
                                    : DesignSystem.ColorToken.ink.opacity(0.6))
            }
            .disabled(isOutOfStock || currentQty == 0)

            Text("\(currentQty)")
                .font(.system(size: 14, weight: .medium))
                .frame(minWidth: 18)
                .foregroundColor(isOutOfStock ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)

            Button {
                viewModel.increaseQuantity(for: product)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: iconSize))
                    .foregroundColor(isOutOfStock || currentQty >= product.stock
                                    ? DesignSystem.ColorToken.quietFill
                                    : DesignSystem.ColorToken.ink.opacity(0.6))
            }
            .disabled(isOutOfStock || currentQty >= product.stock)
        }
    }
}
