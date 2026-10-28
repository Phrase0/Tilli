//
//  CheckoutRecorder.swift
//  Tilli
//
//  結帳寫入的唯一計算：現金／電子支付兩個 VM 共用，純函式、不碰 Repository。
//

import Foundation

enum CheckoutRecorder {

    struct Record {
        let transaction: TransactionModel
        let inventoryChanges: [InventoryChangeModel]
    }

    /// 組出要寫入的交易與庫存異動（每列一筆）。
    /// 折扣在這裡對「扣掉套餐／組合差額後的小計」收斂，不依賴呼叫端先算對。
    static func makeRecord(
        event: EventModel,
        items: [SummaryItemModel],
        bundleDeductions: [RevenueAllocator.BundleDeduction],
        appliedDiscounts: [AppliedDiscount],
        totalAmount: Decimal,
        paymentMethod: PaymentMethod,
        occurredAt: Date?,
        now: Date
    ) -> Record {
        let deductionTotal = bundleDeductions.reduce(Decimal(0)) { MoneyHelper.add($0, $1.amount) }
        let subtotalAfterBundles = MoneyHelper.subtract(items.subtotal, deductionTotal)

        let safeDiscounts = DiscountCalculator.sanitized(
            appliedDiscounts,
            subtotal: subtotalAfterBundles
        )

        // 結帳當下就把折扣攤到每一項，報表只做加總（FEATURE_PLAN_V1.md §7）
        let allocatedItems = RevenueAllocator.allocate(
            items,
            bundles: bundleDeductions,
            discounts: safeDiscounts,
            currency: event.currency
        )

        let transaction = TransactionModel(
            eventId: event.id,
            eventTitle: event.title,
            currency: event.currency,
            items: allocatedItems,
            totalAmount: totalAmount,
            paymentMethod: paymentMethod,
            timestamp: now,
            occurredAt: occurredAt,
            appliedDiscounts: safeDiscounts
        )

        let changeTimestamp = occurredAt ?? now
        let changes = items.map { item in
            let isFixedBundle = item.bundleKind == .fixed
            return InventoryChangeModel(
                productId: item.productId,
                change: -item.quantity,
                reason: .salesOut,
                customReason: nil,
                transactionId: transaction.id,
                timestamp: changeTimestamp,
                bundleId: isFixedBundle ? item.bundleId : nil,
                bundleName: isFixedBundle ? item.bundleName : nil
            )
        }

        return Record(transaction: transaction, inventoryChanges: changes)
    }

    /// 各商品結帳後的庫存。同一商品出現多列（例如單點＋套餐內）時累加扣除；找不到商品的列略過。
    static func stockUpdates(for items: [SummaryItemModel], currentStock: [UUID: Int]) -> [UUID: Int] {
        var sold: [UUID: Int] = [:]
        for item in items where currentStock[item.productId] != nil {
            sold[item.productId, default: 0] += item.quantity
        }
        return sold.reduce(into: [:]) { result, entry in
            result[entry.key] = max((currentStock[entry.key] ?? 0) - entry.value, 0)
        }
    }
}
