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
    @Published var selectedCategoryId: UUID? = nil  // nil 表示全部類別
    @Published var inventoryItems: [InventoryProductItem] = []

    // MARK: - Dependencies
    let session: SessionModel
    private var productRepository: ProductRepository?
    private var inventoryChangeRepository: InventoryChangeRepository?

    // MARK: - Computed Properties

    /// 從 session 取得類別列表（只顯示啟用的）
    var categories: [CategoryModel] {
        session.categories.filter { !$0.isDisabled }
    }

    /// 篩選後的商品列表
    var filteredItems: [InventoryProductItem] {
        var result = inventoryItems

        // 類別篩選
        if let categoryId = selectedCategoryId {
            result = result.filter { $0.product.categoryId == categoryId }
        }

        // 搜尋篩選
        if !searchText.isEmpty {
            result = result.filter {
                $0.product.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    // MARK: - Init

    init(session: SessionModel) {
        self.session = session
        self.selectedTimeRange = ReportTimeRange(session: session)
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
}
