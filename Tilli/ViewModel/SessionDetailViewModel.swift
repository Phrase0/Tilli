//
//  SessionDetailViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/8.
//

import SwiftUI

class SessionDetailViewModel: ObservableObject {

    @Published var productViewModel: ProductViewModel
    @Published var transactionViewModel: TransactionViewModel
    @Published var sessionTotalAmount: Double = 0

    @Binding var session: SessionModel
    private var transactionDataManager: TransactionDataManager?
    
    init(session: Binding<SessionModel>) {
        self._session = session
        self.productViewModel = ProductViewModel(session: session)
        self.transactionViewModel = TransactionViewModel(session: session)
        self.sessionTotalAmount = session.wrappedValue.transactions.reduce(0) { $0 + $1.totalAmount }
    }
    
    // MARK: - DataManager 管理
    
    /// 更新 DataManager 引用給所有子 ViewModel
    func updateDataManagers(
        transactionDataManager: TransactionDataManager,
        sessionDataManager: SessionDataManager,
        productRepository: ProductRepository,
        categoryRepository: CategoryRepository
    ) {
        self.transactionDataManager = transactionDataManager

        productViewModel.updateDataManagers(
            transactionDataManager: transactionDataManager,
            sessionDataManager: sessionDataManager,
            productRepository: productRepository,
            categoryRepository: categoryRepository
        )

        transactionViewModel.updateDataManagers(
            transactionDataManager: transactionDataManager
        )

        updateSessionTotalAmount()
    }

    /// 更新 sessionTotalAmount
    func updateSessionTotalAmount() {
        guard let transactionDataManager = transactionDataManager else {
            sessionTotalAmount = session.transactions.reduce(0) { $0 + $1.totalAmount }
            return
        }

        let transactions = transactionDataManager.fetchTransactions(forSessionId: session.id)
        sessionTotalAmount = transactions.reduce(0) { $0 + $1.totalAmount }
    }
    
    /// 載入數據
    func loadData() {
        productViewModel.loadProducts()
        transactionViewModel.loadData()
    }
}
