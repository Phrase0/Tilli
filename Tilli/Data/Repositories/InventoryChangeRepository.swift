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

    /// 在 context 建立一筆庫存異動 entity，**不存檔**。
    /// 異動一律跟著結帳、作廢或商品存檔一起寫入，由呼叫端的 Repository 和其他變更在同一次 save 完成。
    static func insertChange(
        _ change: InventoryChangeModel,
        event: CDEventEntity,
        product: CDProductEntity?,
        userId: String,
        at date: Date,
        in context: NSManagedObjectContext
    ) {
        let entity = CDInventoryChangeEntity(context: context)
        entity.update(from: change, context: context)
        entity.userId = userId
        entity.markPendingSync(at: date)
        entity.event = event
        entity.eventId = event.id
        entity.product = product
        // TODO: [SYNC-PENDING] 重建同步時，呼叫端存檔成功後 enqueue
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

    /// 儲存成功回傳 true；失敗時 rollback 並回傳 false
    @discardableResult
    private func saveContext() -> Bool {
        do {
            try context.save()
            print("InventoryChange data saved to CoreData")
            return true
        } catch {
            print("Core Data save failed:", error)
            context.rollback()
            return false
        }
    }
}
