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
        /// 作廢紀錄（與回流）都寫入成功
        case done
        /// 寫入前被拒絕（已作廢、原因或庫存方式未選），什麼都沒寫
        case rejected
        /// 作廢紀錄寫入失敗，什麼都沒寫
        case voidFailed
        /// 作廢紀錄已寫入，但商品庫存回流失敗
        case restockFailed
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

    /// 寫入順序：作廢紀錄 → （回流時）庫存異動 → 商品庫存 → 重新載入 dataSource。
    /// 作廢紀錄是判斷「已作廢」的依據，先寫它；它失敗就什麼都不寫。
    /// 庫存異動存檔成功才更新商品庫存；異動或庫存任一失敗回傳 `.restockFailed`。
    func performVoid(
        eventRepository: EventRepository,
        productRepository: ProductRepository,
        inventoryChangeRepository: InventoryChangeRepository,
        now: Date = Date()
    ) -> VoidOutcome {
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

        guard eventRepository.addVoid(record.void) else { return .voidFailed }

        var outcome = VoidOutcome.done
        if !record.inventoryChanges.isEmpty {
            if inventoryChangeRepository.addChanges(record.inventoryChanges, eventId: transaction.eventId) {
                let currentStock = Dictionary(uniqueKeysWithValues: dataSource.products.map { ($0.id, $0.stock) })
                let stockUpdates = VoidRecorder.stockUpdates(for: record.inventoryChanges, currentStock: currentStock)
                if !productRepository.batchUpdateProductStock(stockUpdates) {
                    outcome = .restockFailed
                }
            } else {
                outcome = .restockFailed
            }
        }

        dataSource.reload()
        return outcome
    }
}
