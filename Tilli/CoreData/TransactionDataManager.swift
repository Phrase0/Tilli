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

    // MARK: - Statistics Methods
    
    /// 計算指定 Session 的總營收
    func calculateTotalRevenue(forSessionId sessionId: UUID) -> Double {
        let transactions = fetchTransactions(forSessionId: sessionId)
        return transactions.reduce(0) { $0 + $1.totalAmount }
    }
    
    /// 計算指定日期範圍的總營收
    func calculateTotalRevenue(from startDate: Date, to endDate: Date) -> Double {
        let transactions = fetchTransactions(from: startDate, to: endDate)
        return transactions.reduce(0) { $0 + $1.totalAmount }
    }
    
    /// 計算最受歡迎的產品（根據銷售數量）
    func getMostPopularProducts(limit: Int = 10) -> [(productId: UUID, productName: String, totalQuantity: Int)] {
        var productStats: [UUID: (name: String, quantity: Int)] = [:]
        
        for transaction in self.transactions {
            for item in transaction.items {
                if let existing = productStats[item.productId] {
                    productStats[item.productId] = (existing.name, existing.quantity + item.quantity)
                } else {
                    productStats[item.productId] = (item.name, item.quantity)
                }
            }
        }
        
        return productStats.map { (productId: $0.key, productName: $0.value.name, totalQuantity: $0.value.quantity) }
                          .sorted { $0.totalQuantity > $1.totalQuantity }
                          .prefix(limit)
                          .map { $0 }
    }
}
