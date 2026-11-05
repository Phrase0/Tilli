//
//  TransactionDetailViewModel.swift
//  Tilli
//
//  交易明細頁：讀這一筆交易的快照（不回頭查場次設定），作廢狀態從 `EventDataSource.voidIndex` 取。
//  作廢寫入由彈出的作廢視窗（`VoidTransactionViewModel`）負責，寫完以 callback 通知這頁重新讀取。
//

import Foundation

@MainActor
final class TransactionDetailViewModel: ObservableObject {
    let transaction: TransactionModel
    /// 商品列與優惠明細（從交易快照還原）
    let breakdown: TransactionBreakdown
    /// 作廢視窗也用同一份場次資料
    let dataSource: EventDataSource

    /// 這筆交易的作廢紀錄（未作廢為 nil）
    @Published private(set) var voidRecord: TransactionVoidModel?

    init(transaction: TransactionModel, dataSource: EventDataSource) {
        self.transaction = transaction
        self.breakdown = TransactionBreakdown(transaction: transaction)
        self.dataSource = dataSource
        self.voidRecord = dataSource.voidIndex.voidRecord(for: transaction.id)
    }

    var isVoided: Bool { voidRecord != nil }

    /// 作廢視窗寫入並重新載入 dataSource 後呼叫
    func refreshVoidState() {
        voidRecord = dataSource.voidIndex.voidRecord(for: transaction.id)
    }

    /// 已作廢卡片的「庫存」列：場次異動中有這筆交易的作廢回流（`.voidRestock`）才算已回流。
    /// 不看作廢紀錄的 `restocked`（那是使用者的選擇；交易當初沒有銷售出庫異動時，選了回流也沒有東西加回庫存）。
    var restockText: String {
        let restocked = dataSource.inventoryChanges.contains {
            $0.reason == .voidRestock && $0.transactionId == transaction.id
        }
        return restocked
            // 已回流
            ? String.localized("voidedRestocked")
            // 未回流
            : String.localized("voidedNotRestocked")
    }

    var transactionNumber: String { transaction.displayNumber }
    var paymentMethodText: String { transaction.paymentMethod.displayName }
    /// 交易當下的幣別
    var currency: String { transaction.currency }

    func formatAmount(_ amount: Decimal) -> String {
        MoneyHelper.format(amount, currencyCode: transaction.currency)
    }
}
