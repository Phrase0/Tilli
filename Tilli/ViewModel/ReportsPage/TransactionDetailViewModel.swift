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

    var transactionNumber: String { transaction.displayNumber }
    var paymentMethodText: String { transaction.paymentMethod.displayName }
    /// 交易當下的幣別
    var currency: String { transaction.currency }

    func formatAmount(_ amount: Decimal) -> String {
        MoneyHelper.format(amount, currencyCode: transaction.currency)
    }
}
