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

/// 庫存匯出類型
enum InventoryExportType {
    case all       // 全部匯出
    case summary   // 庫存總覽
    case detail    // 庫存異動明細
}

@MainActor
class InventoryChangeViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var searchText: String = ""
    @Published var selectedTimeRange: ReportTimeRange
    @Published var inventoryItems: [InventoryProductItem] = []
    @Published var disabledInventoryItems: [InventoryProductItem] = []  // 已下架商品
    @Published var expandedCategoryIds: Set<UUID> = []
    @Published var showDisabledProducts: Bool = false  // 下架商品區展開/收合狀態（預設收合）

    // MARK: - Export Properties
    @Published var selectedExportType: InventoryExportType = .all
    @Published var showingExportAlert = false
    @Published var currentShareItems: [Any] = []

    // MARK: - Dependencies
    let session: SessionModel
    private var productRepository: ProductRepository?
    private var inventoryChangeRepository: InventoryChangeRepository?
    private var transactionDataManager: TransactionRepository?

    // MARK: - Computed Properties

    /// 從 session 取得類別列表（只顯示啟用的，按 sortOrder 排序）
    var sortedCategories: [CategoryModel] {
        session.categories
            .filter { !$0.isDisabled }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 檢查是否有任何商品（用於空狀態判斷）
    var hasNoProducts: Bool {
        inventoryItems.isEmpty && disabledInventoryItems.isEmpty
    }

    /// 檢查搜尋是否無結果
    var isSearchEmpty: Bool {
        !searchText.isEmpty &&
        sortedCategories.allSatisfy { getItemsForCategory($0.id).isEmpty } &&
        filteredDisabledItems.isEmpty
    }

    /// 篩選後的下架商品（套用搜尋）
    var filteredDisabledItems: [InventoryProductItem] {
        if searchText.isEmpty {
            return disabledInventoryItems.sorted { $0.product.name.localizedStandardCompare($1.product.name) == .orderedAscending }
        }
        return disabledInventoryItems
            .filter { $0.product.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.product.name.localizedStandardCompare($1.product.name) == .orderedAscending }
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
                            inventoryChangeRepository: InventoryChangeRepository,
                            transactionDataManager: TransactionRepository) {
        self.productRepository = productRepository
        self.inventoryChangeRepository = inventoryChangeRepository
        self.transactionDataManager = transactionDataManager
        loadData()
    }

    /// 載入資料
    func loadData() {
        guard let productRepo = productRepository,
              let changeRepo = inventoryChangeRepository else { return }

        // 取得該場次的所有產品
        let allProducts = productRepo.fetchProducts(forSessionId: session.id)
        let enabledProducts = allProducts.filter { !$0.isDisabled }
        let disabledProducts = allProducts.filter { $0.isDisabled }

        // 取得該場次的所有異動紀錄
        let allChanges = changeRepo.fetchChanges(forSessionId: session.id)

        // 組合成 InventoryProductItem（啟用的商品）
        inventoryItems = enabledProducts.map { product in
            let productChanges = allChanges.filter { $0.productId == product.id }
            return InventoryProductItem(
                id: product.id,
                product: product,
                changes: productChanges
            )
        }

        // 組合成 InventoryProductItem（已下架的商品）
        disabledInventoryItems = disabledProducts.map { product in
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

    /// 切換下架商品展開/收起狀態
    func toggleDisabledExpanded(for itemId: UUID) {
        if let index = disabledInventoryItems.firstIndex(where: { $0.id == itemId }) {
            disabledInventoryItems[index].isExpanded.toggle()
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

    // MARK: - CSV 匯出

    /// 生成庫存總覽 CSV
    func generateInventorySummaryCSV() -> String {
        let currencyCode = session.currency
        let currency = Currency(rawValue: currencyCode) ?? .twd
        var csvContent = ""

        // 報表標題行
        csvContent += "庫存總覽_\(session.title), \(selectedTimeRange.csvDateRangeText)\n"
        csvContent += "\n"

        // 欄位標題（新增「狀態」欄位）
        csvContent += "商品名稱,類別,單價(\(currencyCode)),現有庫存,庫存狀態,狀態,期間入庫,期間出庫,淨異動\n"

        let dateInterval = selectedTimeRange.dateInterval

        // 合併啟用和下架商品
        let allItems = inventoryItems + disabledInventoryItems

        for item in allItems {
            let productName = item.product.name.replacingOccurrences(of: ",", with: "，")
            let categoryName = getCategoryName(for: item.product.categoryId).replacingOccurrences(of: ",", with: "，")
            let unitPrice = MoneyHelper.toDisplayString(item.product.price, currency: currency)
            let currentStock = "\(item.currentStock)"
            let stockStatus = item.isLowStock ? "庫存不足" : "庫存正常"
            let productStatus = item.product.isDisabled ? "已下架" : "銷售中"

            // 計算期間內的入庫和出庫
            let periodChanges = item.changes.filter { dateInterval.contains($0.timestamp) }
            let periodIn = periodChanges.filter { $0.change > 0 }.reduce(0) { $0 + $1.change }
            let periodOut = periodChanges.filter { $0.change < 0 }.reduce(0) { $0 + abs($1.change) }
            let netChange = periodIn - periodOut

            let periodInText = periodIn > 0 ? "+\(periodIn)" : "0"
            let periodOutText = periodOut > 0 ? "-\(periodOut)" : "0"
            let netChangeText = netChange >= 0 ? "+\(netChange)" : "\(netChange)"

            let row = "\(productName),\(categoryName),\(unitPrice),\(currentStock),\(stockStatus),\(productStatus),\(periodInText),\(periodOutText),\(netChangeText)\n"
            csvContent += row
        }

        return csvContent
    }

    /// 生成庫存異動明細 CSV
    func generateInventoryDetailCSV() -> String {
        var csvContent = ""

        // 報表標題行
        csvContent += "庫存異動明細_\(session.title), \(selectedTimeRange.csvDateRangeText)\n"
        csvContent += "\n"

        // 欄位標題（新增「狀態」欄位）
        csvContent += "交易編號,日期時間,商品名稱,類別,狀態,異動原因,異動數量,變動後庫存\n"

        let dateInterval = selectedTimeRange.dateInterval

        // 合併啟用和下架商品
        let allItems = inventoryItems + disabledInventoryItems

        // 預先計算每個商品每筆異動的「變動後庫存」
        var afterStockMap: [UUID: Int] = [:]  // changeId -> afterStock

        for item in allItems {
            // 取得該商品的所有異動紀錄（按時間升序排列）
            let sortedChanges = item.changes.sorted { $0.timestamp < $1.timestamp }

            // 計算所有異動的淨變化
            let totalChange = sortedChanges.reduce(0) { $0 + $1.change }

            // 推算最早異動前的庫存
            let stockBeforeAll = item.currentStock - totalChange

            // 依序計算每筆異動後的庫存
            var runningStock = stockBeforeAll
            for change in sortedChanges {
                runningStock += change.change
                afterStockMap[change.id] = runningStock
            }
        }

        // 收集所有期間內的異動紀錄
        var allChanges: [(change: InventoryChangeModel, product: ProductModel)] = []

        for item in allItems {
            let periodChanges = item.changes.filter { dateInterval.contains($0.timestamp) }
            for change in periodChanges {
                allChanges.append((change: change, product: item.product))
            }
        }

        // 按時間降序排列（最新的在最上面）
        allChanges.sort { $0.change.timestamp > $1.change.timestamp }

        // 建立 CSV 行
        for entry in allChanges {
            let change = entry.change
            let product = entry.product

            // 交易編號（僅銷售出庫有值）
            let transactionIdText: String
            if change.reason == .salesOut, let txId = change.transactionId {
                transactionIdText = "TXN\(txId.uuidString.prefix(8))"
            } else {
                transactionIdText = "-"
            }

            let dateTime = DateFormatter.dateTime.string(from: change.timestamp)
            let productName = product.name.replacingOccurrences(of: ",", with: "，")
            let categoryName = getCategoryName(for: product.categoryId).replacingOccurrences(of: ",", with: "，")
            let productStatus = product.isDisabled ? "已下架" : "銷售中"
            let reasonName = change.displayReasonName.replacingOccurrences(of: ",", with: "，")
            let changeText = change.change >= 0 ? "+\(change.change)" : "\(change.change)"
            let afterStock = afterStockMap[change.id].map { String($0) } ?? "-"

            let row = "\(transactionIdText),\(dateTime),\(productName),\(categoryName),\(productStatus),\(reasonName),\(changeText),\(afterStock)\n"
            csvContent += row
        }

        return csvContent
    }

    /// 建立庫存總覽 CSV 檔案 URL
    func createInventorySummaryCSVFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let safeTitle = session.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let fileName = "庫存總覽_\(safeTitle)_\(DateFormatter.fileTimestamp.string(from: Date())).csv"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            let csvContent = generateInventorySummaryCSV()
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error creating Inventory Summary CSV file: \(error)")
        }

        return fileURL
    }

    /// 建立庫存異動明細 CSV 檔案 URL
    func createInventoryDetailCSVFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let safeTitle = session.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let fileName = "庫存異動明細_\(safeTitle)_\(DateFormatter.fileTimestamp.string(from: Date())).csv"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            let csvContent = generateInventoryDetailCSV()
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error creating Inventory Detail CSV file: \(error)")
        }

        return fileURL
    }

    /// 取得類別名稱
    private func getCategoryName(for categoryId: UUID) -> String {
        session.categories.first { $0.id == categoryId }?.name ?? "未分類"
    }

    // MARK: - Export Management

    /// 準備匯出（設定類型並生成 share items）
    func prepareExport(type: InventoryExportType) {
        selectedExportType = type
        currentShareItems = getShareItems(for: type)
    }

    /// 根據匯出類型取得 share items
    func getShareItems(for type: InventoryExportType) -> [Any] {
        switch type {
        case .all:
            return [
                createInventorySummaryCSVFileURL(),
                createInventoryDetailCSVFileURL()
            ]
        case .summary:
            return [createInventorySummaryCSVFileURL()]
        case .detail:
            return [createInventoryDetailCSVFileURL()]
        }
    }

    /// 匯出成功後顯示提示
    func handleExportSuccess() {
        showingExportAlert = true
    }

    /// 檢查是否可以匯出
    var isExportDisabled: Bool {
        inventoryItems.isEmpty && disabledInventoryItems.isEmpty
    }
}
