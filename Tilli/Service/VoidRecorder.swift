//
//  VoidRecorder.swift
//  Tilli
//
//  作廢寫入的唯一計算：組出作廢紀錄與庫存回流異動，純函式、不碰 Repository。
//

import Foundation

enum VoidRecorder {

    enum Rejection: Error, Equatable {
        case alreadyVoided
        case missingReason
        case missingRestockChoice
    }

    struct Record {
        let void: TransactionVoidModel
        let inventoryChanges: [InventoryChangeModel]
    }

    /// 組出要寫入的作廢紀錄與回流異動。已作廢、原因或回流選擇為 nil 一律拒絕。
    /// `salesChanges` 可傳該場次全部異動，這裡只取這筆交易的 `.salesOut`。
    static func makeRecord(
        transaction: TransactionModel,
        salesChanges: [InventoryChangeModel],
        voidIndex: TransactionVoidIndex,
        reason: VoidReason?,
        note: String,
        restock: Bool?,
        now: Date
    ) -> Result<Record, Rejection> {
        if voidIndex.isVoided(transaction.id) { return .failure(.alreadyVoided) }
        guard let reason else { return .failure(.missingReason) }
        guard let restock else { return .failure(.missingRestockChoice) }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let voidModel = TransactionVoidModel(
            id: UUID(),
            transactionId: transaction.id,
            eventId: transaction.eventId,
            voidedAt: now,
            reason: reason,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            restocked: restock
        )

        let restockChanges: [InventoryChangeModel] = restock
            ? salesChanges
                .filter { $0.reason == .salesOut && $0.transactionId == transaction.id }
                .map { original in
                    InventoryChangeModel(
                        productId: original.productId,
                        change: -original.change,
                        reason: .voidRestock,
                        customReason: nil,
                        transactionId: transaction.id,
                        timestamp: now,
                        eventId: original.eventId,
                        bundleId: original.bundleId,
                        bundleName: original.bundleName
                    )
                }
            : []

        return .success(Record(void: voidModel, inventoryChanges: restockChanges))
    }

    /// 回流後的庫存。同一商品出現多列時累加；找不到商品的列略過。
    static func stockUpdates(for changes: [InventoryChangeModel], currentStock: [UUID: Int]) -> [UUID: Int] {
        var restored: [UUID: Int] = [:]
        for change in changes where currentStock[change.productId] != nil {
            restored[change.productId, default: 0] += change.change
        }
        return restored.reduce(into: [:]) { result, entry in
            result[entry.key] = (currentStock[entry.key] ?? 0) + entry.value
        }
    }
}
