//
//  TransactionVoidIndex.swift
//  Tilli
//
//  「交易是否作廢／哪些是有效交易」的唯一答案來源。
//

import Foundation

/// 以 `transactionId` 建立作廢紀錄索引。
///
/// 作廢不改原交易快照；有效交易 = 全部交易排除有作廢紀錄者。
struct TransactionVoidIndex {
    private let recordsByTransactionId: [UUID: TransactionVoidModel]

    /// 同一 `transactionId` 有多筆作廢紀錄時，取 `voidedAt` 最早者
    init(voids: [TransactionVoidModel]) {
        var records: [UUID: TransactionVoidModel] = [:]
        for record in voids {
            if let existing = records[record.transactionId], existing.voidedAt <= record.voidedAt {
                continue
            }
            records[record.transactionId] = record
        }
        self.recordsByTransactionId = records
    }

    /// 空索引（沒有任何作廢紀錄）
    static let empty = TransactionVoidIndex(voids: [])

    func voidRecord(for transactionId: UUID) -> TransactionVoidModel? {
        recordsByTransactionId[transactionId]
    }

    func isVoided(_ transactionId: UUID) -> Bool {
        recordsByTransactionId[transactionId] != nil
    }

    /// 排除已作廢的交易，保留原順序
    func effective(_ transactions: [TransactionModel]) -> [TransactionModel] {
        transactions.filter { !isVoided($0.id) }
    }
}
