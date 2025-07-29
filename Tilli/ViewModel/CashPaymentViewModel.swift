//
//  CashPaymentViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/30.
//

import Foundation
import SwiftUI

class CashPaymentViewModel: ObservableObject {
    
    let totalAmount: Int
    let session: SessionModel
    let summaryItems: [SummaryItemModel]

    @Published var receivedAmountText: String = ""
    @Published var errorMessage: String? = nil
    
    var receivedAmount: Int {
        Int(receivedAmountText) ?? 0
    }
    
    var change: Int {
        receivedAmount - totalAmount
    }
    
    var isAmountValid: Bool {
        receivedAmount >= totalAmount
    }
    
    init(totalAmount: Int, session: SessionModel, summaryItems: [SummaryItemModel]) {
        self.totalAmount = totalAmount
        self.session = session
        self.summaryItems = summaryItems
    }

    func performCheckout(transactionDataManager: TransactionDataManager, sessionDataManager: SessionDataManager) {
        // 新增交易紀錄
        let transaction = TransactionModel(
            sessionId: session.id,
            items: summaryItems,
            totalAmount: Double(totalAmount),
            paymentMethod: .cash,
            timestamp: Date()
        )
        transactionDataManager.addTransaction(transaction)

        // 更新產品庫存
        var updatedSession = session
        for item in summaryItems {
            if let index = updatedSession.products.firstIndex(where: { $0.id == item.productId }) {
                updatedSession.products[index].stock -= item.quantity
                if updatedSession.products[index].stock < 0 {
                    updatedSession.products[index].stock = 0
                }
            }
        }

        sessionDataManager.updateSession(updatedSession)
    }
}
