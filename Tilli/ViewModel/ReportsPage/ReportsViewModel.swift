//
//  ReportsViewModel.swift
//  Tilli
//
//  Created by Peiyun.
//

import SwiftUI

enum ReportsTab: Int, CaseIterable {
    case transactions = 0
    case performance = 1
    case analytics = 2
}

enum ReportExportType {
    case transactionDetail
    case productPerformanceAll
    case topProducts
    case categoryAnalysis
    case salesAnalyticsAll
    case hourlyAnalysis
    case paymentMethod
    case dailyRevenueTrend
    case monthlyRevenueTrend
}

@MainActor
class ReportsViewModel: ObservableObject {

    /// 場次工作區的共用資料源（CONVENTIONS.md 規則 1 例外 2）
    private let dataSource: EventDataSource

    var event: EventModel { dataSource.event }

    let transactionViewModel: TransactionHistoryViewModel
    let productPerformanceViewModel: ProductPerformanceViewModel
    let salesAnalyticsViewModel: SalesAnalyticsViewModel

    @Published var selectedTab: ReportsTab = .transactions
    @Published var currentShareItems: [Any] = []
    @Published var showingExportSuccessAlert = false

    init(dataSource: EventDataSource) {
        self.dataSource = dataSource
        self.transactionViewModel = TransactionHistoryViewModel(dataSource: dataSource)
        self.productPerformanceViewModel = ProductPerformanceViewModel(dataSource: dataSource)
        self.salesAnalyticsViewModel = SalesAnalyticsViewModel(dataSource: dataSource)
    }

    /// 重新查 DB 一次，再讓三張報表各自重算（進頁面／回到頁面時用）
    func reloadAllData(timeRange: ReportTimeRange) {
        dataSource.reload()
        loadAllData(timeRange: timeRange)
    }

    /// 只重算，不查 DB。
    ///
    /// 三張報表共用 `dataSource` 的同一份 `transactions`，切換 timeRange 純粹是
    /// 換記憶體裡的篩選條件 —— 原本每換一次要查 3 次 DB（A5 / E2 / U6）。
    func loadAllData(timeRange: ReportTimeRange) {
        transactionViewModel.loadData(timeRange: timeRange)
        productPerformanceViewModel.loadData(timeRange: timeRange)
        salesAnalyticsViewModel.loadData(timeRange: timeRange)
        objectWillChange.send()
    }

    func isCurrentTabExportDisabled() -> Bool {
        switch selectedTab {
        case .transactions:
            return transactionViewModel.transactions.isEmpty
        case .performance:
            return productPerformanceViewModel.topProducts.isEmpty
                && productPerformanceViewModel.categoryAnalysis.isEmpty
        case .analytics:
            return salesAnalyticsViewModel.salesOverview?.totalTransactions == 0
                || salesAnalyticsViewModel.salesOverview == nil
        }
    }

    func handleExportSuccess() {
        showingExportSuccessAlert = true
    }

    func prepareExport(type: ReportExportType) {
        currentShareItems = getShareItems(for: type)
    }

    private func getShareItems(for type: ReportExportType) -> [Any] {
        switch type {
        case .transactionDetail:
            return [transactionViewModel.createTempCSVFileURL()]
        case .productPerformanceAll:
            return [
                productPerformanceViewModel.createTopProductsCSVFileURL(),
                productPerformanceViewModel.createCategoryAnalysisCSVFileURL()
            ]
        case .topProducts:
            return [productPerformanceViewModel.createTopProductsCSVFileURL()]
        case .categoryAnalysis:
            return [productPerformanceViewModel.createCategoryAnalysisCSVFileURL()]
        case .salesAnalyticsAll:
            var items: [Any] = [
                salesAnalyticsViewModel.createHourlyAnalysisCSVFileURL(),
                salesAnalyticsViewModel.createPaymentMethodCSVFileURL(),
                salesAnalyticsViewModel.createDailyRevenueTrendCSVFileURL()
            ]
            if event.dateType == .permanent {
                items.append(salesAnalyticsViewModel.createMonthlyRevenueTrendCSVFileURL())
            }
            return items
        case .hourlyAnalysis:
            return [salesAnalyticsViewModel.createHourlyAnalysisCSVFileURL()]
        case .paymentMethod:
            return [salesAnalyticsViewModel.createPaymentMethodCSVFileURL()]
        case .dailyRevenueTrend:
            return [salesAnalyticsViewModel.createDailyRevenueTrendCSVFileURL()]
        case .monthlyRevenueTrend:
            return [salesAnalyticsViewModel.createMonthlyRevenueTrendCSVFileURL()]
        }
    }
}
