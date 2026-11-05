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
    @Published var showCheckoutFailed = false
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

    /// 結帳寫入：交易、銷售扣庫存異動、商品庫存一次存檔（`EventRepository.recordCheckout`）。
    /// 失敗時什麼都沒寫入，設定 `showCheckoutFailed` 並回傳 false，畫面留在付款頁讓使用者重試。
    func performCheckout(
        eventDataManager: EventRepository,
        productRepository: ProductRepository
    ) -> Bool {
        // 同一商品多列會累加扣除
        let currentStock = Dictionary(
            uniqueKeysWithValues: productRepository.fetchProducts(forEventId: event.id).map { ($0.id, $0.stock) }
        )
        let stockUpdates = CheckoutRecorder.stockUpdates(for: summaryItems, currentStock: currentStock)

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

        guard eventDataManager.recordCheckout(record, stockUpdates: stockUpdates) else {
            showCheckoutFailed = true
            return false
        }
        return true
    }
}
