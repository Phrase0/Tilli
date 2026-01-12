//
//  InventoryChangeView.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/12.
//

import SwiftUI

struct InventoryChangeView: View {
    @StateObject private var viewModel: InventoryChangeViewModel
    @Environment(\.dismiss) private var dismiss

    init(session: SessionModel) {
        self._viewModel = StateObject(wrappedValue: InventoryChangeViewModel(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 搜尋框
            searchBar

            // 時間篩選
            timeRangeSelector

            // 類別篩選
            categorySelector

            // 商品列表
            productList
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.gray)
                }
            }
            ToolbarItem(placement: .principal) {
                Text("庫存管理")
                    .font(.headline)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    // TODO: CSV 匯出功能
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.blue)
                }
            }
        }
    }

    // MARK: - 搜尋框

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("輸入商品名稱", text: $viewModel.searchText)
                .textFieldStyle(.plain)

            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - 時間篩選

    private var timeRangeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InventoryTimeRange.RangeType.allCases, id: \.self) { rangeType in
                    timeRangeButton(for: rangeType)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
    }

    private func timeRangeButton(for rangeType: InventoryTimeRange.RangeType) -> some View {
        let isSelected = viewModel.selectedTimeRange.type == rangeType

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedTimeRange.type = rangeType
            }
        }) {
            Text(rangeType.displayName)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Color.blue : Color(.systemGray5))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 類別篩選

    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 全部類別按鈕
                categoryButton(id: nil, name: "全部", icon: "square.grid.2x2")

                // 各類別按鈕
                ForEach(viewModel.categories) { category in
                    categoryButton(id: category.id, name: category.name, icon: "tag")
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 12)
    }

    private func categoryButton(id: UUID?, name: String, icon: String) -> some View {
        let isSelected = viewModel.selectedCategoryId == id

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedCategoryId = id
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(name)
                    .font(.subheadline)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(isSelected ? Color.clear : Color(.systemGray4), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 商品列表

    private var productList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredItems) { item in
                    InventoryProductCard(
                        item: item,
                        filteredChanges: viewModel.filteredChanges(for: item),
                        onToggle: { viewModel.toggleExpanded(for: item.id) }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
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
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    // MARK: - 商品標題區

    private var productHeader: some View {
        HStack(spacing: 12) {
            // 商品圖片
            productImage

            // 商品資訊
            VStack(alignment: .leading, spacing: 4) {
                Text(item.product.name)
                    .font(.headline)
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
        .padding()
    }

    private var productImage: some View {
        Group {
            if let imageData = item.product.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 50, height: 50)
        .background(Color(.systemGray6))
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
            }
        }
        .padding()
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
        .padding()
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
            // 原因標籤
            Text(change.reason.displayName)
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
