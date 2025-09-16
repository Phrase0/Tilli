//
//  SessionDetailFromCalendarViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/9/8.
//

import SwiftUI

class SessionDetailFromCalendarViewModel: ObservableObject {

    @Published var transactionViewModel: TransactionViewModel
    @Published var productPerformanceViewModel: ProductPerformanceViewModel
    @Published var salesAnalyticsViewModel: SalesAnalyticsViewModel
    @Published var selectedTab = 0

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
        transactionDataManager: TransactionDataManager,
        sessionDataManager: SessionDataManager
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
    
    /// 獲取當前 tab 的分享內容
    func getCurrentTabShareItems() -> [Any] {
        switch selectedTab {
        case 0: // 交易明細
            return [
                CustomActivityItemSource(
                    csvContent: transactionViewModel.generateCSVContent(),
                    csvFileURL: transactionViewModel.createTempCSVFileURL(),
                    reportTitle: "交易明細報表"
                )
            ]
        case 1: // 產品績效
            return [
                CustomActivityItemSource(
                    csvContent: productPerformanceViewModel.generateTopProductsCSV(),
                    csvFileURL: productPerformanceViewModel.createTopProductsCSVFileURL(),
                    reportTitle: "熱門商品排行報表"
                ),
                CustomActivityItemSource(
                    csvContent: productPerformanceViewModel.generateCategoryAnalysisCSV(),
                    csvFileURL: productPerformanceViewModel.createCategoryAnalysisCSVFileURL(),
                    reportTitle: "類別銷售匯總報表"
                )
            ]
        case 2: // 銷售分析
            return [
                CustomActivityItemSource(
                    csvContent: salesAnalyticsViewModel.generateHourlyAnalysisCSV(),
                    csvFileURL: salesAnalyticsViewModel.createHourlyAnalysisCSVFileURL(),
                    reportTitle: "時段銷售分析報表"
                ),
                CustomActivityItemSource(
                    csvContent: salesAnalyticsViewModel.generatePaymentMethodCSV(),
                    csvFileURL: salesAnalyticsViewModel.createPaymentMethodCSVFileURL(),
                    reportTitle: "支付方式分析報表"
                )
            ]
        default:
            return []
        }
    }
    
    /// 處理當前 tab 的導出成功回調
    func handleCurrentTabExportSuccess() {
        switch selectedTab {
        case 0: // 交易明細
            transactionViewModel.showExportSuccessAlert()
        case 1: // 產品績效
            productPerformanceViewModel.showExportSuccessAlert()
        case 2: // 銷售分析
            salesAnalyticsViewModel.showExportSuccessAlert()
        default:
            break
        }
    }
}
