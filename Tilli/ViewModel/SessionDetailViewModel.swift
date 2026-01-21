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

    // MARK: - Export Properties
    @Published var currentShareItems: [Any] = []
    @Published var showingExportSuccessAlert = false

    @Binding var session: SessionModel
    private var transactionDataManager: TransactionRepository?
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
        transactionDataManager: TransactionRepository,
        sessionDataManager: SessionRepository,
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

    /// 準備匯出交易明細
    func prepareExport() {
        currentShareItems = [transactionViewModel.createTempCSVFileURL()]
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

    /// 處理導出成功回調
    func handleExportSuccess() {
        showingExportSuccessAlert = true
    }
}
