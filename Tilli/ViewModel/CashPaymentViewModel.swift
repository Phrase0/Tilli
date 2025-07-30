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

    func performCheckout(
        transactionDataManager: TransactionDataManager,
        sessionDataManager: SessionDataManager,
        productDataManager: ProductDataManager
    ) -> SessionModel {


        for item in summaryItems {
            guard let matchedProduct = productDataManager.products.first(where: { $0.id == item.productId }) else {
                print("無法在 CoreData 中找到對應的 productId: \(item.productId)")
                continue
            }
            var updatedProduct = matchedProduct
            updatedProduct.stock = max(updatedProduct.stock - item.quantity, 0)
            
            productDataManager.updateProduct(updatedProduct)
        }

        let transaction = TransactionModel(
            sessionId: session.id,
            items: summaryItems,
            totalAmount: Double(totalAmount),
            paymentMethod: .cash,
            timestamp: Date()
        )

        transactionDataManager.addTransaction(transaction)
        sessionDataManager.updateSession(session)

        return session
    }



}
