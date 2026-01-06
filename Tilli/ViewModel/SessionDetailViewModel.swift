//
//  SessionDetailViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/8.
//

import SwiftUI
import Foundation
import Combine

class SessionDetailViewModel: ObservableObject {

    @Published var productViewModel: ProductViewModel
    @Published var transactionViewModel: TransactionViewModel
    @Published var sessionTotalAmount: Decimal = 0
    @Published var currentShareItems: [Any] = []

    @Binding var session: SessionModel
    private var transactionDataManager: TransactionDataManager?
    private var currentExportTab: Int = 0
    private var cancellables = Set<AnyCancellable>()

    init(session: Binding<SessionModel>) {
        self._session = session
        self.productViewModel = ProductViewModel(session: session)
        self.transactionViewModel = TransactionViewModel(session: session)
        self.sessionTotalAmount = 0

        // 轉發子 ViewModel 的變化通知
        productViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        transactionViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - DataManager 管理
    
    /// 更新 DataManager 引用給所有子 ViewModel
    func updateDataManagers(
        transactionDataManager: TransactionDataManager,
        sessionDataManager: SessionDataManager,
        productRepository: ProductRepository
    ) {
        self.transactionDataManager = transactionDataManager

        productViewModel.updateDataManagers(
            transactionDataManager: transactionDataManager,
            sessionDataManager: sessionDataManager,
            productRepository: productRepository
        )

        transactionViewModel.updateDataManagers(
            transactionDataManager: transactionDataManager
        )

        updateSessionTotalAmount()
    }

    /// 更新 sessionTotalAmount
    func updateSessionTotalAmount() {
        guard let transactionDataManager = transactionDataManager else {
            sessionTotalAmount = 0
            return
        }

        let transactions = transactionDataManager.fetchTransactions(forSessionId: session.id)
        sessionTotalAmount = transactions.reduce(0) { MoneyHelper.add($0, $1.totalAmount) }
    }
    
    /// 載入數據
    func loadData() {
        productViewModel.loadProducts()
        transactionViewModel.loadData()
    }
    
    // MARK: - CSV Export Management
    
    /// 執行指定 tab 的 CSV 導出準備
    func exportTabCSV(tabIndex: Int) {
        currentExportTab = tabIndex
        // 準備分享內容 - 所有 tab 都直接準備分享
        currentShareItems = getTabShareItems(tabIndex: tabIndex)
    }
    
    /// 檢查指定 tab 是否可以導出
    func isTabExportDisabled(tabIndex: Int) -> Bool {
        switch tabIndex {
        case 0: // 商品頁
            return true
        case 1: // 交易明細
            return transactionViewModel.transactions.isEmpty
        default:
            return true
        }
    }
    
    /// 獲取指定 tab 的分享內容
    func getTabShareItems(tabIndex: Int) -> [Any] {
        switch tabIndex {
        case 1: // 交易明細
            return [
                CustomActivityItemSource(
                    csvContent: transactionViewModel.generateCSVContent(),
                    csvFileURL: transactionViewModel.createTempCSVFileURL(),
                    reportTitle: "交易明細報表"
                )
            ]
        default:
            return []
        }
    }
    
    /// 處理導出成功回調
    func handleCurrentTabExportSuccess() {
        switch currentExportTab {
        case 1: // 交易明細
            transactionViewModel.showExportSuccessAlert()
        default:
            break
        }
    }
}
