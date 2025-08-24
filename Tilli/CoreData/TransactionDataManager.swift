//
//  SessinDataManager.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/30.
//

import CoreData
import SwiftUI

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

    // MARK: - Create
    func addTransaction(_ model: TransactionModel) {
        let sessionRequest: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        sessionRequest.predicate = NSPredicate(format: "id == %@", model.sessionId as CVarArg)

        do {
            guard let sessionEntity = try context.fetch(sessionRequest).first else {
                print("找不到對應 session，無法加入 transaction")
                return
            }

            let entity = CDTransactionEntity(context: context)
            entity.update(from: model, context: context)

            sessionEntity.addToTransactions(entity)

            saveContext()
            fetchAllTransactions()

        } catch {
            print("加入 transaction 失敗:", error)
        }
    }

    // MARK: - Read
    func fetchAllTransactions() {
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()

        do {
            let result = try context.fetch(request)
            transactions = result.compactMap { $0.toModel() }
        } catch {
            print("Fetch transactions failed:", error)
        }
    }

    func fetchTransactions(forSessionId sessionId: UUID) -> [TransactionModel] {
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "sessionId == %@", sessionId as CVarArg)

        do {
            let result = try context.fetch(request)
            return result.compactMap { $0.toModel() }
        } catch {
            print("Fetch transactions for session failed:", error)
            return []
        }
    }
    

    // MARK: - Update
    func updateTransaction(_ model: TransactionModel) {
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                entity.update(from: model, context: context)
                saveContext()
                fetchAllTransactions()
            }
        } catch {
            print("Update transaction failed:", error)
        }
    }

    // MARK: - Delete
    func deleteTransaction(_ model: TransactionModel) {
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                context.delete(entity)
                saveContext()
                fetchAllTransactions()
            }
        } catch {
            print("Delete transaction failed:", error)
        }
    }

    // MARK: - Save
    private func saveContext() {
        do {
            try context.save()
            print("Transaction saved to Core Data")
        } catch {
            print("Core Data save failed:", error)
            context.rollback()
        }
    }
}
