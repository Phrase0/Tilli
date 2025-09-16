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
        transactionViewModel.loadTransactions()
        productPerformanceViewModel.loadData()
        salesAnalyticsViewModel.loadData()
    }
}