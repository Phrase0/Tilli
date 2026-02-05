//
//  SyncManager.swift
//  Tilli
//
//  Created by Peiyun on 2026/1/30.
//  Created for CoreData + Firebase Sync
//  統一管理同步邏輯，協調上傳/下載/衝突處理
//
//  Repository → SyncManager → FirestoreUploader
//  SyncManager 負責：檢查同步條件、檢查網路、決定即時上傳或排隊
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
    private let uploader = FirestoreUploader.shared

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

    // MARK: - Should Sync Check

    /// 檢查是否應該同步
    /// 目前：member + ready
    /// 之後可改成：付費會員才同步
    var shouldSync: Bool {
        guard isUserLoggedIn else { return false }
        // TODO: 之後改成檢查付費會員
        // guard let user = authManager.currentUser else { return false }
        // return user.membership == .pro && !user.isProExpired
        return true
    }

    /// 檢查網路是否可用
    var isNetworkAvailable: Bool {
        return NetworkMonitor.shared.isConnected
    }

    // MARK: - Initialize Sync (登入成功後呼叫)

    /// 初始化同步環境（登入成功後呼叫）
    func initializeSync() async {
        guard shouldSync else { return }

        do {
            try await uploader.initializeSyncState()
            print("✅ SyncManager: syncState 初始化成功")
        } catch {
            print("❌ SyncManager: syncState 初始化失敗 - \(error)")
        }
    }

    // MARK: - Session Sync

    /// 同步 Session（新增或更新）
    func syncSession(_ session: SessionModel, operation: SyncOperationType) {
        guard shouldSync else { return }

        Task {
            if isNetworkAvailable {
                do {
                    switch operation {
                    case .create:
                        try await uploader.uploadSession(session)
                    case .update:
                        try await uploader.updateSession(session)
                    case .delete:
                        break // 刪除用另一個方法
                    }
                    updateEntitySyncStatus(entityType: SyncEntityType.session.rawValue, entityId: session.id, status: .synced)
                    print("✅ Session 同步成功: \(session.id)")
                } catch {
                    handleSyncError(error, entityType: .session, entityId: session.id, operation: operation, model: session)
                }
            } else {
                enqueueSessionOperation(session, operation: operation)
            }
        }
    }

    /// 同步刪除 Session
    func syncDeleteSession(_ sessionId: UUID, withChildren: Bool = true) {
        guard shouldSync else { return }

        Task {
            if isNetworkAvailable {
                do {
                    if withChildren {
                        try await uploader.deleteSessionWithChildren(sessionId)
                    } else {
                        try await uploader.deleteSession(sessionId)
                    }
                    print("✅ Session 刪除同步成功: \(sessionId)")
                } catch {
                    print("❌ Session 刪除同步失敗: \(error)")
                    // 刪除失敗加入佇列
                    enqueueOperation(entityType: .session, entityId: sessionId, operationType: .delete, payload: nil)
                }
            } else {
                enqueueOperation(entityType: .session, entityId: sessionId, operationType: .delete, payload: nil)
            }
        }
    }

    /// 同步完整 Session（包含 Categories 和 Products）
    func syncSessionWithChildren(_ session: SessionModel) {
        guard shouldSync else { return }

        Task {
            if isNetworkAvailable {
                do {
                    try await uploader.uploadSessionWithChildren(session)
                    updateEntitySyncStatus(entityType: SyncEntityType.session.rawValue, entityId: session.id, status: .synced)
                    print("✅ Session（含子項目）同步成功: \(session.id)")
                } catch {
                    print("❌ Session（含子項目）同步失敗: \(error)")
                    enqueueSessionOperation(session, operation: .create)
                }
            } else {
                enqueueSessionOperation(session, operation: .create)
            }
        }
    }

    // MARK: - Category Sync

    /// 同步 Category
    func syncCategory(_ category: CategoryModel, sessionId: UUID, operation: SyncOperationType) {
        guard shouldSync else { return }

        Task {
            if isNetworkAvailable {
                do {
                    switch operation {
                    case .create:
                        try await uploader.uploadCategory(category, sessionId: sessionId)
                    case .update:
                        try await uploader.updateCategory(category, sessionId: sessionId)
                    case .delete:
                        break
                    }
                    updateEntitySyncStatus(entityType: SyncEntityType.category.rawValue, entityId: category.id, status: .synced)
                    print("✅ Category 同步成功: \(category.id)")
                } catch {
                    handleSyncError(error, entityType: .category, entityId: category.id, operation: operation, model: category, sessionId: sessionId)
                }
            } else {
                enqueueCategoryOperation(category, sessionId: sessionId, operation: operation)
            }
        }
    }

    /// 同步刪除 Category
    func syncDeleteCategory(_ categoryId: UUID, withProducts: Bool = true) {
        guard shouldSync else { return }

        Task {
            if isNetworkAvailable {
                do {
                    if withProducts {
                        try await uploader.deleteCategoryWithProducts(categoryId)
                    } else {
                        try await uploader.deleteCategory(categoryId)
                    }
                    print("✅ Category 刪除同步成功: \(categoryId)")
                } catch {
                    print("❌ Category 刪除同步失敗: \(error)")
                    enqueueOperation(entityType: .category, entityId: categoryId, operationType: .delete, payload: nil)
                }
            } else {
                enqueueOperation(entityType: .category, entityId: categoryId, operationType: .delete, payload: nil)
            }
        }
    }

    // MARK: - Product Sync

    /// 同步 Product
    func syncProduct(_ product: ProductModel, operation: SyncOperationType, imageURL: String? = nil) {
        guard shouldSync else { return }

        Task {
            if isNetworkAvailable {
                do {
                    switch operation {
                    case .create:
                        try await uploader.uploadProduct(product, imageURL: imageURL)
                    case .update:
                        try await uploader.updateProduct(product, imageURL: imageURL)
                    case .delete:
                        break
                    }
                    updateEntitySyncStatus(entityType: SyncEntityType.product.rawValue, entityId: product.id, status: .synced)
                    print("✅ Product 同步成功: \(product.id)")
                } catch {
                    handleSyncError(error, entityType: .product, entityId: product.id, operation: operation, model: product)
                }
            } else {
                enqueueProductOperation(product, operation: operation)
            }
        }
    }

    /// 同步刪除 Product
    func syncDeleteProduct(_ productId: UUID) {
        guard shouldSync else { return }

        Task {
            if isNetworkAvailable {
                do {
                    try await uploader.deleteProduct(productId)
                    print("✅ Product 刪除同步成功: \(productId)")
                } catch {
                    print("❌ Product 刪除同步失敗: \(error)")
                    enqueueOperation(entityType: .product, entityId: productId, operationType: .delete, payload: nil)
                }
            } else {
                enqueueOperation(entityType: .product, entityId: productId, operationType: .delete, payload: nil)
            }
        }
    }

    // MARK: - Transaction Sync

    /// 同步 Transaction（只有新增，不可修改刪除）
    func syncTransaction(_ transaction: TransactionModel) {
        guard shouldSync else { return }

        Task {
            if isNetworkAvailable {
                do {
                    try await uploader.uploadTransaction(transaction)
                    updateEntitySyncStatus(entityType: SyncEntityType.transaction.rawValue, entityId: transaction.id, status: .synced)
                    print("✅ Transaction 同步成功: \(transaction.id)")
                } catch {
                    handleSyncError(error, entityType: .transaction, entityId: transaction.id, operation: .create, model: transaction)
                }
            } else {
                enqueueTransactionOperation(transaction)
            }
        }
    }

    // MARK: - InventoryChange Sync

    /// 同步 InventoryChange
    func syncInventoryChange(_ change: InventoryChangeModel, sessionId: UUID) {
        guard shouldSync else { return }

        Task {
            if isNetworkAvailable {
                do {
                    try await uploader.uploadInventoryChange(change, sessionId: sessionId)
                    updateEntitySyncStatus(entityType: SyncEntityType.inventoryChange.rawValue, entityId: change.id, status: .synced)
                    print("✅ InventoryChange 同步成功: \(change.id)")
                } catch {
                    handleSyncError(error, entityType: .inventoryChange, entityId: change.id, operation: .create, model: change, sessionId: sessionId)
                }
            } else {
                enqueueInventoryChangeOperation(change, sessionId: sessionId)
            }
        }
    }

    // MARK: - QRCode Sync

    /// 同步 QRCode
    func syncQRCode(_ qrCode: QRCodeModel, operation: SyncOperationType, imageURL: String? = nil) {
        guard shouldSync else { return }

        Task {
            if isNetworkAvailable {
                do {
                    switch operation {
                    case .create:
                        try await uploader.uploadQRCode(qrCode, imageURL: imageURL)
                    case .update:
                        try await uploader.updateQRCode(qrCode, imageURL: imageURL)
                    case .delete:
                        break
                    }
                    updateEntitySyncStatus(entityType: SyncEntityType.qrCode.rawValue, entityId: qrCode.id, status: .synced)
                    print("✅ QRCode 同步成功: \(qrCode.id)")
                } catch {
                    handleSyncError(error, entityType: .qrCode, entityId: qrCode.id, operation: operation, model: qrCode)
                }
            } else {
                enqueueQRCodeOperation(qrCode, operation: operation)
            }
        }
    }

    /// 同步刪除 QRCode
    func syncDeleteQRCode(_ qrCodeId: UUID) {
        guard shouldSync else { return }

        Task {
            if isNetworkAvailable {
                do {
                    try await uploader.deleteQRCode(qrCodeId)
                    print("✅ QRCode 刪除同步成功: \(qrCodeId)")
                } catch {
                    print("❌ QRCode 刪除同步失敗: \(error)")
                    enqueueOperation(entityType: .qrCode, entityId: qrCodeId, operationType: .delete, payload: nil)
                }
            } else {
                enqueueOperation(entityType: .qrCode, entityId: qrCodeId, operationType: .delete, payload: nil)
            }
        }
    }

    // MARK: - Error Handling

    private func handleSyncError<T: Encodable>(_ error: Error, entityType: SyncEntityType, entityId: UUID, operation: SyncOperationType, model: T, sessionId: UUID? = nil) {
        print("❌ \(entityType.rawValue) 同步失敗: \(error)")
        updateEntitySyncStatus(entityType: entityType.rawValue, entityId: entityId, status: .error)

        // 加入重試佇列
        if let payload = try? JSONEncoder().encode(model) {
            enqueueOperation(entityType: entityType, entityId: entityId, operationType: operation, payload: payload)
        }
    }

    // MARK: - Enqueue Helpers

    private func enqueueSessionOperation(_ session: SessionModel, operation: SyncOperationType) {
        if let payload = try? JSONEncoder().encode(session) {
            enqueueOperation(entityType: .session, entityId: session.id, operationType: operation, payload: payload)
        }
        updateEntitySyncStatus(entityType: SyncEntityType.session.rawValue, entityId: session.id, status: .pending)
    }

    private func enqueueCategoryOperation(_ category: CategoryModel, sessionId: UUID, operation: SyncOperationType) {
        if let payload = try? JSONEncoder().encode(category) {
            enqueueOperation(entityType: .category, entityId: category.id, operationType: operation, payload: payload)
        }
        updateEntitySyncStatus(entityType: SyncEntityType.category.rawValue, entityId: category.id, status: .pending)
    }

    private func enqueueProductOperation(_ product: ProductModel, operation: SyncOperationType) {
        if let payload = try? JSONEncoder().encode(product) {
            enqueueOperation(entityType: .product, entityId: product.id, operationType: operation, payload: payload)
        }
        updateEntitySyncStatus(entityType: SyncEntityType.product.rawValue, entityId: product.id, status: .pending)
    }

    private func enqueueTransactionOperation(_ transaction: TransactionModel) {
        if let payload = try? JSONEncoder().encode(transaction) {
            enqueueOperation(entityType: .transaction, entityId: transaction.id, operationType: .create, payload: payload)
        }
        updateEntitySyncStatus(entityType: SyncEntityType.transaction.rawValue, entityId: transaction.id, status: .pending)
    }

    private func enqueueInventoryChangeOperation(_ change: InventoryChangeModel, sessionId: UUID) {
        if let payload = try? JSONEncoder().encode(change) {
            enqueueOperation(entityType: .inventoryChange, entityId: change.id, operationType: .create, payload: payload)
        }
        updateEntitySyncStatus(entityType: SyncEntityType.inventoryChange.rawValue, entityId: change.id, status: .pending)
    }

    private func enqueueQRCodeOperation(_ qrCode: QRCodeModel, operation: SyncOperationType) {
        if let payload = try? JSONEncoder().encode(qrCode) {
            enqueueOperation(entityType: .qrCode, entityId: qrCode.id, operationType: operation, payload: payload)
        }
        updateEntitySyncStatus(entityType: SyncEntityType.qrCode.rawValue, entityId: qrCode.id, status: .pending)
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
