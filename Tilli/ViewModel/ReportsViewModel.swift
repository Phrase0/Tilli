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

class ReportsViewModel: ObservableObject {

    let event: EventModel

    let transactionViewModel: TransactionViewModel
    let productPerformanceViewModel: ProductPerformanceViewModel
    let salesAnalyticsViewModel: SalesAnalyticsViewModel

    @Published var selectedTab: ReportsTab = .transactions
    @Published var currentShareItems: [Any] = []
    @Published var showingExportSuccessAlert = false

    init(event: EventModel) {
        self.event = event
        self.transactionViewModel = TransactionViewModel(event: .constant(event))
        self.productPerformanceViewModel = ProductPerformanceViewModel(event: .constant(event))
        self.salesAnalyticsViewModel = SalesAnalyticsViewModel(event: .constant(event))
    }

    func updateDataManagers(
        transactionDataManager: TransactionRepository,
        eventDataManager: EventRepository
    ) {
        transactionViewModel.updateDataManagers(
            transactionDataManager: transactionDataManager
        )
        productPerformanceViewModel.updateDataManagers(
            transactionDataManager: transactionDataManager,
            eventDataManager: eventDataManager
        )
        salesAnalyticsViewModel.updateDataManagers(
            transactionDataManager: transactionDataManager
        )
    }

    func loadAllData(timeRange: ReportTimeRange) {
        transactionViewModel.loadData(timeRange: timeRange)
        productPerformanceViewModel.loadData(timeRange: timeRange)
        salesAnalyticsViewModel.loadData(timeRange: timeRange)
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
