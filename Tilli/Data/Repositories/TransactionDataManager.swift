//
//  TransactionDataManager.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/30.
//  Updated by Peiyun on 2025/9/3 - 簡化為查詢專用
//

import CoreData
import SwiftUI

/// TransactionDataManager: 專門用於查詢 Transaction 數據
/// 注意：Transaction 的 CRUD 操作已移至 SessionDataManager
/// 這個 class 主要用於查詢和統計用途
class TransactionDataManager: ObservableObject {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    /// 交易變更觸發器 - 當交易新增/更新時會改變，用於通知 UI 刷新
    @Published var transactionUpdateTrigger = UUID()

    static let shared = TransactionDataManager()

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
        self.context = container.viewContext
    }

    // MARK: - Notification

    /// 通知交易資料已變更，觸發 UI 刷新
    func notifyTransactionsChanged() {
        DispatchQueue.main.async {
            self.transactionUpdateTrigger = UUID()
        }
    }

    // MARK: - Read Operations Only (Transaction CRUD moved to SessionDataManager)

    /// 取得指定 Session 的交易記錄
    /// 按 displayDate（優先 occurredAt，否則 timestamp）排序
    func fetchTransactions(forSessionId sessionId: UUID) -> [TransactionModel] {
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "sessionId == %@", sessionId as CVarArg)

        do {
            let result = try context.fetch(request)
            let transactions = result.compactMap { $0.toModel() }
            // 按 displayDate 排序
            return transactions.sorted { $0.displayDate > $1.displayDate }
        } catch {
            print("Fetch transactions for session failed:", error)
            return []
        }
    }

    /// 根據場次和日期範圍查詢交易記錄（用於多日場次報表）
    /// 使用 displayDate（優先 occurredAt，否則 timestamp）進行日期篩選
    func fetchTransactions(forSessionId sessionId: UUID, dateRange: DateInterval?) -> [TransactionModel] {
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "sessionId == %@", sessionId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let result = try context.fetch(request)
            var transactions = result.compactMap { $0.toModel() }

            // 如果有指定日期範圍，使用 displayDate 進行記憶體內篩選
            if let range = dateRange {
                transactions = transactions.filter { transaction in
                    transaction.displayDate >= range.start && transaction.displayDate <= range.end
                }
            }

            // 按 displayDate 排序
            return transactions.sorted { $0.displayDate > $1.displayDate }
        } catch {
            print("Failed to fetch transactions with date range: \(error)")
            return []
        }
    }
    
    /// 取得指定日期的所有交易記錄（包括孤兒交易）
    /// 使用 displayDate（優先 occurredAt，否則 timestamp）進行日期篩選
    func fetchTransactions(for date: Date) -> [TransactionModel] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        // 用 OR 條件查詢：timestamp 或 occurredAt 在當天範圍內
        let timestampPredicate = NSPredicate(
            format: "timestamp >= %@ AND timestamp < %@",
            startOfDay as NSDate,
            endOfDay as NSDate
        )
        let occurredAtPredicate = NSPredicate(
            format: "occurredAt >= %@ AND occurredAt < %@",
            startOfDay as NSDate,
            endOfDay as NSDate
        )

        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            timestampPredicate,
            occurredAtPredicate
        ])

        do {
            let result = try context.fetch(request)
            let transactions = result.compactMap { $0.toModel() }

            // 使用 displayDate 進行精確篩選
            return transactions
                .filter { $0.displayDate >= startOfDay && $0.displayDate < endOfDay }
                .sorted { $0.displayDate > $1.displayDate }
        } catch {
            print("Fetch transactions for date failed:", error)
            return []
        }
    }
    
    /// 取得指定日期的交易記錄，按SessionId分組
    func fetchTransactionsGroupedBySession(for date: Date) -> [String: [TransactionModel]] {
        let transactions = fetchTransactions(for: date)
        return Dictionary(grouping: transactions) { $0.sessionId.uuidString }
    }

}
