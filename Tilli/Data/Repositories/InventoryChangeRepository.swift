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
        entity.userId = Auth.auth().currentUser?.uid ?? UserProfileModel.guestUserId
        entity.markPendingSync()
        entity.event = eventEntity
        entity.eventId = eventId
        entity.product = fetchProductEntity(by: change.productId)
        saveContext()
        // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md
    }

    /// 批次新增庫存異動紀錄
    func addChanges(_ changes: [InventoryChangeModel], eventId: UUID) {
        guard let eventEntity = fetchEventEntity(by: eventId) else {
            print("Event not found for id: \(eventId)")
            return
        }
        let currentUserId = Auth.auth().currentUser?.uid ?? UserProfileModel.guestUserId
        // 一次撈出這批用到的 product entity，避免每筆異動各查一次
        let productEntities = fetchProductEntities(by: Set(changes.map { $0.productId }))
        let now = Date()
        for change in changes {
            let entity = CDInventoryChangeEntity(context: context)
            entity.update(from: change, context: context)
            entity.userId = currentUserId
            entity.markPendingSync(at: now)
            entity.event = eventEntity
            entity.eventId = eventId
            entity.product = productEntities[change.productId]
        }
        saveContext()
        // TODO: [SYNC-PENDING] 重建同步時在此 enqueue，見 ARCHITECTURE.md
    }

    /// 根據 eventId 取得 CDEventEntity
    private func fetchEventEntity(by eventId: UUID) -> CDEventEntity? {
        let request: NSFetchRequest<CDEventEntity> = CDEventEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", eventId as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// 根據 productId 取得 CDProductEntity（接 `product` relationship 用）
    private func fetchProductEntity(by productId: UUID) -> CDProductEntity? {
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productId as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// 批次取得多個 CDProductEntity，以 id 為索引
    private func fetchProductEntities(by productIds: Set<UUID>) -> [UUID: CDProductEntity] {
        guard !productIds.isEmpty else { return [:] }
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", Array(productIds))
        let entities = (try? context.fetch(request)) ?? []
        return Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
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
