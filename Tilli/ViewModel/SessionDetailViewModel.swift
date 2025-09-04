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
    
    @Binding var session: SessionModel
    
    var sessionTotalAmount: Double {
        session.transactions.reduce(0) { $0 + $1.totalAmount }
    }
    
    init(session: Binding<SessionModel>) {
        self._session = session
        self.productViewModel = ProductViewModel(session: session)
        self.transactionViewModel = TransactionViewModel(session: session)
    }
    
    // MARK: - DataManager 管理
    
    /// 更新 DataManager 引用給所有子 ViewModel
    func updateDataManagers(
        transactionDataManager: TransactionDataManager,
        sessionDataManager: SessionDataManager,
        productRepository: ProductRepository,
        categoryRepository: CategoryRepository
    ) {
        productViewModel.updateDataManagers(
            transactionDataManager: transactionDataManager,
            sessionDataManager: sessionDataManager,
            productRepository: productRepository,
            categoryRepository: categoryRepository
        )
        
        transactionViewModel.updateDataManagers(
            transactionDataManager: transactionDataManager
        )
    }
}
