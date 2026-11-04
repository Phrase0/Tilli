//
//  TransactionVoidModel.swift
//  Tilli
//

import Foundation

// MARK: - 作廢原因
enum VoidReason: String, Codable, CaseIterable {
    case inputError         // 輸入錯誤
    case customerCancelled  // 客人取消
    case returned           // 退貨
    case other              // 其他

    var displayName: String {
        switch self {
        case .inputError: return String.localized("voidReasonInputError") // 輸入錯誤
        case .customerCancelled: return String.localized("voidReasonCustomerCancelled") // 客人取消
        case .returned: return String.localized("voidReasonReturned") // 退貨
        case .other: return String.localized("voidReasonOther") // 其他
        }
    }
}

// MARK: - 作廢紀錄（流水帳，只新增）
struct TransactionVoidModel: Identifiable, Equatable {
    let id: UUID
    let transactionId: UUID
    let eventId: UUID
    let voidedAt: Date
    let reason: VoidReason
    let note: String?        // 空字串存 nil
    let restocked: Bool      // 作廢時是否回補庫存

    init(id: UUID, transactionId: UUID, eventId: UUID, voidedAt: Date,
         reason: VoidReason, note: String?, restocked: Bool) {
        self.id = id
        self.transactionId = transactionId
        self.eventId = eventId
        self.voidedAt = voidedAt
        self.reason = reason
        self.note = (note?.isEmpty ?? true) ? nil : note
        self.restocked = restocked
    }
}

// MARK: - CoreData 轉換
extension TransactionVoidModel {
    init(entity: CDTransactionVoidEntity) {
        self.init(
            id: entity.id,
            transactionId: entity.transactionId,
            eventId: entity.eventId,
            voidedAt: entity.voidedAt,
            reason: VoidReason(rawValue: entity.reason) ?? .other,
            note: entity.note,
            restocked: entity.restocked
        )
    }
}
