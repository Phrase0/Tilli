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
    let event: EventModel
    let summaryItems: [SummaryItemModel]
    let appliedDiscounts: [AppliedDiscount]
    let bundleDeductions: [RevenueAllocator.BundleDeduction]
    let occurredAt: Date?  // 補記帳時的實際發生時間

    @Published var showDateWarning: Bool = false
    @Published var dateWarningMessage: String = ""

    init(totalAmount: Decimal, event: EventModel, summaryItems: [SummaryItemModel], appliedDiscounts: [AppliedDiscount] = [], bundleDeductions: [RevenueAllocator.BundleDeduction] = [], occurredAt: Date? = nil) {
        self.totalAmount = totalAmount
        self.event = event
        self.summaryItems = summaryItems
        self.appliedDiscounts = appliedDiscounts
        self.bundleDeductions = bundleDeductions
        self.occurredAt = occurredAt
    }

    /// 驗證交易日期是否在場次範圍內
    func validateTransactionDate() -> Bool {
        let validation = DateValidationHelper.validateTransactionDate(for: event)
        if !validation.isValid {
            // 交易日期不在場次範圍內
            dateWarningMessage = validation.errorMessage ?? String.localized("paymentDateOutOfRange")
            showDateWarning = true
            return false
        }
        return true
    }

    func performCheckout(
        eventDataManager: EventRepository,
        productRepository: ProductRepository,
        inventoryChangeRepository: InventoryChangeRepository
    ) {
        // 批次更新產品庫存（同一商品多列會累加）
        let currentStock = Dictionary(
            uniqueKeysWithValues: productRepository.fetchProducts(forEventId: event.id).map { ($0.id, $0.stock) }
        )
        let stockUpdates = CheckoutRecorder.stockUpdates(for: summaryItems, currentStock: currentStock)
        if !productRepository.batchUpdateProductStock(stockUpdates) {
            print("🔴 批次更新產品庫存失敗")
        }

        let record = CheckoutRecorder.makeRecord(
            event: event,
            items: summaryItems,
            bundleDeductions: bundleDeductions,
            appliedDiscounts: appliedDiscounts,
            totalAmount: totalAmount,
            paymentMethod: .ePayment,
            occurredAt: occurredAt,
            now: Date()
        )

        eventDataManager.addTransaction(record.transaction)
        for change in record.inventoryChanges {
            inventoryChangeRepository.addChange(change, eventId: event.id)
        }
    }
}
