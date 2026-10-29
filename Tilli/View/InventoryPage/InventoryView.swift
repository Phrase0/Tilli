//
//  InventoryView.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/12.
//

import SwiftUI

private extension View {
    /// 讓 List 裡的自訂卡片列（商品卡片、區塊標題）不要有系統預設的分隔線/灰底/邊界留白，
    /// 呈現卡片式清單，只保留列之間的垂直間距。
    func productListRow(topSpacing: CGFloat = 0, bottomSpacing: CGFloat) -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: topSpacing,
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
    /// 目前選取的 chip（黑底白字）；預設「全部」
    @State private var selectedAnchor: InventorySectionAnchor = .top

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
                chip(Text("inventoryChipAll"), anchor: .top, proxy: proxy)
                if !viewModel.fixedBundles.isEmpty {
                    // 套餐
                    chip(Text("bundleChipFixed"), anchor: .fixedBundles, proxy: proxy)
                }
                if !viewModel.comboBundles.isEmpty {
                    // 組合
                    chip(Text("bundleChipCombo"), anchor: .comboBundles, proxy: proxy)
                }
                ForEach(visibleCategories, id: \.id) { category in
                    chip(Text(verbatim: category.name), anchor: .category(category.id), proxy: proxy)
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

    /// 點 chip：標成選取並把對應區塊捲到頂端
    private func select(_ anchor: InventorySectionAnchor, proxy: ScrollViewProxy) {
        selectedAnchor = anchor
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    /// 樣式同收銀頁的折扣 chip：選取時黑底白字，未選取時灰底黑字
    private func chip(_ label: Text, anchor: InventorySectionAnchor, proxy: ScrollViewProxy) -> some View {
        let isSelected = selectedAnchor == anchor
        return Button {
            select(anchor, proxy: proxy)
        } label: {
            label
                .font(DesignSystem.Typography.caption)
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(isSelected ? DesignSystem.ColorToken.ink : DesignSystem.ColorToken.quietFill)
                .foregroundColor(isSelected ? DesignSystem.ColorToken.paper : DesignSystem.ColorToken.ink)
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

            // 區塊標題放在一般列（不用 Section header），跟內容一起捲動、不黏在上方，與收銀頁一致

            // 套餐
            if !viewModel.fixedBundles.isEmpty {
                Section {
                    sectionTitle(Text("bundleChipFixed"))
                        .productListRow(topSpacing: DesignSystem.Spacing.sm, bottomSpacing: DesignSystem.Spacing.sm)
                        .id(InventorySectionAnchor.fixedBundles)
                    ForEach(viewModel.fixedBundles) { bundle in
                        bundleRow(bundle)
                    }
                }
            }

            // 組合
            if !viewModel.comboBundles.isEmpty {
                Section {
                    sectionTitle(Text("bundleChipCombo"))
                        .productListRow(topSpacing: DesignSystem.Spacing.sm, bottomSpacing: DesignSystem.Spacing.sm)
                        .id(InventorySectionAnchor.comboBundles)
                    ForEach(viewModel.comboBundles) { bundle in
                        bundleRow(bundle)
                    }
                }
            }

            // 商品（按類別分組，含已下架者留在原位；類別內沒有商品時整個類別隱藏，同類別內可長按拖曳排序）
            ForEach(viewModel.sortedCategories, id: \.id) { category in
                let items = viewModel.getItemsForCategory(category.id)
                if !items.isEmpty {
                    Section {
                        sectionTitle(Text(verbatim: category.name))
                            .productListRow(topSpacing: DesignSystem.Spacing.sm, bottomSpacing: DesignSystem.Spacing.sm)
                            .id(InventorySectionAnchor.category(category.id))
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
                                },
                                onRestore: { viewModel.handleRestoreAction(for: item.id) }
                            )
                            .productListRow(bottomSpacing: DesignSystem.Spacing.sm)
                        }
                        .onMove { from, to in
                            viewModel.moveProduct(in: category.id, from: from, to: to)
                        }
                        // 搜尋中不允許拖曳，避免搬動的是過濾後的子集
                        .moveDisabled(!searchText.isEmpty)
                    }
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

    /// 區塊標題：字級與收銀頁的類別標題相同（Body 半粗體）
    private func sectionTitle(_ title: Text) -> some View {
        HStack {
            title
                .font(DesignSystem.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.ColorToken.ink)
            Spacer()
        }
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
