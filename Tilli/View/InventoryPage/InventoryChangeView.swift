//
//  InventoryChangeView.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/12.
//

import SwiftUI

struct InventoryChangeView: View {
    @StateObject private var viewModel: InventoryChangeViewModel
    @EnvironmentObject var productRepository: ProductRepository
    @EnvironmentObject var inventoryChangeRepository: InventoryChangeRepository
    @EnvironmentObject var transactionDataManager: TransactionRepository
    @EnvironmentObject var sessionDataManager: SessionRepository
    @Environment(\.dismiss) private var dismiss

    @State private var timeRange: ReportTimeRange
    @State private var searchText = ""
    @State private var showShareSheet = false

    init(session: SessionModel) {
        self._viewModel = StateObject(wrappedValue: InventoryChangeViewModel(session: session))
        self._timeRange = State(initialValue: ReportTimeRange(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 時間範圍選擇器
            ReportTimeRangeSelector(session: viewModel.session, selectedRange: $timeRange)
                .padding(.horizontal)
            // 商品列表（按類別分組）
            productList
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
//        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜尋商品")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.gray)
                }
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(viewModel.session.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        viewModel.prepareExport(type: .all)
                        showShareSheet = true
                    } label: {
                        Label("全部匯出", systemImage: "square.and.arrow.up.on.square")
                    }

                    Divider()

                    Button {
                        viewModel.prepareExport(type: .summary)
                        showShareSheet = true
                    } label: {
                        Label("庫存總覽", systemImage: "list.bullet.rectangle")
                    }

                    Button {
                        viewModel.prepareExport(type: .detail)
                        showShareSheet = true
                    } label: {
                        Label("庫存異動明細", systemImage: "clock.arrow.circlepath")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(viewModel.isExportDisabled ? .gray : .blue)
                }
                .disabled(viewModel.isExportDisabled)
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
        .alert("匯出成功", isPresented: $viewModel.showingExportAlert) {
            Button("確定") { }
        } message: {
            Text("報表已成功匯出")
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
        .onChange(of: sessionDataManager.sessions) {
            // 檢查當前場次是否還存在，若已被刪除則返回上一頁
            let sessionExists = sessionDataManager.sessions.contains { $0.id == viewModel.session.id }
            if !sessionExists {
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
                VStack(alignment: .leading, spacing: 24) {
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
                .padding(.top)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - 下架商品區（參考 ProductDetailView）

    private var disabledProductsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 可點擊的標題（展開/收合）
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.showDisabledProducts.toggle()
                }
            }) {
                HStack {
                    Text("下架商品")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .padding(.horizontal)

                    Spacer()

                    Image(systemName: viewModel.showDisabledProducts ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                        .font(.caption)
                        .padding(.horizontal)
                }
            }
            .buttonStyle(PlainButtonStyle())

            // 下架商品列表（展開時顯示）
            if viewModel.showDisabledProducts {
                ForEach(viewModel.filteredDisabledItems) { item in
                    DisabledInventoryProductCard(
                        item: item,
                        filteredChanges: viewModel.filteredChanges(for: item),
                        onToggle: { viewModel.toggleDisabledExpanded(for: item.id) }
                    )
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - 類別區塊（可展開/收起）

    private func categorySection(category: CategoryModel, items: [InventoryProductItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 可點擊的分類標題
            Button(action: {
                viewModel.toggleCategoryExpansion(category.id)
            }) {
                HStack {
                    Text(category.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal)

                    Spacer()

                    Image(systemName: viewModel.isCategoryExpanded(category.id) ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                        .font(.caption)
                        .padding(.horizontal)
                }
            }
            .buttonStyle(PlainButtonStyle())

            // 商品列表（可展開/收起）
            if viewModel.isCategoryExpanded(category.id) {
                ForEach(items) { item in
                    InventoryProductCard(
                        item: item,
                        filteredChanges: viewModel.filteredChanges(for: item),
                        onToggle: { viewModel.toggleExpanded(for: item.id) }
                    )
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - 空狀態

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))

            Text("尚無商品")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("請先在場次中新增商品")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))

            Text("查無結果")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("找不到符合「\(viewModel.searchText)」的商品")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - 商品卡片

struct InventoryProductCard: View {
    let item: InventoryProductItem
    let filteredChanges: [InventoryChangeModel]
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 商品基本資訊（可點擊展開）
            Button(action: onToggle) {
                productHeader
            }
            .buttonStyle(.plain)

            // 展開內容
            if item.isExpanded {
                Divider()
                    .padding(.horizontal)

                expandedContent
            }
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
    }

    // MARK: - 商品標題區

    private var productHeader: some View {
        HStack(spacing: 12) {
            // 商品圖片
            productImage

            // 商品資訊
            VStack(alignment: .leading, spacing: 4) {
                Text(item.product.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("NT$ \(item.product.price.formatted())")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }

            Spacer()

            // 庫存狀態（收起時顯示）
            if !item.isExpanded {
                stockBadge
            }

            // 展開/收起箭頭
            Image(systemName: item.isExpanded ? "chevron.up" : "chevron.down")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding(12)
    }

    private var productImage: some View {
        ZStack {
            if let imageData = item.product.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .foregroundColor(Color(.systemGray5))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                            .font(.caption)
                    )
            }
        }
        .frame(width: 70, height: 70)
        .cornerRadius(8)
        .clipped()
    }

    private var stockBadge: some View {
        HStack(spacing: 4) {
            if item.isLowStock {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
            Text("\(item.currentStock) 件")
                .font(.caption)
                .foregroundColor(item.isLowStock ? .orange : .secondary)
        }
    }

    // MARK: - 展開內容

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 現有庫存卡片
            stockCard

            // 異動紀錄
            if !filteredChanges.isEmpty {
                changesSection
            } else {
                Text("此時間範圍內無異動紀錄")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
    }

    private var stockCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("現有庫存")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(item.currentStock)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.primary)
                    Text("件")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 庫存狀態標籤
            HStack(spacing: 4) {
                Image(systemName: item.isLowStock ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                Text(item.isLowStock ? "庫存不足" : "庫存正常")
            }
            .font(.caption)
            .foregroundColor(item.isLowStock ? .orange : .green)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(item.isLowStock ? Color.orange.opacity(0.1) : Color.green.opacity(0.1))
            )
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("異動紀錄")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(filteredChanges) { change in
                changeRow(change)
            }
        }
    }

    private func changeRow(_ change: InventoryChangeModel) -> some View {
        HStack {
            // 原因標籤（顯示自定義原因或預設名稱）
            Text(change.displayReasonName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(change.reason.tagColor)
                )

            // 變化量
            Text(change.changeText)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(change.changeColor)

            Spacer()

            // 時間
            Text(DateFormatter.dateTime.string(from: change.timestamp))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 下架商品卡片（灰度樣式）

struct DisabledInventoryProductCard: View {
    let item: InventoryProductItem
    let filteredChanges: [InventoryChangeModel]
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 商品基本資訊（可點擊展開）
            Button(action: onToggle) {
                productHeader
            }
            .buttonStyle(.plain)

            // 展開內容
            if item.isExpanded {
                Divider()
                    .padding(.horizontal)

                expandedContent
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
    }

    // MARK: - 商品標題區

    private var productHeader: some View {
        HStack(spacing: 12) {
            // 商品圖片（灰度效果）
            productImage

            // 商品資訊
            VStack(alignment: .leading, spacing: 4) {
                Text(item.product.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.gray)
                    .lineLimit(1)

                Text("NT$ \(item.product.price.formatted())")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            Spacer()

            // 庫存狀態（收起時顯示）
            if !item.isExpanded {
                stockBadge
            }

            // 展開/收起箭頭
            Image(systemName: item.isExpanded ? "chevron.up" : "chevron.down")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding(12)
    }

    private var productImage: some View {
        ZStack {
            if let imageData = item.product.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .foregroundColor(Color(.systemGray5))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                            .font(.caption)
                    )
            }
        }
        .frame(width: 70, height: 70)
        .cornerRadius(8)
        .clipped()
        .grayscale(1.0)
        .opacity(0.6)
    }

    private var stockBadge: some View {
        Text("\(item.currentStock) 件")
            .font(.caption)
            .foregroundColor(.gray)
    }

    // MARK: - 展開內容

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 現有庫存卡片
            stockCard

            // 異動紀錄
            if !filteredChanges.isEmpty {
                changesSection
            } else {
                Text("此時間範圍內無異動紀錄")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
    }

    private var stockCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("現有庫存")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(item.currentStock)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.gray)
                    Text("件")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.systemGray5))
        .cornerRadius(10)
    }

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("異動紀錄")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(filteredChanges) { change in
                changeRow(change)
            }
        }
    }

    private func changeRow(_ change: InventoryChangeModel) -> some View {
        HStack {
            // 原因標籤（顯示自定義原因或預設名稱）
            Text(change.displayReasonName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(change.reason.tagColor)
                )

            // 變化量
            Text(change.changeText)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(change.changeColor)

            Spacer()

            // 時間
            Text(DateFormatter.dateTime.string(from: change.timestamp))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
