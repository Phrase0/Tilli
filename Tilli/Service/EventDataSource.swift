//
//  EventDataSource.swift
//  Tilli
//
//  Created by Peiyun on 2026/9/12.
//
//  一個場次的完整資料快照，由場次工作區建立一次，三個分頁（POS／庫存／報表）共用。
//

import SwiftUI

/// 場次工作區的唯一資料源。
///
/// - `event` 只有一個來源，三個分頁看到的是同一份
/// - 商品與類別**一起**重載，不會出現「商品是新鮮的、類別是舊快照」
/// - 報表共用同一份 `transactions`，切換 timeRange 只在記憶體篩選，不查 DB
/// - `transactionIndex` 只建立一次，全場次共用
@MainActor
final class EventDataSource: ObservableObject {

    @Published private(set) var event: EventModel
    @Published private(set) var products: [ProductModel] = []
    @Published private(set) var categories: [CategoryModel] = []
    @Published private(set) var transactions: [TransactionModel] = []
    @Published private(set) var inventoryChanges: [InventoryChangeModel] = []
    @Published private(set) var transactionIndex: TransactionIndex = .empty

    /// 場次已被刪除（由工作區容器監看並 pop 回上一頁）。
    /// 「場次還在不在」是容器層的事，不由其中一個分頁負責。
    @Published private(set) var isEventDeleted = false

    private var eventRepository: EventRepository?
    private var productRepository: ProductRepository?
    private var transactionRepository: TransactionRepository?
    private var inventoryChangeRepository: InventoryChangeRepository?

    init(event: EventModel) {
        self.event = event
        self.categories = event.categories
    }

    // MARK: - 注入與載入

    /// 由場次工作區在 `onAppear` 注入 Repository 並立即載入
    /// （Repository 走 `@EnvironmentObject`，在 `init` 取不到）
    func attach(
        eventRepository: EventRepository,
        productRepository: ProductRepository,
        transactionRepository: TransactionRepository,
        inventoryChangeRepository: InventoryChangeRepository
    ) {
        self.eventRepository = eventRepository
        self.productRepository = productRepository
        self.transactionRepository = transactionRepository
        self.inventoryChangeRepository = inventoryChangeRepository
        reload()
    }

    /// 重新載入全部資料。
    ///
    /// ⭐ `event`、`categories`、`products` 一定一起更新：
    /// 不可以只重載商品而讓類別留在舊的 `event` 快照上。
    func reload() {
        guard let productRepository, let transactionRepository, let inventoryChangeRepository else { return }

        if let eventRepository {
            if let fresh = eventRepository.fetchEvent(by: event.id) {
                event = fresh
            } else {
                isEventDeleted = true
                return
            }
        }
        categories = event.categories
        products = productRepository.fetchProducts(forEventId: event.id)
        transactions = transactionRepository.fetchTransactions(forEventId: event.id)
        inventoryChanges = inventoryChangeRepository.fetchChanges(forEventId: event.id)
        transactionIndex = TransactionIndex(transactions: transactions)
    }

    // MARK: - 查詢

    /// 依時間範圍取交易（報表用，從記憶體篩選，不重複查 DB）。
    ///
    /// 篩選條件與 `TransactionRepository.fetchTransactions(forEventId:dateRange:)` 一致：
    /// 都用 `displayDate`（優先 `occurredAt`，否則 `timestamp`）。
    func transactions(in range: DateInterval?) -> [TransactionModel] {
        guard let range else { return transactions }
        return transactions.filter { $0.displayDate >= range.start && $0.displayDate <= range.end }
    }

    /// 該場次的交易摘要（筆數 + 總金額）
    var transactionSummary: (count: Int, total: Decimal) {
        transactions.summary
    }

    /// 啟用中的類別（依 sortOrder）
    var activeCategories: [CategoryModel] {
        categories.active
    }

    /// 可販售的商品（商品未下架 + 所屬類別存在且未停用）
    var activeProducts: [ProductModel] {
        products.filter { $0.isAvailableForSale(in: categories) }
    }

    /// 取得類別名稱（從目前的類別查，商品不另存類別名稱）
    func categoryName(for categoryId: UUID) -> String {
        // 未分類
        categories.first { $0.id == categoryId }?.name ?? String.localized("inventoryUncategorized")
    }

    /// 指定商品的庫存異動紀錄
    func inventoryChanges(forProductId productId: UUID) -> [InventoryChangeModel] {
        inventoryChanges.filter { $0.productId == productId }
    }
}

extension Array where Element == TransactionModel {

    /// 交易摘要（筆數 + 總金額）。
    ///
    /// ⭐ 一律用 `MoneyHelper.add`，不用原生 `+`（捨入行為不同）。場次列表與日曆都用這裡，是唯一的定義。
    var summary: (count: Int, total: Decimal) {
        (count: count, total: total)
    }

    /// 總金額
    var total: Decimal {
        reduce(Decimal(0)) { MoneyHelper.add($0, $1.totalAmount) }
    }
}
