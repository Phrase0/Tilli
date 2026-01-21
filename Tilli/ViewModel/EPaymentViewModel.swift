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
    let selectedDiscount: DiscountModel?
    let occurredAt: Date?  // 補記帳時的實際發生時間

    @Published var showDateWarning: Bool = false
    @Published var dateWarningMessage: String = ""

    init(totalAmount: Decimal, session: SessionModel, summaryItems: [SummaryItemModel], selectedDiscount: DiscountModel? = nil, occurredAt: Date? = nil) {
        self.totalAmount = totalAmount
        self.session = session
        self.summaryItems = summaryItems
        self.selectedDiscount = selectedDiscount
        self.occurredAt = occurredAt
    }

    /// 驗證交易日期是否在場次範圍內
    func validateTransactionDate() -> Bool {
        let validation = DateValidationHelper.validateTransactionDate(for: session)
        if !validation.isValid {
            dateWarningMessage = validation.errorMessage ?? "交易日期不在場次範圍內"
            showDateWarning = true
            return false
        }
        return true
    }

    func performCheckout(
        sessionDataManager: SessionRepository,
        productRepository: ProductRepository,
        inventoryChangeRepository: InventoryChangeRepository
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
            sessionTitle: session.title,
            currency: session.currency,
            items: summaryItems,
            totalAmount: totalAmount,
            paymentMethod: .ePayment,
            timestamp: Date(),
            occurredAt: occurredAt,
            discountType: selectedDiscount?.type,
            discountValue: selectedDiscount?.value
        )

        // 使用 SessionDataManager 添加交易記錄
        sessionDataManager.addTransaction(transaction)

        // 記錄庫存異動（銷售出庫）
        let changeTimestamp = occurredAt ?? Date()
        for item in summaryItems {
            let inventoryChange = InventoryChangeModel(
                productId: item.productId,
                change: -item.quantity,
                reason: .salesOut,
                customReason: nil,
                transactionId: transaction.id,
                timestamp: changeTimestamp
            )
            inventoryChangeRepository.addChange(inventoryChange, sessionId: session.id)
        }

        // 直接返回原 session，UI 更新由 onChange(of: checkoutCompleted) 處理
        return session
    }
}
