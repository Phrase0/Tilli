//
//  InventoryView.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/12.
//

import SwiftUI

struct InventoryView: View {
    let event: EventModel

    @StateObject private var viewModel: InventoryViewModel
    @EnvironmentObject var productRepository: ProductRepository
    @EnvironmentObject var inventoryChangeRepository: InventoryChangeRepository
    @EnvironmentObject var transactionDataManager: TransactionRepository
    @EnvironmentObject var eventDataManager: EventRepository
    @Environment(\.dismiss) private var dismiss

    @State private var timeRange: ReportTimeRange
    @State private var searchText = ""
    @State private var showShareSheet = false
    @State private var editingProduct: ProductModel?
    @State private var showAddProduct = false

    init(event: EventModel) {
        self.event = event
        self._viewModel = StateObject(wrappedValue: InventoryViewModel(event: event))
        self._timeRange = State(initialValue: ReportTimeRange(event: event))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 時間範圍選擇器
            ReportTimeRangeSelector(event: viewModel.event, selectedRange: $timeRange)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.top, DesignSystem.Spacing.xs)
            // 商品列表（按類別分組）
            productList
        }
        .background(DesignSystem.ColorToken.paper)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
//        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜尋商品")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(DesignSystem.ColorToken.ink)
                }
            }
            ToolbarItem(placement: .principal) {
                Text(viewModel.event.title)
                    .font(.headline)
                    .foregroundColor(DesignSystem.ColorToken.ink)
                    .lineLimit(1)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        viewModel.prepareExport(type: .all)
                        showShareSheet = true
                    } label: {
                        // 全部匯出
                        Label("inventoryChangeExportAll", systemImage: "square.and.arrow.up.on.square")
                    }

                    Divider()

                    Button {
                        viewModel.prepareExport(type: .summary)
                        showShareSheet = true
                    } label: {
                        // 庫存總覽
                        Label("inventoryChangeExportSummary", systemImage: "list.bullet.rectangle")
                    }

                    Button {
                        viewModel.prepareExport(type: .detail)
                        showShareSheet = true
                    } label: {
                        // 庫存異動明細
                        Label("inventoryChangeExportDetail", systemImage: "clock.arrow.circlepath")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(viewModel.isExportDisabled ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
                }
                .disabled(viewModel.isExportDisabled)

                NavigationLink {
                    AddNewProductView(event: event) {
                        viewModel.loadData()
                    }
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(DesignSystem.ColorToken.ink)
                }
            }
        }
        .shareSheet(
            isPresented: $showShareSheet,
            activityItems: { viewModel.currentShareItems },
            excludedTypes: UIActivity.ActivityType.defaultExcludedTypes,
            onComplete: { completed in
                if completed {
                    viewModel.handleExportSuccess()
                }
            }
        )
        // 匯出成功
        .alert("inventoryChangeExportSuccess", isPresented: $viewModel.showingExportAlert) {
            // 確定
            Button("commonConfirm") { }
        } message: {
            // 報表已成功匯出
            Text("inventoryChangeExportSuccessMessage")
        }
        .alert(isPresented: $viewModel.showAlert) {
            viewModel.createAlert()
        }
        .navigationDestination(isPresented: $showAddProduct) {
            if let product = editingProduct {
                AddNewProductView(event: event, productToEdit: product) {
                    viewModel.loadData()
                    editingProduct = nil
                }
            }
        }
        .onAppear {
            viewModel.updateRepositories(
                productRepository: productRepository,
                inventoryChangeRepository: inventoryChangeRepository,
                transactionDataManager: transactionDataManager
            )
        }
        .onChange(of: searchText) {
            viewModel.searchText = searchText
        }
        .onChange(of: timeRange.type) {
            viewModel.selectedTimeRange = timeRange
        }
        .onChange(of: timeRange.customStart) {
            if timeRange.type == .custom {
                viewModel.selectedTimeRange = timeRange
            }
        }
        .onChange(of: timeRange.customEnd) {
            if timeRange.type == .custom {
                viewModel.selectedTimeRange = timeRange
            }
        }
        .onChange(of: eventDataManager.events) {
            // 檢查當前場次是否還存在，若已被刪除則返回上一頁
            let eventExists = eventDataManager.events.contains { $0.id == viewModel.event.id }
            if !eventExists {
                dismiss()
            }
        }
    }

    // MARK: - 商品列表（按類別分組，參考 ProductDetailView）

    private var productList: some View {
        ScrollView {
            if viewModel.hasNoProducts {
                emptyState
            } else if viewModel.isSearchEmpty {
                searchEmptyState
            } else {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    // 啟用的商品（按類別分組）
                    ForEach(viewModel.sortedCategories, id: \.id) { category in
                        let items = viewModel.getItemsForCategory(category.id)
                        if !items.isEmpty {
                            categorySection(category: category, items: items)
                        }
                    }

                    // 下架商品區
                    if !viewModel.filteredDisabledItems.isEmpty {
                        disabledProductsSection
                    }
                }
                .padding(.top, DesignSystem.Spacing.md)
                .padding(.bottom, DesignSystem.Spacing.lg)
            }
        }
    }

    // MARK: - 下架商品區（參考 ProductDetailView）

    private var disabledProductsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            // 可點擊的標題（展開/收合）
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.showDisabledProducts.toggle()
                }
            }) {
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

            // 下架商品列表（展開時顯示）
            if viewModel.showDisabledProducts {
                ForEach(viewModel.filteredDisabledItems) { item in
                    DisabledInventoryProductCard(
                        item: item,
                        filteredChanges: viewModel.filteredChanges(for: item),
                        currency: event.currency,
                        onToggle: { viewModel.toggleDisabledExpanded(for: item.id) },
                        onRestore: { viewModel.handleRestoreAction(for: item.id) }
                    )
                    .padding(.horizontal, DesignSystem.Spacing.md)
                }
            }
        }
    }

    // MARK: - 類別區塊（可展開/收起）

    private func categorySection(category: CategoryModel, items: [InventoryProductItem]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            // 可點擊的分類標題
            Button(action: {
                viewModel.toggleCategoryExpansion(category.id)
            }) {
                HStack {
                    Text(category.name)
                        .font(DesignSystem.Typography.title2)
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

            // 商品列表（可展開/收起）
            if viewModel.isCategoryExpanded(category.id) {
                ForEach(items) { item in
                    InventoryProductCard(
                        item: item,
                        filteredChanges: viewModel.filteredChanges(for: item),
                        currency: event.currency,
                        onToggle: { viewModel.toggleExpanded(for: item.id) },
                        actionType: viewModel.getActionType(for: item.id),
                        onEdit: {
                            editingProduct = item.product
                            showAddProduct = true
                        },
                        onDisableOrDelete: {
                            switch viewModel.getActionType(for: item.id) {
                            case .disable:
                                viewModel.handleDisableAction(for: item.id)
                            case .delete:
                                viewModel.handleDeleteAction(for: item.id)
                            }
                        }
                    )
                    .padding(.horizontal, DesignSystem.Spacing.md)
                }
            }
        }
    }

    // MARK: - 空狀態

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "shippingbox",
            // 尚無商品
            title: String.localized("inventoryChangeEmptyTitle"),
            // 請先在場次中新增商品
            message: String.localized("inventoryChangeEmptyMessage"),
            topPadding: 60
        )
    }

    private var searchEmptyState: some View {
        EmptyStateView(
            systemImage: "magnifyingglass",
            // 查無結果
            title: String.localized("inventoryChangeSearchNoResult"),
            // 找不到符合「%@」的商品
            message: String.localized("inventoryChangeSearchNoResultMessage \(viewModel.searchText)"),
            topPadding: 60
        )
    }
}

// MARK: - 商品卡片

struct InventoryProductCard: View {
    let item: InventoryProductItem
    let filteredChanges: [InventoryChangeModel]
    let currency: String
    let onToggle: () -> Void
    let actionType: ProductActionType
    let onEdit: () -> Void
    let onDisableOrDelete: () -> Void

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
        .background(DesignSystem.ColorToken.cardSurface)
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
                        Text(item.product.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DesignSystem.ColorToken.ink)
                            .lineLimit(1)

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

            // 編輯／下架／刪除選單
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
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .foregroundColor(DesignSystem.ColorToken.muted)
                .padding(DesignSystem.Spacing.xxs)
        }
    }

    private var productImage: some View {
        SyncableImageView(
            imageData: item.product.imageData,
            imageURL: item.product.imageURL,
            entityId: item.product.id,
            entityType: .product,
            contentMode: .fill
        )
        .frame(width: 70, height: 70)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
    }

    private var stockBadge: some View {
        HStack(spacing: DesignSystem.Spacing.xxs) {
            if item.isLowStock {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(DesignSystem.Typography.caption)
            }
            // %lld 件
            Text("inventoryChangePieceCount \(item.currentStock)")
                .font(DesignSystem.Typography.caption)
        }
        .foregroundColor(item.isLowStock ? DesignSystem.ColorToken.alertRed : DesignSystem.ColorToken.muted)
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
                        .foregroundColor(DesignSystem.ColorToken.ink)
                    // 件
                    Text("inventoryChangeUnit")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
            }

            Spacer()

            // 庫存狀態標籤
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
        .padding(DesignSystem.Spacing.sm)
        .background(DesignSystem.ColorToken.quietFill)
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
                .foregroundColor(DesignSystem.ColorToken.ink)
                .padding(.horizontal, DesignSystem.Spacing.xs)
                .padding(.vertical, DesignSystem.Spacing.xxs)
                .background(
                    Capsule()
                        .fill(DesignSystem.ColorToken.quietFill)
                )

            // 變化量
            Text(change.changeText)
                .font(DesignSystem.Typography.caption)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.ColorToken.ink)

            Spacer()

            // 時間
            Text(DateFormatter.dateTime.string(from: change.timestamp))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.muted)
        }
        .padding(.vertical, DesignSystem.Spacing.xxs)
    }
}

// MARK: - 下架商品卡片（灰度樣式）

struct DisabledInventoryProductCard: View {
    let item: InventoryProductItem
    let filteredChanges: [InventoryChangeModel]
    let currency: String
    let onToggle: () -> Void
    let onRestore: () -> Void

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
        .background(DesignSystem.ColorToken.quietFill)
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
                    // 商品圖片（灰度效果）
                    productImage

                    // 商品資訊
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                        Text(item.product.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .lineLimit(1)

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

            // 復原選單
            Menu {
                Button {
                    onRestore()
                } label: {
                    // 復原
                    Label("inventoryRestore", systemImage: "arrow.uturn.backward")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .foregroundColor(DesignSystem.ColorToken.muted)
                    .padding(DesignSystem.Spacing.xxs)
            }
        }
        .padding(DesignSystem.Spacing.sm)
    }

    private var productImage: some View {
        SyncableImageView(
            imageData: item.product.imageData,
            imageURL: item.product.imageURL,
            entityId: item.product.id,
            entityType: .product,
            contentMode: .fill
        )
        .frame(width: 70, height: 70)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
        .grayscale(1.0)
        .opacity(0.6)
    }

    private var stockBadge: some View {
        // %lld 件
        Text("inventoryChangePieceCount \(item.currentStock)")
            .font(DesignSystem.Typography.caption)
            .foregroundColor(DesignSystem.ColorToken.muted)
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
                        .foregroundColor(DesignSystem.ColorToken.muted)
                    // 件
                    Text("inventoryChangeUnit")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.ColorToken.muted)
                }
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.sm)
        .background(DesignSystem.ColorToken.cardSurface)
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
                .foregroundColor(DesignSystem.ColorToken.muted)
                .padding(.horizontal, DesignSystem.Spacing.xs)
                .padding(.vertical, DesignSystem.Spacing.xxs)
                .background(
                    Capsule()
                        .fill(DesignSystem.ColorToken.cardSurface)
                )

            // 變化量
            Text(change.changeText)
                .font(DesignSystem.Typography.caption)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.ColorToken.muted)

            Spacer()

            // 時間
            Text(DateFormatter.dateTime.string(from: change.timestamp))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.ColorToken.muted)
        }
        .padding(.vertical, DesignSystem.Spacing.xxs)
    }
}
