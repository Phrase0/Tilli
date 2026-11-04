//
//  TransactionDetailViewModel.swift
//  Tilli
//
//  交易明細頁（唯讀）：只讀這一筆交易的快照，不回頭查場次設定。
//

import Foundation

@MainActor
final class TransactionDetailViewModel: ObservableObject {
    let transaction: TransactionModel
    /// 商品列與優惠明細（從交易快照還原）
    let breakdown: TransactionBreakdown

    init(transaction: TransactionModel) {
        self.transaction = transaction
        self.breakdown = TransactionBreakdown(transaction: transaction)
    }

    var transactionNumber: String { transaction.displayNumber }
    var paymentMethodText: String { transaction.paymentMethod.displayName }
    /// 交易當下的幣別
    var currency: String { transaction.currency }

    func formatAmount(_ amount: Decimal) -> String {
        MoneyHelper.format(amount, currencyCode: transaction.currency)
    }
}
