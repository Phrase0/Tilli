//
//  SyncManager.swift
//  Tilli
//
//  Created by Peiyun on 2026/1/30.
//  Created for CoreData + Firebase Sync
//  統一管理同步邏輯，協調上傳/下載/衝突處理
//

import Foundation
import CoreData
import FirebaseAuth
import FirebaseFirestore

@MainActor
class SyncManager: ObservableObject {
    static let shared = SyncManager()

    // MARK: - Dependencies
    private let context: NSManagedObjectContext
    private let db = Firestore.firestore()

    // MARK: - Published Properties
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: SyncError?

    // MARK: - Init
    private init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }

    // MARK: - Current User ID
    var currentUserId: String? {
        return Auth.auth().currentUser?.uid
    }

    var isUserLoggedIn: Bool {
        return currentUserId != nil
    }

    // MARK: - Pending Queue Operations

    /// 處理所有待同步的操作（網路恢復時呼叫）
    func processPendingQueue() async {
        guard isUserLoggedIn else { return }
        guard NetworkMonitor.shared.isConnected else { return }

        let request: NSFetchRequest<CDPendingSyncOperation> = CDPendingSyncOperation.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        do {
            let pendingOps = try context.fetch(request)

            for op in pendingOps {
                do {
                    try await processOperation(op)

                    // 成功：刪除這筆 pending operation
                    context.delete(op)

                    // 更新原實體的 syncStatus
                    updateEntitySyncStatus(
                        entityType: op.entityType,
                        entityId: op.entityId,
                        status: .synced
                    )
                } catch {
                    // 失敗：增加 retryCount，記錄 error
                    op.retryCount += 1
                    op.lastError = error.localizedDescription

                    if op.retryCount >= 3 {
                        // 超過重試次數，標記原實體為 error 狀態
                        updateEntitySyncStatus(
                            entityType: op.entityType,
                            entityId: op.entityId,
                            status: .error
                        )
                    }
                }
            }

            try context.save()
        } catch {
            print("處理待同步佇列失敗: \(error)")
        }
    }

    /// 處理單一操作
    private func processOperation(_ op: CDPendingSyncOperation) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        switch op.operationType {
        case "create":
            try await uploadEntity(op, userId: userId)
        case "update":
            try await updateEntity(op, userId: userId)
        case "delete":
            try await deleteEntity(op)
        default:
            break
        }
    }

    /// 上傳新實體到 Firestore
    private func uploadEntity(_ op: CDPendingSyncOperation, userId: String) async throws {
        guard let payload = op.payload,
              let data = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else {
            throw SyncError.dataCorrupted
        }

        let collectionName = getCollectionName(for: op.entityType)
        try await db.collection(collectionName)
            .document(op.entityId.uuidString)
            .setData(data)
    }

    /// 更新 Firestore 中的實體
    private func updateEntity(_ op: CDPendingSyncOperation, userId: String) async throws {
        guard let payload = op.payload,
              let data = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else {
            throw SyncError.dataCorrupted
        }

        let collectionName = getCollectionName(for: op.entityType)
        try await db.collection(collectionName)
            .document(op.entityId.uuidString)
            .updateData(data)
    }

    /// 從 Firestore 刪除實體
    private func deleteEntity(_ op: CDPendingSyncOperation) async throws {
        let collectionName = getCollectionName(for: op.entityType)
        try await db.collection(collectionName)
            .document(op.entityId.uuidString)
            .delete()
    }

    // MARK: - Enqueue Operations

    /// 將操作加入待同步佇列
    func enqueueOperation(
        entityType: SyncEntityType,
        entityId: UUID,
        operationType: SyncOperationType,
        payload: Data? = nil
    ) {
        let pending = CDPendingSyncOperation(context: context)
        pending.id = UUID()
        pending.entityType = entityType.rawValue
        pending.entityId = entityId
        pending.operationType = operationType.rawValue
        pending.payload = payload
        pending.createdAt = Date()
        pending.retryCount = 0
        pending.lastError = nil

        do {
            try context.save()
        } catch {
            print("加入待同步佇列失敗: \(error)")
        }
    }

    // MARK: - Helper Methods

    /// 根據 entityType 取得 Firestore collection 名稱
    private func getCollectionName(for entityType: String) -> String {
        switch entityType {
        case "session": return "sessions"
        case "category": return "categories"
        case "product": return "products"
        case "transaction": return "transactions"
        case "inventoryChange": return "inventoryChanges"
        case "qrCode": return "qrCodes"
        default: return entityType
        }
    }

    /// 更新實體的 syncStatus
    private func updateEntitySyncStatus(entityType: String, entityId: UUID, status: SyncStatus) {
        let entityName = getEntityName(for: entityType)

        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", entityId as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                entity.setValue(status.rawValue, forKey: "syncStatus")
                try context.save()
            }
        } catch {
            print("更新 syncStatus 失敗: \(error)")
        }
    }

    /// 根據 entityType 取得 CoreData entity 名稱
    private func getEntityName(for entityType: String) -> String {
        switch entityType {
        case "session": return "CDSessionEntity"
        case "category": return "CDCategoryEntity"
        case "product": return "CDProductEntity"
        case "transaction": return "CDTransactionEntity"
        case "inventoryChange": return "CDInventoryChangeEntity"
        case "qrCode": return "CDQRCodeEntity"
        default: return entityType
        }
    }

    // MARK: - Sync with Retry

    /// 帶重試機制的同步操作
    func syncWithRetry(operation: () async throws -> Void, maxRetries: Int = 3) async throws {
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                try await operation()
                return // 成功
            } catch {
                lastError = error

                // 指數退避
                let delay = pow(2.0, Double(attempt)) // 2, 4, 8 秒
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? SyncError.unknown(NSError())
    }
}

// MARK: - SyncError

enum SyncError: Error {
    case networkUnavailable          // 無網路
    case authenticationRequired      // 需要登入
    case permissionDenied            // 權限不足
    case quotaExceeded               // 配額超限
    case documentNotFound            // 文件不存在
    case dataCorrupted               // 資料損壞
    case imageUploadFailed           // 圖片上傳失敗
    case unknown(Error)              // 其他錯誤

    var localizedDescription: String {
        switch self {
        case .networkUnavailable:
            return "無網路連線"
        case .authenticationRequired:
            return "需要登入"
        case .permissionDenied:
            return "權限不足"
        case .quotaExceeded:
            return "配額超限"
        case .documentNotFound:
            return "資料不存在"
        case .dataCorrupted:
            return "資料損壞"
        case .imageUploadFailed:
            return "圖片上傳失敗"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
