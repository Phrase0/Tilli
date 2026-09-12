//
//  LocalDataManager.swift
//  Tilli
//
//  Created by Peiyun on 2026/9/12.
//
//  純本機的資料管理：歸戶、清除、存在性判斷。
//  （由原 Data/Sync/SyncManager.swift 抽出 —— 這些是 CoreData 操作，跟雲端同步無關）
//
//  ⚠️ 這裡不做任何網路行為。重建同步時，同步層應該【呼叫】這裡，而不是把這些邏輯搬回去。
//  見 ARCHITECTURE.md §8。
//

import Foundation
import CoreData

/// 本機資料管理（登入歸戶、登出清除）
final class LocalDataManager {

    static let shared = LocalDataManager()

    private let context: NSManagedObjectContext

    /// 受 userId 標記的 entity（`clearAll` 靠 cascade，這裡是歸戶用的完整清單）
    private static let userOwnedEntityNames = [
        "CDEventEntity",
        "CDCategoryEntity",
        "CDProductEntity",
        "CDTransactionEntity",
        "CDInventoryChangeEntity",
        "CDQRCodeEntity"
    ]

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }

    // MARK: - 存在性判斷

    /// 本機是否有指定使用者的資料（登入時判斷要不要做歸戶）
    func hasLocalData(for userId: String) -> Bool {
        let eventRequest: NSFetchRequest<CDEventEntity> = CDEventEntity.fetchRequest()
        eventRequest.predicate = NSPredicate(format: "userId == %@", userId)
        if (try? context.count(for: eventRequest)) ?? 0 > 0 { return true }

        // 訪客可能只有收款 QRCode（沒有任何場次），也算有資料
        let qrRequest: NSFetchRequest<CDQRCodeEntity> = CDQRCodeEntity.fetchRequest()
        qrRequest.predicate = NSPredicate(format: "userId == %@", userId)
        return (try? context.count(for: qrRequest)) ?? 0 > 0
    }

    // MARK: - 歸戶

    /// 批次改寫所有實體的 userId（訪客 → 正式帳號）
    func updateAllUserIds(from oldUID: String, to newUID: String) {
        for entityName in Self.userOwnedEntityNames {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = NSPredicate(format: "userId == %@", oldUID)
            do {
                for entity in try context.fetch(request) {
                    entity.setValue(newUID, forKey: "userId")
                    entity.setValue(SyncStatus.pending.rawValue, forKey: "syncStatus")
                }
            } catch {
                print("❌ updateAllUserIds 失敗（\(entityName)）: \(error)")
            }
        }

        do {
            try context.save()
            print("✅ updateAllUserIds: \(oldUID) → \(newUID)")
        } catch {
            print("❌ updateAllUserIds 儲存失敗: \(error)")
            context.rollback()
        }
    }

    // MARK: - 清除

    /// 清除所有本機資料（登出時呼叫）
    ///
    /// ⚠️ CDEventEntity 設有 cascade delete rule，刪除 event 會自動連帶刪除
    /// CDCategoryEntity / CDProductEntity / CDInventoryChangeEntity。
    ///
    /// ⚠️ 重建同步後，這個方法【不可以】被無條件呼叫 ——
    /// 只有「確認資料已備份到雲端」才能清除，否則未上傳的資料會永久消失。
    /// 見 SYNC_ARCHITECTURE_V2.md §9.6。
    func clearAllLocalData() {
        do {
            // 1. Event → cascade 連帶刪除 Category / Product / InventoryChange
            let eventRequest: NSFetchRequest<CDEventEntity> = CDEventEntity.fetchRequest()
            try context.fetch(eventRequest).forEach { context.delete($0) }

            // 2. Transaction（與 Event 是 Nullify，不會被 cascade）
            let txRequest: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
            try context.fetch(txRequest).forEach { context.delete($0) }

            // 3. QRCode（獨立 entity）
            let qrRequest: NSFetchRequest<CDQRCodeEntity> = CDQRCodeEntity.fetchRequest()
            try context.fetch(qrRequest).forEach { context.delete($0) }

            // 4. UserProfile 本機快取（避免同一台裝置換帳號登入時被舊快取誤導）
            let profileRequest: NSFetchRequest<CDUserProfileEntity> = CDUserProfileEntity.fetchRequest()
            try context.fetch(profileRequest).forEach { context.delete($0) }

            try context.save()
            print("✅ clearAllLocalData 完成")
        } catch {
            print("❌ clearAllLocalData 失敗: \(error)")
            context.rollback()
        }

        // TODO: [SYNC-PENDING] 原本這裡會發 .syncDidComplete 通知 UI 重讀。
        // 重建時改由 EventDataSource 統一處理（見 FEATURE_PLAN_V1.md §2.2）
        NotificationCenter.default.post(name: .localDataDidReset, object: nil)
    }
}

// MARK: - Notification

extension Notification.Name {
    /// 本機資料被整批清除（登出）後發送，通知 UI 重新讀取
    static let localDataDidReset = Notification.Name("localDataDidReset")
}
