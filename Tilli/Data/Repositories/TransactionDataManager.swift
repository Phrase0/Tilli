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

    @Published var transactions: [TransactionModel] = []

    static let shared = TransactionDataManager()

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
        self.context = container.viewContext
        fetchAllTransactions()
    }

    // MARK: - Read Operations Only (Transaction CRUD moved to SessionDataManager)

    /// 取得所有交易記錄（私有方法，僅用於內部初始化）
    private func fetchAllTransactions() {
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let result = try context.fetch(request)
            transactions = result.compactMap { $0.toModel() }
        } catch {
            print("Fetch transactions failed:", error)
        }
    }

    /// 取得指定 Session 的交易記錄
    func fetchTransactions(forSessionId sessionId: UUID) -> [TransactionModel] {
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "sessionId == %@", sessionId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let result = try context.fetch(request)
            return result.compactMap { $0.toModel() }
        } catch {
            print("Fetch transactions for session failed:", error)
            return []
        }
    }

    /// 根據場次和日期範圍查詢交易記錄（用於多日場次報表）
    func fetchTransactions(forSessionId sessionId: UUID, dateRange: DateInterval?) -> [TransactionModel] {
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()

        var predicates: [NSPredicate] = [
            NSPredicate(format: "sessionId == %@", sessionId as CVarArg)
        ]

        // 如果有指定日期範圍，加入日期條件
        if let range = dateRange {
            predicates.append(
                NSPredicate(format: "timestamp >= %@ AND timestamp <= %@",
                           range.start as CVarArg,
                           range.end as CVarArg)
            )
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let result = try context.fetch(request)
            return result.compactMap { $0.toModel() }
        } catch {
            print("Failed to fetch transactions with date range: \(error)")
            return []
        }
    }
    
    /// 取得指定日期的所有交易記錄（包括孤兒交易）
    func fetchTransactions(for date: Date) -> [TransactionModel] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", startOfDay as NSDate, endOfDay as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let result = try context.fetch(request)
            return result.compactMap { $0.toModel() }
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
