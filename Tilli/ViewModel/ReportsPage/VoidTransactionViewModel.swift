//
//  VoidTransactionViewModel.swift
//  Tilli
//
//  作廢視窗：選原因、補充說明、庫存回流與否，確認後寫入作廢紀錄（與回流異動、商品庫存）。
//  視窗每次打開都新建這個 VM，所以原因與庫存方式一律從未選開始。
//  寫入邊界在 `performVoid`：已作廢、原因或庫存方式未選一律拒絕（由 `VoidRecorder` 判斷），不依賴 View 的 disabled。
//

import Foundation

@MainActor
final class VoidTransactionViewModel: ObservableObject {

    enum VoidOutcome: Equatable {
        /// 作廢紀錄（與回流異動、庫存）一次寫入成功
        case done
        /// 寫入前被拒絕（已作廢、原因或庫存方式未選），什麼都沒寫
        case rejected
        /// 存檔失敗，什麼都沒寫
        case voidFailed
    }

    let transaction: TransactionModel
    private let dataSource: EventDataSource

    @Published var selectedReason: VoidReason?
    @Published var note: String = ""
    /// nil = 未選；true = 回流；false = 不回流
    @Published var restockChoice: Bool?

    init(transaction: TransactionModel, dataSource: EventDataSource) {
        self.transaction = transaction
        self.dataSource = dataSource
    }

    var transactionNumber: String { transaction.displayNumber }

    var amountText: String {
        MoneyHelper.format(transaction.totalAmount, currencyCode: transaction.currency)
    }

    var canSubmit: Bool {
        !dataSource.voidIndex.isVoided(transaction.id) && selectedReason != nil && restockChoice != nil
    }

    /// 作廢 %@（%@）？
    var confirmTitle: String {
        String.localized("voidConfirmTitle \(transactionNumber) \(amountText)")
    }

    /// 作廢後無法還原。＋換行＋庫存：回流／庫存：不回流
    var confirmMessage: String {
        let restockLine = restockChoice == true
            // 庫存：回流
            ? String.localized("voidConfirmRestock")
            // 庫存：不回流
            : String.localized("voidConfirmNoRestock")
        // 作廢後無法還原。
        return String.localized("voidConfirmMessage") + "\n" + restockLine
    }

    /// 作廢紀錄、（回流時）作廢回流異動、商品庫存一次存檔（`EventRepository.recordVoid`），失敗時都不留。
    func performVoid(eventRepository: EventRepository, now: Date = Date()) -> VoidOutcome {
        // 先重新載入，作廢判斷與目前庫存都用最新資料
        dataSource.reload()

        let result = VoidRecorder.makeRecord(
            transaction: transaction,
            salesChanges: dataSource.inventoryChanges,
            voidIndex: dataSource.voidIndex,
            reason: selectedReason,
            note: note,
            restock: restockChoice,
            now: now
        )
        guard case .success(let record) = result else { return .rejected }

        let currentStock = Dictionary(uniqueKeysWithValues: dataSource.products.map { ($0.id, $0.stock) })
        let stockUpdates = VoidRecorder.stockUpdates(for: record.inventoryChanges, currentStock: currentStock)
        guard eventRepository.recordVoid(record, stockUpdates: stockUpdates) else { return .voidFailed }

        dataSource.reload()
        return .done
    }
}
