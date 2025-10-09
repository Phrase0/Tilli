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

        // 批次更新產品庫存
        var stockUpdates: [UUID: Int] = [:]
        
        // 首先獲取所有相關產品
        let allProducts = productRepository.fetchProducts(forSessionId: session.id)
        let productDict = Dictionary(uniqueKeysWithValues: allProducts.map { ($0.id, $0) })
        
        // 準備批次更新數據
        for item in summaryItems {
            guard let currentProduct = productDict[item.productId] else {
                print("⚠️ 無法在 CoreData 中找到對應的 productId: \(item.productId)")
                continue
            }
            
            let newStock = max(currentProduct.stock - item.quantity, 0)
            stockUpdates[item.productId] = newStock
        }
        
        // 執行批次更新
        let success = productRepository.batchUpdateProductStock(stockUpdates)
        if !success {
            print("🔴 批次更新產品庫存失敗")
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
