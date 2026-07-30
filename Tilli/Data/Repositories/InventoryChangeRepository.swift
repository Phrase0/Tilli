//
//  InventoryChangeRepository.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/12.
//

import CoreData
import SwiftUI
import FirebaseAuth

class InventoryChangeRepository: ObservableObject {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
        self.context = container.viewContext
    }

    // MARK: - Create

    /// 新增庫存異動紀錄
    func addChange(_ change: InventoryChangeModel, eventId: UUID) {
        guard let eventEntity = fetchEventEntity(by: eventId) else {
            print("Event not found for id: \(eventId)")
            return
        }
        let entity = CDInventoryChangeEntity(context: context)
        entity.update(from: change, context: context)
        entity.userId = Auth.auth().currentUser?.uid ?? UserProfile.guestUserId
        entity.syncStatus = "pending"
        entity.event = eventEntity
        entity.eventId = eventId
        saveContext()
        // 同步到 Firestore
        Task { @MainActor in
            SyncManager.shared.syncInventoryChange(change, eventId: eventId)
        }
    }

    /// 批次新增庫存異動紀錄
    func addChanges(_ changes: [InventoryChangeModel], eventId: UUID) {
        guard let eventEntity = fetchEventEntity(by: eventId) else {
            print("Event not found for id: \(eventId)")
            return
        }
        let currentUserId = Auth.auth().currentUser?.uid ?? UserProfile.guestUserId
        for change in changes {
            let entity = CDInventoryChangeEntity(context: context)
            entity.update(from: change, context: context)
            entity.userId = currentUserId
            entity.syncStatus = "pending"
            entity.event = eventEntity
            entity.eventId = eventId
        }
        saveContext()
        // 批次同步到 Firestore
        Task { @MainActor in
            for change in changes {
                SyncManager.shared.syncInventoryChange(change, eventId: eventId)
            }
        }
    }

    /// 根據 eventId 取得 CDEventEntity
    private func fetchEventEntity(by eventId: UUID) -> CDEventEntity? {
        let request: NSFetchRequest<CDEventEntity> = CDEventEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", eventId as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
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
    func fetchChanges(forEventId eventId: UUID) -> [InventoryChangeModel] {
        let request: NSFetchRequest<CDInventoryChangeEntity> = CDInventoryChangeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "event.id == %@", eventId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let result = try context.fetch(request)
            return result.map { $0.toModel() }
        } catch {
            print("Fetch inventory changes for event failed:", error)
            return []
        }
    }

    /// 取得指定場次在時間範圍內的異動紀錄
    func fetchChanges(forEventId eventId: UUID, in dateInterval: DateInterval) -> [InventoryChangeModel] {
        let request: NSFetchRequest<CDInventoryChangeEntity> = CDInventoryChangeEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "event.id == %@ AND timestamp >= %@ AND timestamp <= %@",
            eventId as CVarArg,
            dateInterval.start as CVarArg,
            dateInterval.end as CVarArg
        )
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let result = try context.fetch(request)
            return result.map { $0.toModel() }
        } catch {
            print("Fetch inventory changes for event in date range failed:", error)
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

    /// 刪除指定產品的所有庫存異動（本地 CoreData）
    /// - Returns: 被刪除的 InventoryChange IDs（供 Sync 使用）
    func deleteChanges(forProductId productId: UUID) -> [UUID] {
        let request: NSFetchRequest<CDInventoryChangeEntity> = CDInventoryChangeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "productId == %@", productId as CVarArg)

        do {
            let entities = try context.fetch(request)
            let deletedIds = entities.map { $0.id }

            for entity in entities {
                context.delete(entity)
            }

            saveContext()
            print("🗑️ 已刪除 \(entities.count) 筆庫存異動（productId: \(productId)）")
            return deletedIds
        } catch {
            print("刪除庫存異動失敗:", error)
            return []
        }
    }

    /// 批次刪除指定多個產品的所有庫存異動（本地 CoreData）
    /// - Returns: 被刪除的 InventoryChange IDs（供 Sync 使用）
    func deleteChanges(forProductIds productIds: [UUID]) -> [UUID] {
        guard !productIds.isEmpty else { return [] }

        let request: NSFetchRequest<CDInventoryChangeEntity> = CDInventoryChangeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "productId IN %@", productIds)

        do {
            let entities = try context.fetch(request)
            let deletedIds = entities.map { $0.id }

            for entity in entities {
                context.delete(entity)
            }

            saveContext()
            print("🗑️ 已批次刪除 \(entities.count) 筆庫存異動（\(productIds.count) 個產品）")
            return deletedIds
        } catch {
            print("批次刪除庫存異動失敗:", error)
            return []
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
