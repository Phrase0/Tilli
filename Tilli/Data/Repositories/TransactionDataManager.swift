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
    
    /// 取得所有交易記錄
    func fetchAllTransactions() {
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
    
    /// 取得指定日期範圍的交易記錄
    func fetchTransactions(from startDate: Date, to endDate: Date) -> [TransactionModel] {
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp <= %@", startDate as NSDate, endDate as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let result = try context.fetch(request)
            return result.compactMap { $0.toModel() }
        } catch {
            print("Fetch transactions for date range failed:", error)
            return []
        }
    }
    
    /// 取得指定日期的所有交易記錄（包括孤兒交易）
    func fetchTransactions(for date: Date) -> [TransactionModel] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return fetchTransactions(from: startOfDay, to: endOfDay)
    }
    
    /// 取得指定日期的交易記錄，按SessionId分組
    func fetchTransactionsGroupedBySession(for date: Date) -> [String: [TransactionModel]] {
        let transactions = fetchTransactions(for: date)
        return Dictionary(grouping: transactions) { $0.sessionId.uuidString }
    }

}
