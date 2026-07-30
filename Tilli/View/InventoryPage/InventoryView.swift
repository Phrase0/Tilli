//
//  InventoryView.swift
//  Tilli
//
//  Created by Peiyun on 2026/7/30.
//

import SwiftUI

struct InventoryView: View {

    let event: EventModel

    @StateObject private var viewModel: ProductViewModel
    @EnvironmentObject var productRepository: ProductRepository
    @EnvironmentObject var transactionDataManager: TransactionRepository
    @EnvironmentObject var eventDataManager: EventRepository

    @State private var editingProduct: ProductModel?
    @State private var showAddProduct = false
    @State private var showInventoryChange = false

    init(event: EventModel) {
        self.event = event
        _viewModel = StateObject(wrappedValue: ProductViewModel(event: .constant(event)))
    }

    var body: some View {
        Group {
            if viewModel.shouldShowEmptyState {
                emptyState
            } else {
                productList
            }
        }
        .background(DesignSystem.ColorToken.paper)
        // 管理商品
        .navigationTitle("inventoryTitle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    AddNewProductView(event: event) {
                        viewModel.loadProducts()
                    }
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(DesignSystem.ColorToken.ink)
                }
            }
        }
        .alert(isPresented: $viewModel.showAlert) {
            viewModel.createAlert()
        }
        .navigationDestination(isPresented: $showAddProduct) {
            if let product = editingProduct {
                AddNewProductView(event: event, productToEdit: product) {
                    viewModel.loadProducts()
                    editingProduct = nil
                }
            }
        }
        .navigationDestination(isPresented: $showInventoryChange) {
            InventoryChangeView(event: event)
        }
        .onAppear {
            viewModel.updateDataManagers(
                transactionDataManager: transactionDataManager,
                eventDataManager: eventDataManager,
                productRepository: productRepository
            )
            viewModel.loadProducts()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                EmptyStateView(
                    systemImage: "shippingbox",
                    // 尚無商品
                    title: String(localized: "inventoryEmptyTitle"),
                    // 點擊右上角 + 新增商品
                    message: String(localized: "inventoryEmptyMessage"),
                    topPadding: 90
                )
            }
        }
    }

    // MARK: - Product List

    private var productList: some View {
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
            .padding(.bottom, DesignSystem.Spacing.lg)
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
                        inventoryProductCard(product)
                    }
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignSystem.Spacing.md) {
                        ForEach(products) { product in
                            inventoryGridCard(product)
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
                    Text("inventoryDisabledHeader")
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
                        disabledProductCard(product)
                    }
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignSystem.Spacing.md) {
                        ForEach(viewModel.disabledProducts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { product in
                            disabledGridCard(product)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                }
            }
        }
    }

    // MARK: - List Product Card (No quantity +/-)

    private func inventoryProductCard(_ product: ProductModel) -> some View {
        let isOutOfStock = viewModel.isOutOfStock(product)

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

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
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

                    Spacer()

                    productMenu(for: product)
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MoneyHelper.format(product.price, currencyCode: event.currency))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isOutOfStock ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)

                        if isOutOfStock {
                            // 無庫存
                            Text("inventoryOutOfStock")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.alertRed)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DesignSystem.ColorToken.alertRed.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            // 庫存: %d
                            Text("inventoryStockCount \(product.stock)")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.ColorToken.muted)
                        }
                    }

                    Spacer()
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
    }

    // MARK: - Grid Product Card (No quantity +/-)

    private func inventoryGridCard(_ product: ProductModel) -> some View {
        let isOutOfStock = viewModel.isOutOfStock(product)

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

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack(alignment: .top) {
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

                    Spacer()

                    productMenu(for: product)
                }

                Text(MoneyHelper.format(product.price, currencyCode: event.currency))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isOutOfStock ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)

                Spacer(minLength: 4)

                if isOutOfStock {
                    // 無庫存
                    Text("inventoryOutOfStock")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.alertRed)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignSystem.ColorToken.alertRed.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    // 庫存: %d
                    Text("inventoryStockCount \(product.stock)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
            }
            .padding(10)
        }
        .background(isOutOfStock ? DesignSystem.ColorToken.quietFill : DesignSystem.ColorToken.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
        .shadow(
            color: DesignSystem.Shadow.cardColor,
            radius: DesignSystem.Shadow.cardRadius,
            x: DesignSystem.Shadow.cardX,
            y: DesignSystem.Shadow.cardY
        )
    }

    // MARK: - Disabled Product Card (List)

    private func disabledProductCard(_ product: ProductModel) -> some View {
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

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
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

                    Spacer()

                    Menu {
                        // 復原
                        Button("inventoryRestore") {
                            viewModel.handleRestoreAction(for: product.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .padding(4)
                    }
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MoneyHelper.format(product.price, currencyCode: event.currency))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DesignSystem.ColorToken.muted)

                        // 庫存: %d
                        Text("inventoryStockCount \(product.stock)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                    }

                    Spacer()
                }
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(DesignSystem.ColorToken.quietFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
        .padding(.horizontal, DesignSystem.Spacing.md)
    }

    // MARK: - Disabled Product Card (Grid)

    private func disabledGridCard(_ product: ProductModel) -> some View {
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

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack(alignment: .top) {
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

                    Spacer()

                    Menu {
                        // 復原
                        Button("inventoryRestore") {
                            viewModel.handleRestoreAction(for: product.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                            .rotationEffect(.degrees(90))
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .padding(4)
                    }
                }

                Text(MoneyHelper.format(product.price, currencyCode: event.currency))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.ColorToken.muted)

                Spacer(minLength: 4)

                // 庫存: %d
                Text("inventoryStockCount \(product.stock)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.ColorToken.muted)
            }
            .padding(10)
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

    // MARK: - Product Menu

    @ViewBuilder
    private func productMenu(for product: ProductModel) -> some View {
        Menu {
            // 編輯
            Button {
                editingProduct = product
                showAddProduct = true
            } label: {
                // 編輯
                Label("inventoryMenuEdit", systemImage: "pencil")
            }

            Button {
                showInventoryChange = true
            } label: {
                // 庫存異動
                Label("inventoryMenuStockChange", systemImage: "arrow.up.arrow.down")
            }

            switch viewModel.getActionType(for: product.id) {
            case .disable:
                Button {
                    viewModel.handleDisableAction(for: product.id)
                } label: {
                    // 下架
                    Label("inventoryMenuDisable", systemImage: "minus.circle")
                }
            case .delete:
                Button(role: .destructive) {
                    viewModel.handleDeleteAction(for: product.id)
                } label: {
                    // 刪除
                    Label("inventoryMenuDelete", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .foregroundColor(DesignSystem.ColorToken.muted)
                .padding(4)
        }
    }
}
