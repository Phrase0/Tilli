//
//  InventoryChangeRepository.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/12.
//

import CoreData
import SwiftUI

class InventoryChangeRepository: ObservableObject {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
        self.context = container.viewContext
    }

    // MARK: - Create

    /// 新增庫存異動紀錄
    func addChange(_ change: InventoryChangeModel) {
        let entity = CDInventoryChangeEntity(context: context)
        entity.update(from: change, context: context)
        saveContext()
    }

    /// 批次新增庫存異動紀錄
    func addChanges(_ changes: [InventoryChangeModel]) {
        for change in changes {
            let entity = CDInventoryChangeEntity(context: context)
            entity.update(from: change, context: context)
        }
        saveContext()
    }

    // MARK: - Read

    /// 取得指定產品的所有異動紀錄
    func fetchChanges(forProductId productId: UUID) -> [InventoryChangeModel] {
        let request: NSFetchRequest<CDInventoryChangeEntity> = CDInventoryChangeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "productId == %@", productId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let result = try context.fetch(request)
            return result.map { $0.toModel() }
        } catch {
            print("Fetch inventory changes for product failed:", error)
            return []
        }
    }

    /// 取得指定場次的所有異動紀錄
    func fetchChanges(forSessionId sessionId: UUID) -> [InventoryChangeModel] {
        let request: NSFetchRequest<CDInventoryChangeEntity> = CDInventoryChangeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "sessionId == %@", sessionId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let result = try context.fetch(request)
            return result.map { $0.toModel() }
        } catch {
            print("Fetch inventory changes for session failed:", error)
            return []
        }
    }

    /// 取得指定場次在時間範圍內的異動紀錄
    func fetchChanges(forSessionId sessionId: UUID, in dateInterval: DateInterval) -> [InventoryChangeModel] {
        let request: NSFetchRequest<CDInventoryChangeEntity> = CDInventoryChangeEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "sessionId == %@ AND timestamp >= %@ AND timestamp <= %@",
            sessionId as CVarArg,
            dateInterval.start as CVarArg,
            dateInterval.end as CVarArg
        )
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let result = try context.fetch(request)
            return result.map { $0.toModel() }
        } catch {
            print("Fetch inventory changes for session in date range failed:", error)
            return []
        }
    }

    /// 取得指定產品在時間範圍內的異動紀錄
    func fetchChanges(forProductId productId: UUID, in dateInterval: DateInterval) -> [InventoryChangeModel] {
        let request: NSFetchRequest<CDInventoryChangeEntity> = CDInventoryChangeEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "productId == %@ AND timestamp >= %@ AND timestamp <= %@",
            productId as CVarArg,
            dateInterval.start as CVarArg,
            dateInterval.end as CVarArg
        )
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let result = try context.fetch(request)
            return result.map { $0.toModel() }
        } catch {
            print("Fetch inventory changes for product in date range failed:", error)
            return []
        }
    }

    // MARK: - Delete

    /// 刪除指定的異動紀錄
    func deleteChange(_ changeId: UUID) {
        let request: NSFetchRequest<CDInventoryChangeEntity> = CDInventoryChangeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", changeId as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                context.delete(entity)
                saveContext()
            }
        } catch {
            print("Delete inventory change failed:", error)
        }
    }

    /// 刪除指定產品的所有異動紀錄
    func deleteChanges(forProductId productId: UUID) {
        let request: NSFetchRequest<CDInventoryChangeEntity> = CDInventoryChangeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "productId == %@", productId as CVarArg)

        do {
            let entities = try context.fetch(request)
            for entity in entities {
                context.delete(entity)
            }
            saveContext()
        } catch {
            print("Delete inventory changes for product failed:", error)
        }
    }

    /// 刪除指定場次的所有異動紀錄
    func deleteChanges(forSessionId sessionId: UUID) {
        let request: NSFetchRequest<CDInventoryChangeEntity> = CDInventoryChangeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "sessionId == %@", sessionId as CVarArg)

        do {
            let entities = try context.fetch(request)
            for entity in entities {
                context.delete(entity)
            }
            saveContext()
        } catch {
            print("Delete inventory changes for session failed:", error)
        }
    }

    // MARK: - Save Context

    private func saveContext() {
        do {
            try context.save()
            print("InventoryChange data saved to CoreData")
        } catch {
            print("Core Data save failed:", error)
            context.rollback()
        }
    }
}
