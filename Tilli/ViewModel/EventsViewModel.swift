//
//  EventsViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2026/7/29.
//

import SwiftUI

class EventsViewModel: ObservableObject {
    @Published var displayMode: EventsDisplayMode = .list

    private var transactionDataManager: TransactionRepository?

    func updateDataManagers(transactionDataManager: TransactionRepository) {
        self.transactionDataManager = transactionDataManager
    }

    func transactionSummary(for session: SessionModel) -> (count: Int, total: Decimal) {
        guard let manager = transactionDataManager else { return (0, 0) }
        let transactions = manager.fetchTransactions(forSessionId: session.id)
        let total = transactions.reduce(Decimal.zero) { $0 + $1.totalAmount }
        return (transactions.count, total)
    }
}
