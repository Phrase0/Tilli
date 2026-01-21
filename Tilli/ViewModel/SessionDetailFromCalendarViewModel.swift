//
//  SessionDetailFromCalendarViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/8.
//

import SwiftUI

/// 報表匯出類型
enum CalendarReportExportType {
    // Tab 0: 交易明細
    case transactionDetail

    // Tab 1: 產品績效
    case productPerformanceAll
    case topProducts
    case categoryAnalysis

    // Tab 2: 銷售分析
    case salesAnalyticsAll
    case hourlyAnalysis
    case paymentMethod
    case dailyRevenueTrend
    case monthlyRevenueTrend
}

class SessionDetailFromCalendarViewModel: ObservableObject {

    @Published var transactionViewModel: TransactionViewModel
    @Published var productPerformanceViewModel: ProductPerformanceViewModel
    @Published var salesAnalyticsViewModel: SalesAnalyticsViewModel
    @Published var selectedTab = 0

    // MARK: - Export Properties
    @Published var currentShareItems: [Any] = []
    @Published var showingExportSuccessAlert = false

    @Binding var session: SessionModel

    let tabTitles = ["交易明細", "產品績效", "銷售分析"]

    init(session: Binding<SessionModel>) {
        self._session = session
        self.transactionViewModel = TransactionViewModel(session: session)
        self.productPerformanceViewModel = ProductPerformanceViewModel(session: session)
        self.salesAnalyticsViewModel = SalesAnalyticsViewModel(session: session)
    }
    
    // MARK: - DataManager 管理
    
    /// 更新 DataManager 引用給所有子 ViewModel
    func updateDataManagers(
        transactionDataManager: TransactionRepository,
        sessionDataManager: SessionRepository
    ) {
        transactionViewModel.updateDataManagers(
            transactionDataManager: transactionDataManager
        )
        productPerformanceViewModel.updateDataManagers(
            transactionDataManager: transactionDataManager,
            sessionDataManager: sessionDataManager
        )
        salesAnalyticsViewModel.updateDataManagers(
            transactionDataManager: transactionDataManager
        )
    }
    
    // MARK: - Tab Management
    
    /// 切換選項卡
    func selectTab(_ index: Int) {
        selectedTab = index
    }
    
    /// 載入數據
    func loadData() {
        transactionViewModel.loadData()
        productPerformanceViewModel.loadData()
        salesAnalyticsViewModel.loadData()
    }
    
    // MARK: - CSV Export Management
    
    /// 檢查當前 tab 是否可以導出
    func isCurrentTabExportDisabled() -> Bool {
        switch selectedTab {
        case 0: // 交易明細
            return transactionViewModel.transactions.isEmpty
        case 1: // 產品績效
            return productPerformanceViewModel.topProducts.isEmpty && productPerformanceViewModel.categoryAnalysis.isEmpty
        case 2: // 銷售分析
            return salesAnalyticsViewModel.salesOverview?.totalTransactions == 0 || salesAnalyticsViewModel.salesOverview == nil
        default:
            return true
        }
    }

    /// 處理導出成功回調（在父視圖顯示 alert）
    func handleExportSuccess() {
        showingExportSuccessAlert = true
    }

    /// 準備匯出（設定類型並生成 share items）
    func prepareExport(type: CalendarReportExportType) {
        currentShareItems = getShareItems(for: type)
    }

    /// 根據匯出類型取得 share items
    func getShareItems(for type: CalendarReportExportType) -> [Any] {
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
            if session.dateType == .permanent {
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
