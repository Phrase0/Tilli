//
//  InventoryChangeViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/12.
//

import SwiftUI
import Combine

/// 庫存商品展示模型（包含商品資訊與異動紀錄）
struct InventoryProductItem: Identifiable {
    let id: UUID
    let product: ProductModel
    var changes: [InventoryChangeModel]
    var isExpanded: Bool = false

    /// 現有庫存
    var currentStock: Int {
        product.stock
    }

    /// 是否低庫存（< 3）
    var isLowStock: Bool {
        currentStock < 3
    }
}

@MainActor
class InventoryChangeViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var searchText: String = ""
    @Published var selectedTimeRange: ReportTimeRange
    @Published var inventoryItems: [InventoryProductItem] = []
    @Published var expandedCategoryIds: Set<UUID> = []

    // MARK: - Dependencies
    let session: SessionModel
    private var productRepository: ProductRepository?
    private var inventoryChangeRepository: InventoryChangeRepository?

    // MARK: - Computed Properties

    /// 從 session 取得類別列表（只顯示啟用的，按 sortOrder 排序）
    var sortedCategories: [CategoryModel] {
        session.categories
            .filter { !$0.isDisabled }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 檢查是否有任何商品（用於空狀態判斷）
    var hasNoProducts: Bool {
        inventoryItems.isEmpty
    }

    /// 檢查搜尋是否無結果
    var isSearchEmpty: Bool {
        !searchText.isEmpty && sortedCategories.allSatisfy { getItemsForCategory($0.id).isEmpty }
    }

    // MARK: - Init

    init(session: SessionModel) {
        self.session = session
        self.selectedTimeRange = ReportTimeRange(session: session)
        // 預設展開所有類別
        self.expandedCategoryIds = Set(session.categories.filter { !$0.isDisabled }.map { $0.id })
    }

    // MARK: - Public Methods

    /// 更新 Repository 引用
    func updateRepositories(productRepository: ProductRepository,
                            inventoryChangeRepository: InventoryChangeRepository) {
        self.productRepository = productRepository
        self.inventoryChangeRepository = inventoryChangeRepository
        loadData()
    }

    /// 載入資料
    func loadData() {
        guard let productRepo = productRepository,
              let changeRepo = inventoryChangeRepository else { return }

        // 取得該場次的所有產品（只顯示啟用的）
        let products = productRepo.fetchProducts(forSessionId: session.id)
            .filter { !$0.isDisabled }

        // 取得該場次的所有異動紀錄
        let allChanges = changeRepo.fetchChanges(forSessionId: session.id)

        // 組合成 InventoryProductItem
        inventoryItems = products.map { product in
            let productChanges = allChanges.filter { $0.productId == product.id }
            return InventoryProductItem(
                id: product.id,
                product: product,
                changes: productChanges
            )
        }
    }

    /// 切換商品展開/收起狀態
    func toggleExpanded(for itemId: UUID) {
        if let index = inventoryItems.firstIndex(where: { $0.id == itemId }) {
            inventoryItems[index].isExpanded.toggle()
        }
    }

    /// 篩選異動紀錄（根據時間範圍）
    func filteredChanges(for item: InventoryProductItem) -> [InventoryChangeModel] {
        let dateInterval = selectedTimeRange.dateInterval
        return item.changes.filter { change in
            dateInterval.contains(change.timestamp)
        }.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - 類別展開/收起

    /// 切換類別展開/收起狀態
    func toggleCategoryExpansion(_ categoryId: UUID) {
        if expandedCategoryIds.contains(categoryId) {
            expandedCategoryIds.remove(categoryId)
        } else {
            expandedCategoryIds.insert(categoryId)
        }
    }

    /// 檢查類別是否展開
    func isCategoryExpanded(_ categoryId: UUID) -> Bool {
        expandedCategoryIds.contains(categoryId)
    }

    /// 取得特定類別的商品列表（套用搜尋篩選）
    func getItemsForCategory(_ categoryId: UUID) -> [InventoryProductItem] {
        var items = inventoryItems.filter { $0.product.categoryId == categoryId }

        // 搜尋篩選
        if !searchText.isEmpty {
            items = items.filter {
                $0.product.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        return items
    }
}
