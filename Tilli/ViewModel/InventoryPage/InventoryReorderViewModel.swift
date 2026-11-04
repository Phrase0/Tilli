//
//  InventoryReorderViewModel.swift
//  Tilli
//
//  排序畫面：組合｜套餐｜各類別商品的草稿，按「完成」才寫入。
//  列出全部項目（不套管理頁的搜尋、含已下架）。
//

import Foundation

/// 排序畫面的草稿：組合、套餐、各類別商品
struct ReorderDraft: Equatable {
    struct CategoryGroup: Equatable {
        let category: CategoryModel
        var products: [ProductModel]
    }

    var combos: [BundleModel]
    var fixed: [BundleModel]
    var categories: [CategoryGroup]
}

@MainActor
final class InventoryReorderViewModel: ObservableObject {
    /// 畫面上正在調整的順序（拖曳只改這份，「取消」直接丟掉）
    @Published private(set) var draft: ReorderDraft
    /// 寫入失敗（畫面不關閉，可再按一次「完成」）
    @Published var saveFailed = false

    private let dataSource: EventDataSource
    /// 有寫入資料庫時通知管理頁重新載入（成功或中途失敗都會通知）
    private let onDataChanged: () -> Void
    private var productRepository: ProductRepository?
    private var eventRepository: EventRepository?

    init(dataSource: EventDataSource, onDataChanged: @escaping () -> Void = {}) {
        self.dataSource = dataSource
        self.onDataChanged = onDataChanged
        self.draft = Self.makeDraft(from: dataSource)
    }

    /// 注入寫入用的 Repository（讀取一律走 dataSource）
    func updateRepositories(productRepository: ProductRepository, eventRepository: EventRepository) {
        self.productRepository = productRepository
        self.eventRepository = eventRepository
    }

    // MARK: - 拖曳（只能在同一組內移動）

    func moveCombos(from source: IndexSet, to destination: Int) {
        draft.combos.move(fromOffsets: source, toOffset: destination)
    }

    func moveFixed(from source: IndexSet, to destination: Int) {
        draft.fixed.move(fromOffsets: source, toOffset: destination)
    }

    func moveProducts(inGroup index: Int, from source: IndexSet, to destination: Int) {
        guard draft.categories.indices.contains(index) else { return }
        draft.categories[index].products.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - 寫入

    /// 按「完成」：套餐／組合依草稿寫入 sortOrder 0…n-1，各類別商品重新編號；沒變動的不寫。
    /// 任何一步失敗就設 `saveFailed` 並回傳 false
    @discardableResult
    func save() -> Bool {
        guard let productRepository, let eventRepository else {
            saveFailed = true
            return false
        }
        let original = Self.makeDraft(from: dataSource)
        var didWrite = false
        defer {
            if didWrite {
                dataSource.reload()
                onDataChanged()
            }
        }

        if draft.combos != original.combos || draft.fixed != original.fixed {
            var order: [UUID: Int] = [:]
            for (index, bundle) in draft.combos.enumerated() { order[bundle.id] = index }
            for (index, bundle) in draft.fixed.enumerated() { order[bundle.id] = index }
            let bundles = dataSource.event.bundles.map { bundle -> BundleModel in
                var copy = bundle
                if let index = order[bundle.id] { copy.sortOrder = index }
                return copy
            }
            guard eventRepository.saveBundles(bundles, forEventId: dataSource.event.id) else {
                saveFailed = true
                return false
            }
            didWrite = true
        }

        let changedGroups = draft.categories.filter { group in
            original.categories.first { $0.category.id == group.category.id }?.products.map(\.id) != group.products.map(\.id)
        }
        for group in changedGroups {
            guard productRepository.updateProductOrder(group.products.map(\.id)) else {
                saveFailed = true
                return false
            }
            didWrite = true
        }
        return true
    }

    // MARK: - 草稿

    /// 組合、套餐依顯示順序；類別依類別順序，各類別商品依 sortOrder（不套搜尋、含已下架，沒有商品的類別不列）
    private static func makeDraft(from dataSource: EventDataSource) -> ReorderDraft {
        let bundles = dataSource.event.bundles
        return ReorderDraft(
            combos: bundles.filter { $0.kind == .chooseAny }.sortedForDisplay(),
            fixed: bundles.filter { $0.kind == .fixed }.sortedForDisplay(),
            categories: dataSource.event.categories.active.compactMap { category in
                let products = dataSource.products
                    .filter { $0.categoryId == category.id }
                    .sorted { $0.sortOrder < $1.sortOrder }
                return products.isEmpty ? nil : .init(category: category, products: products)
            }
        )
    }
}
