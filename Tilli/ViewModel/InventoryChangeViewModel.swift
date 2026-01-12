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
    @Published var selectedTimeRange: InventoryTimeRange
    @Published var selectedCategoryId: UUID? = nil  // nil 表示全部類別
    @Published var inventoryItems: [InventoryProductItem] = []

    // MARK: - Dependencies
    private let session: SessionModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    /// 從 session 取得類別列表
    var categories: [CategoryModel] {
        session.categories
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
        self.selectedTimeRange = InventoryTimeRange(session: session)
        loadMockData()
    }

    // MARK: - Public Methods

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

    // MARK: - Mock Data

    private func loadMockData() {
        // 建立假商品資料
        let mockProducts = createMockProducts()
        let mockChanges = createMockChanges(for: mockProducts)

        inventoryItems = mockProducts.map { product in
            let changes = mockChanges.filter { $0.productId == product.id }
            return InventoryProductItem(
                id: product.id,
                product: product,
                changes: changes
            )
        }
    }

    private func createMockProducts() -> [ProductModel] {
        let categories = session.categories
        guard !categories.isEmpty else { return [] }

        let category1 = categories[0]
        let category2 = categories.count > 1 ? categories[1] : categories[0]
        let category3 = categories.count > 2 ? categories[2] : categories[0]

        return [
            ProductModel(
                id: UUID(),
                sessionId: session.id,
                name: "無線藍牙耳機 Pro Max",
                price: 2980,
                stock: 15,
                categoryId: category1.id,
                categoryName: category1.name,
                note: nil,
                imageData: nil,
                isDisabled: false
            ),
            ProductModel(
                id: UUID(),
                sessionId: session.id,
                name: "運動健身水壺 750ml",
                price: 450,
                stock: 2,  // 低庫存
                categoryId: category2.id,
                categoryName: category2.name,
                note: nil,
                imageData: nil,
                isDisabled: false
            ),
            ProductModel(
                id: UUID(),
                sessionId: session.id,
                name: "有機綠茶茶葉禮盒",
                price: 880,
                stock: 28,
                categoryId: category3.id,
                categoryName: category3.name,
                note: nil,
                imageData: nil,
                isDisabled: false
            ),
            ProductModel(
                id: UUID(),
                sessionId: session.id,
                name: "手工皮革錢包",
                price: 1580,
                stock: 1,  // 低庫存
                categoryId: category1.id,
                categoryName: category1.name,
                note: nil,
                imageData: nil,
                isDisabled: false
            ),
            ProductModel(
                id: UUID(),
                sessionId: session.id,
                name: "精品咖啡豆 250g",
                price: 380,
                stock: 45,
                categoryId: category3.id,
                categoryName: category3.name,
                note: nil,
                imageData: nil,
                isDisabled: false
            )
        ]
    }

    private func createMockChanges(for products: [ProductModel]) -> [InventoryChangeModel] {
        var changes: [InventoryChangeModel] = []
        let calendar = Calendar.current
        let now = Date()

        for product in products {
            // 每個商品建立 3-5 筆異動紀錄
            let changeCount = Int.random(in: 3...5)

            for i in 0..<changeCount {
                let daysAgo = Int.random(in: 0...30)
                let hoursAgo = Int.random(in: 0...23)
                let timestamp = calendar.date(
                    byAdding: .hour,
                    value: -hoursAgo,
                    to: calendar.date(byAdding: .day, value: -daysAgo, to: now)!
                )!

                let reasons: [InventoryChangeReason] = [.salesOut, .returnIn, .inventoryLoss, .purchase, .damaged]
                let reason = reasons[i % reasons.count]

                let change: Int
                switch reason {
                case .salesOut, .inventoryLoss, .damaged, .expired, .internalUse:
                    change = -Int.random(in: 1...5)
                case .returnIn, .purchase:
                    change = Int.random(in: 1...10)
                case .adjustment:
                    change = Int.random(in: -3...3)
                }

                changes.append(InventoryChangeModel(
                    id: UUID(),
                    productId: product.id,
                    sessionId: session.id,
                    change: change,
                    reason: reason,
                    timestamp: timestamp
                ))
            }
        }

        return changes.sorted { $0.timestamp > $1.timestamp }
    }
}
