//
//  InventoryView.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/12.
//

import SwiftUI

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
        // 排序（工作區右上角的「排序」按鈕打開）
        .sheet(isPresented: $viewModel.isReordering) {
            InventoryReorderView(viewModel: viewModel)
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

    // MARK: - 商品列表（chip 列＋組合｜套餐｜類別…區塊；排序在「排序」畫面）

    private var productList: some View {
        Group {
            if viewModel.hasNoProducts {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if viewModel.isSearchEmpty {
                searchEmptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                SectionedScrollView(
                    ids: viewModel.sectionIDs,
                    title: sectionTitleText,
                    topPadding: DesignSystem.Spacing.sm,
                    // 底部留白，避免最後一張卡片被右下角 FAB 蓋住
                    bottomPadding: DesignSystem.Spacing.lg * 2
                ) { section in
                    sectionContent(section)
                }
            }
        }
    }

    private func sectionTitleText(_ section: InventorySectionID) -> Text {
        switch section {
        case .comboBundles:
            // 組合
            return Text("bundleChipCombo")
        case .fixedBundles:
            // 套餐
            return Text("bundleChipFixed")
        case .category(let categoryId):
            return Text(verbatim: viewModel.sortedCategories.first { $0.id == categoryId }?.name ?? "")
        }
    }

    /// 一個區塊：標題（與收銀頁相同，跟內容一起捲動）＋卡片；已下架的商品留在原類別原位置
    private func sectionContent(_ section: InventorySectionID) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionTitle(sectionTitleText(section))
            switch section {
            case .comboBundles:
                ForEach(viewModel.comboBundles) { bundleRow($0) }
            case .fixedBundles:
                ForEach(viewModel.fixedBundles) { bundleRow($0) }
            case .category(let categoryId):
                ForEach(viewModel.getItemsForCategory(categoryId)) { item in
                    productRow(item)
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
    }

    private func productRow(_ item: InventoryProductItem) -> some View {
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
