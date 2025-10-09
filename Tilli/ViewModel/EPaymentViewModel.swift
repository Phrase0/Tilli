//
//  EPaymentViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/10/9.
//

import Foundation
import SwiftUI

class EPaymentViewModel: ObservableObject {

    let totalAmount: Decimal
    let session: SessionModel
    let summaryItems: [SummaryItemModel]

    init(totalAmount: Decimal, session: SessionModel, summaryItems: [SummaryItemModel]) {
        self.totalAmount = totalAmount
        self.session = session
        self.summaryItems = summaryItems
    }

    func performCheckout(
        sessionDataManager: SessionDataManager,
        productRepository: ProductRepository
    ) -> SessionModel {

        // 更新產品庫存
        for item in summaryItems {
            let allProducts = productRepository.fetchProducts(forSessionId: session.id)
            guard let matchedProduct = allProducts.first(where: { $0.id == item.productId }) else {
                print("無法在 CoreData 中找到對應的 productId: \(item.productId)")
                continue
            }

            var updatedProduct = matchedProduct
            updatedProduct.stock = max(updatedProduct.stock - item.quantity, 0)

            productRepository.updateProduct(updatedProduct.id, productModel: updatedProduct)
        }

        // 創建交易記錄
        let transaction = TransactionModel(
            sessionId: session.id,
            items: summaryItems,
            totalAmount: totalAmount,
            paymentMethod: .ePayment,
            timestamp: Date()
        )

        // 使用 SessionDataManager 添加交易記錄
        sessionDataManager.addTransaction(transaction)

        // 返回更新後的 session（通過 SessionDataManager 重新獲取）
        return sessionDataManager.fetchSession(by: session.id) ?? session
    }
}
