//
//  InventoryView.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/12.
//

import SwiftUI

private extension View {
    /// 讓 List 裡的自訂卡片列（商品卡片、類別標題）不要有系統預設的分隔線/灰底/邊界留白，
    /// 樣式維持跟原本卡片式清單一致，只保留卡片之間的垂直間距。
    func productListRow(bottomSpacing: CGFloat) -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: 0,
                leading: DesignSystem.Spacing.md,
                bottom: bottomSpacing,
                trailing: DesignSystem.Spacing.md
            ))
    }
}

/// 商品／套餐／組合表單要顯示哪個內容，由容器（EventWorkspaceView）持有並決定何時 push。
enum InventoryFormTarget: Identifiable, Hashable {
    case new
    case edit(ProductModel)
    case newBundle(BundleKind)
    case editBundle(BundleModel)

    var id: String {
        switch self {
        case .new:
            return "new"
        case .edit(let product):
            return product.id.uuidString
        case .newBundle(let kind):
            return "newBundle-\(kind.rawValue)"
        case .editBundle(let bundle):
            return "bundle-\(bundle.id.uuidString)"
        }
    }
}

/// 管理頁 chip 列跳轉的目標區塊
private enum InventorySectionAnchor: Hashable {
    case top
    case fixedBundles
    case comboBundles
    case category(UUID)
}

struct InventoryView: View {
    let event: EventModel

    @ObservedObject var viewModel: InventoryViewModel
    @Binding var showShareSheet: Bool
    @Binding var formTarget: InventoryFormTarget?

    @EnvironmentObject var productRepository: ProductRepository
    @EnvironmentObject var eventRepository: EventRepository

    @State private var timeRange: ReportTimeRange
    @State private var searchText = ""
    @State private var bundlePendingDeletion: BundleModel?

    init(
        event: EventModel,
        viewModel: InventoryViewModel,
        showShareSheet: Binding<Bool>,
        formTarget: Binding<InventoryFormTarget?>
    ) {
        self.event = event
        self.viewModel = viewModel
        self._showShareSheet = showShareSheet
        self._formTarget = formTarget
        self._timeRange = State(initialValue: ReportTimeRange(event: event))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // 時間範圍選擇器
                ReportTimeRangeSelector(event: viewModel.event, selectedRange: $timeRange)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.top, DesignSystem.Spacing.xs)
                // 商品列表（按類別分組）
                productList
            }

            // 場次內還沒有商品 → 直接新增商品；有商品後才能建套餐／組合，選單貼著 ＋ 彈出
            if viewModel.hasAnyProduct {
                FloatingActionMenu(systemImage: "plus") {
                    Button { formTarget = .new } label: {
                        // 新增商品
                        Label("bundleAddMenuProduct", systemImage: "shippingbox")
                    }
                    Button { formTarget = .newBundle(.fixed) } label: {
                        // 新增套餐
                        Label("bundleAddMenuFixed", systemImage: "takeoutbag.and.cup.and.straw")
                    }
                    Button { formTarget = .newBundle(.chooseAny) } label: {
                        // 新增組合
                        Label("bundleAddMenuCombo", systemImage: "square.stack.3d.up")
                    }
                }
            } else {
                FloatingActionButton(systemImage: "plus") {
                    formTarget = .new
                }
            }
        }
        .background(DesignSystem.ColorToken.paper)
        // 確認刪除 / 確定要刪除「%@」嗎？
        .alert(
            "productDetailConfirmDeleteTitle",
            isPresented: Binding(
                get: { bundlePendingDeletion != nil },
                set: { if !$0 { bundlePendingDeletion = nil } }
            ),
            presenting: bundlePendingDeletion
        ) { bundle in
            Button("commonDelete", role: .destructive) {
                viewModel.deleteBundle(bundle.id)
            }
            Button("commonCancel", role: .cancel) { }
        } message: { bundle in
            Text("bundleDeleteConfirm \(bundle.name)")
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
        .onAppear {
            viewModel.updateRepositories(productRepository: productRepository, eventRepository: eventRepository)
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
    }

    // MARK: - 商品列表（按類別分組；用 List 承載才能長按拖曳排序，樣式調成跟卡片式清單一致）

    private var productList: some View {
        Group {
            if viewModel.hasNoProducts {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if viewModel.isSearchEmpty {
                searchEmptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        chipRow(proxy: proxy)
                        list
                    }
                }
            }
        }
    }

    // MARK: - chip 列：全部｜套餐｜組合｜類別…（只列出畫面上有的區塊）

    private func chipRow(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                // 全部
                chip(Text("inventoryChipAll")) { scroll(proxy, to: .top) }
                if !viewModel.fixedBundles.isEmpty {
                    // 套餐
                    chip(Text("bundleChipFixed")) { scroll(proxy, to: .fixedBundles) }
                }
                if !viewModel.comboBundles.isEmpty {
                    // 組合
                    chip(Text("bundleChipCombo")) { scroll(proxy, to: .comboBundles) }
                }
                ForEach(visibleCategories, id: \.id) { category in
                    chip(Text(verbatim: category.name)) {
                        scroll(proxy, to: .category(category.id))
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.xs)
        }
    }

    /// 有商品的啟用類別（與下方區塊一致）
    private var visibleCategories: [CategoryModel] {
        viewModel.sortedCategories.filter { !viewModel.getItemsForCategory($0.id).isEmpty }
    }

    private func scroll(_ proxy: ScrollViewProxy, to anchor: InventorySectionAnchor) {
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    /// 樣式同收銀頁的折扣 chip（未選取狀態）
    private func chip(_ label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(DesignSystem.Typography.caption)
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(DesignSystem.ColorToken.quietFill)
                .foregroundColor(DesignSystem.ColorToken.ink)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 清單本體

    private var list: some View {
        List {
            // 「全部」chip 的跳轉目標
            Color.clear
                .frame(height: 0)
                .productListRow(bottomSpacing: 0)
                .id(InventorySectionAnchor.top)

            // 套餐
            if !viewModel.fixedBundles.isEmpty {
                Section {
                    ForEach(viewModel.fixedBundles) { bundle in
                        bundleRow(bundle)
                    }
                } header: {
                    bundleSectionHeader("bundleChipFixed")
                        .id(InventorySectionAnchor.fixedBundles)
                }
            }

            // 組合
            if !viewModel.comboBundles.isEmpty {
                Section {
                    ForEach(viewModel.comboBundles) { bundle in
                        bundleRow(bundle)
                    }
                } header: {
                    bundleSectionHeader("bundleChipCombo")
                        .id(InventorySectionAnchor.comboBundles)
                }
            }

            // 啟用的商品（按類別分組，類別內沒有商品時整個類別隱藏，同類別內可長按拖曳排序）
            ForEach(viewModel.sortedCategories, id: \.id) { category in
                let items = viewModel.getItemsForCategory(category.id)
                if !items.isEmpty {
                    Section {
                        if viewModel.isCategoryExpanded(category.id) {
                            ForEach(items) { item in
                                InventoryProductCard(
                                    item: item,
                                    filteredChanges: viewModel.filteredChanges(for: item),
                                    currency: event.currency,
                                    onToggle: { viewModel.toggleExpanded(for: item.id) },
                                    actionType: viewModel.getActionType(for: item.id),
                                    onEdit: {
                                        formTarget = .edit(item.product)
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
                                .productListRow(bottomSpacing: DesignSystem.Spacing.sm)
                            }
                            .onMove { from, to in
                                viewModel.moveProduct(in: category.id, from: from, to: to)
                            }
                            // 搜尋中不允許拖曳，避免搬動的是過濾後的子集
                            .moveDisabled(!searchText.isEmpty)
                        }
                    } header: {
                        categoryHeader(category)
                            .id(InventorySectionAnchor.category(category.id))
                    }
                }
            }

            // 下架商品區（不可拖曳）
            if !viewModel.filteredDisabledItems.isEmpty {
                Section {
                    if viewModel.showDisabledProducts {
                        ForEach(viewModel.filteredDisabledItems) { item in
                            DisabledInventoryProductCard(
                                item: item,
                                filteredChanges: viewModel.filteredChanges(for: item),
                                currency: event.currency,
                                onToggle: { viewModel.toggleDisabledExpanded(for: item.id) },
                                onRestore: { viewModel.handleRestoreAction(for: item.id) }
                            )
                            .productListRow(bottomSpacing: DesignSystem.Spacing.sm)
                        }
                    }
                } header: {
                    disabledProductsHeader
                }
            }

            // 底部留白，避免最後一張卡片被右下角 FAB 蓋住
            Color.clear
                .frame(height: DesignSystem.Spacing.lg * 2)
                .productListRow(bottomSpacing: 0)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // 讓最上方 0 高的跳轉錨點列不佔預設最小列高
        .environment(\.defaultMinListRowHeight, 0)
    }

    // MARK: - 套餐／組合

    private func bundleSectionHeader(_ title: LocalizedStringKey) -> some View {
        HStack {
            Text(title)
                .font(DesignSystem.Typography.title2)
                .foregroundColor(DesignSystem.ColorToken.ink)
            Spacer()
        }
        .textCase(nil)
        .productListRow(bottomSpacing: DesignSystem.Spacing.sm)
    }

    private func bundleRow(_ bundle: BundleModel) -> some View {
        InventoryBundleCard(
            bundle: bundle,
            summary: viewModel.bundleSummary(bundle),
            warning: viewModel.bundleWarning(bundle),
            currency: event.currency,
            onEdit: { formTarget = .editBundle(bundle) },
            onToggleDisabled: { viewModel.setBundleDisabled(bundle.id, !bundle.isDisabled) },
            onDelete: { bundlePendingDeletion = bundle }
        )
        .productListRow(bottomSpacing: DesignSystem.Spacing.sm)
    }

    // MARK: - 下架商品區標題（可展開/收合）

    private var disabledProductsHeader: some View {
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

                Spacer()

                Image(systemName: viewModel.showDisabledProducts ? "chevron.up" : "chevron.down")
                    .foregroundColor(DesignSystem.ColorToken.muted)
                    .font(DesignSystem.Typography.caption)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .textCase(nil)
        .productListRow(bottomSpacing: DesignSystem.Spacing.sm)
    }

    // MARK: - 類別標題（可展開/收合，內容展開時同類別內可拖曳排序）

    private func categoryHeader(_ category: CategoryModel) -> some View {
        Button(action: {
            viewModel.toggleCategoryExpansion(category.id)
        }) {
            HStack {
                Text(category.name)
                    .font(DesignSystem.Typography.title2)
                    .foregroundColor(DesignSystem.ColorToken.ink)

                Spacer()

                Image(systemName: viewModel.isCategoryExpanded(category.id) ? "chevron.up" : "chevron.down")
                    .foregroundColor(DesignSystem.ColorToken.muted)
                    .font(DesignSystem.Typography.caption)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .textCase(nil)
        .productListRow(bottomSpacing: DesignSystem.Spacing.sm)
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

// MARK: - 套餐／組合卡片

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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(bundle.isDisabled ? DesignSystem.ColorToken.muted : DesignSystem.ColorToken.ink)
                        .lineLimit(1)

                    if bundle.isDisabled {
                        // 已下架
                        Text("bundleMemberDisabledTag")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.ColorToken.muted)
                            .padding(.horizontal, DesignSystem.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DesignSystem.ColorToken.cardSurface))
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
                        Image(systemName: "exclamationmark.triangle.fill")
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
        EntityImageView(
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
        EntityImageView(
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
