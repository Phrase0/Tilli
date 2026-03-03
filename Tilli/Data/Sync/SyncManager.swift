//
//  SyncManager.swift
//  Tilli
//
//  Created by Peiyun on 2026/1/30.
//  Created for CoreData + Firebase Sync
//  統一管理同步邏輯，協調上傳/下載/衝突處理
//
//  Repository → SyncManager → FirestoreUploader / FirestoreDownloader
//  SyncManager 負責：檢查同步條件、檢查網路、決定即時上傳或排隊、協調下載同步
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
    private let downloader = FirestoreDownloader.shared

    // MARK: - Published Properties
    @Published var isSyncing = false
    @Published var isDownloading = false
    @Published var downloadProgress: FirestoreDownloader.SyncProgress?
    @Published var lastSyncDate: Date?
    @Published var syncError: SyncError?

    // MARK: - Membership State
    private var currentMembership: UserProfile.Membership = .free

    // MARK: - Private State
    private var isProcessingQueue = false

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

    // MARK: - Membership Control

    /// 設定會員等級（由 AuthenticationManager 呼叫）
    func setMembership(_ membership: UserProfile.Membership) {
        currentMembership = membership
        print("✅ SyncManager: 會員等級設定為 \(membership.rawValue)")
    }

    /// 是否應該啟用 Listener（僅 Pro 會員）
    var shouldListen: Bool {
        return isUserLoggedIn && currentMembership == .pro
    }

    /// 檢查網路是否可用
    var isNetworkAvailable: Bool {
        return NetworkMonitor.shared.isConnected
    }

    // MARK: - Hybrid Listener
    private let hybridListener = HybridSyncListener.shared

    // MARK: - Initialize Sync (登入成功後呼叫)

    /// 初始化同步環境（登入成功後呼叫）
    func initializeSync() async {
        guard isUserLoggedIn else { return }

        do {
            try await uploader.initializeSyncState()
            print("✅ SyncManager: syncState 初始化成功")
        } catch {
            print("❌ SyncManager: syncState 初始化失敗 - \(error)")
        }

        // 僅 Pro 會員啟動 Listener
        if shouldListen {
            startListening()
        }

        // 啟動網路監控（網路恢復時自動處理離線佇列）
        startNetworkMonitoring()
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        NetworkMonitor.shared.startMonitoring { isConnected in
            if isConnected {
                Task { @MainActor in
                    await SyncManager.shared.processPendingQueue()
                }
            }
        }
    }

    // MARK: - Listener Management

    /// 開始監聽 syncState（僅 Pro 會員，登入後呼叫）
    func startListening() {
        guard let userId = currentUserId else { return }
        guard shouldListen else { return }

        hybridListener.startListening(userId: userId)
    }

    /// 停止監聽（登出時呼叫）
    func stopListening() {
        hybridListener.stopListening()
    }

    /// 重置同步狀態（登出時呼叫）
    func resetSync() {
        stopListening()
        hybridListener.resetLocalVersion()
    }

    // MARK: - Session Sync

    /// 同步 Session（新增或更新）
    func syncSession(_ session: SessionModel, operation: SyncOperationType) {
        guard isUserLoggedIn else { return }

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
        guard isUserLoggedIn else { return }

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
        guard isUserLoggedIn else { return }

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
        guard isUserLoggedIn else { return }

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
        guard isUserLoggedIn else { return }

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
    func syncProduct(_ product: ProductModel, operation: SyncOperationType, imageChanged: Bool = false) {
        guard isUserLoggedIn else { return }

        Task {
            if isNetworkAvailable {
                do {
                    // 若圖片有變更，先上傳到 Storage 取得新 URL
                    var imageURL: String? = product.imageURL
                    if imageChanged, let image = product.image {
                        imageURL = try await ImageSyncService.shared.uploadProductImage(image, productId: product.id)
                        updateProductImageURL(productId: product.id, imageURL: imageURL)
                    }

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

    /// 更新 CoreData 中 Product 的 imageURL
    private func updateProductImageURL(productId: UUID, imageURL: String?) {
        let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productId as CVarArg)
        do {
            if let entity = try context.fetch(request).first {
                entity.imageURL = imageURL
                try context.save()
            }
        } catch {
            print("❌ updateProductImageURL 失敗: \(error)")
        }
    }

    /// 同步刪除 Product
    func syncDeleteProduct(_ productId: UUID) {
        guard isUserLoggedIn else { return }

        Task {
            if isNetworkAvailable {
                do {
                    try await uploader.deleteProduct(productId)
                    try? await ImageSyncService.shared.deleteProductImage(productId: productId)
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

    /// 同步刪除 Product 及其所有 InventoryChanges（Cascade Delete）
    func syncDeleteProductWithInventoryChanges(_ productId: UUID, inventoryChangeIds: [UUID] = []) {
        guard isUserLoggedIn else { return }

        Task {
            if isNetworkAvailable {
                do {
                    try await uploader.deleteProductWithInventoryChanges(productId)
                    try? await ImageSyncService.shared.deleteProductImage(productId: productId)
                    print("✅ Product（含庫存異動）刪除同步成功: \(productId)")
                } catch {
                    print("❌ Product（含庫存異動）刪除同步失敗: \(error)")
                    // 分別加入佇列
                    enqueueOperation(entityType: .product, entityId: productId, operationType: .delete, payload: nil)
                    for changeId in inventoryChangeIds {
                        enqueueOperation(entityType: .inventoryChange, entityId: changeId, operationType: .delete, payload: nil)
                    }
                }
            } else {
                // 離線：分別 enqueue
                enqueueOperation(entityType: .product, entityId: productId, operationType: .delete, payload: nil)
                for changeId in inventoryChangeIds {
                    enqueueOperation(entityType: .inventoryChange, entityId: changeId, operationType: .delete, payload: nil)
                }
            }
        }
    }

    // MARK: - Transaction Sync

    /// 同步 Transaction（只有新增，不可修改刪除）
    func syncTransaction(_ transaction: TransactionModel) {
        guard isUserLoggedIn else { return }

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
        guard isUserLoggedIn else { return }

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

    /// 同步 QRCode（統一用 setData upsert，不區分 create/update）
    func syncQRCode(_ qrCode: QRCodeModel, imageURL: String? = nil) {
        guard isUserLoggedIn else { return }

        Task {
            if isNetworkAvailable {
                do {
                    try await uploader.uploadQRCode(qrCode, imageURL: imageURL)
                    updateEntitySyncStatus(entityType: SyncEntityType.qrCode.rawValue, entityId: qrCode.id, status: .synced)
                    print("✅ QRCode 同步成功: \(qrCode.id)")
                } catch {
                    handleSyncError(error, entityType: .qrCode, entityId: qrCode.id, operation: .create, model: qrCode)
                }
            } else {
                enqueueQRCodeOperation(qrCode, operation: .create)
            }
        }
    }

    /// 同步刪除 QRCode（同時刪除 Storage 固定路徑圖片）
    func syncDeleteQRCode(_ qrCodeId: UUID) {
        guard isUserLoggedIn else { return }

        Task {
            if isNetworkAvailable {
                do {
                    try await uploader.deleteQRCode(qrCodeId)
                    try? await ImageSyncService.shared.deleteQRCodeImage()
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

        // 加入重試佇列（確保 sessionId 被寫入 payload）
        var payload: Data?
        if var category = model as? CategoryModel, let sid = sessionId {
            category.sessionId = sid
            payload = try? JSONEncoder().encode(category)
        } else if var change = model as? InventoryChangeModel, let sid = sessionId {
            change.sessionId = sid
            payload = try? JSONEncoder().encode(change)
        } else {
            payload = try? JSONEncoder().encode(model)
        }

        if let payload = payload {
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
        var categoryToEnqueue = category
        categoryToEnqueue.sessionId = sessionId
        if let payload = try? JSONEncoder().encode(categoryToEnqueue) {
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
        var changeToEnqueue = change
        changeToEnqueue.sessionId = sessionId
        if let payload = try? JSONEncoder().encode(changeToEnqueue) {
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
        guard !isProcessingQueue else { return }
        guard isUserLoggedIn else { return }
        guard NetworkMonitor.shared.isConnected else { return }

        isProcessingQueue = true
        defer { isProcessingQueue = false }

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
    /// 使用 FirestoreUploader 的正確方法，確保：
    /// 1. Date 被序列化為 Firestore Timestamp（而非 JSON string）
    /// 2. syncState 會被同步更新
    private func processOperation(_ op: CDPendingSyncOperation) async throws {
        switch op.operationType {
        case "create":
            try await uploadEntity(op)
        case "update":
            try await updateEntity(op)
        case "delete":
            try await deleteEntity(op)
        default:
            break
        }
    }

    /// 上傳新實體到 Firestore（透過 uploader 的正確方法）
    private func uploadEntity(_ op: CDPendingSyncOperation) async throws {
        guard let payload = op.payload else {
            throw SyncError.dataCorrupted
        }

        let decoder = JSONDecoder()

        switch op.entityType {
        case SyncEntityType.session.rawValue:
            let model = try decoder.decode(SessionModel.self, from: payload)
            try await uploader.uploadSession(model)

        case SyncEntityType.category.rawValue:
            let model = try decoder.decode(CategoryModel.self, from: payload)
            guard let sessionId = model.sessionId else { throw SyncError.dataCorrupted }
            try await uploader.uploadCategory(model, sessionId: sessionId)

        case SyncEntityType.product.rawValue:
            let model = try decoder.decode(ProductModel.self, from: payload)
            var imageURL: String? = model.imageURL
            if let image = model.image {
                imageURL = try await ImageSyncService.shared.uploadProductImage(image, productId: model.id)
                updateProductImageURL(productId: model.id, imageURL: imageURL)
            }
            try await uploader.uploadProduct(model, imageURL: imageURL)

        case SyncEntityType.transaction.rawValue:
            let model = try decoder.decode(TransactionModel.self, from: payload)
            try await uploader.uploadTransaction(model)

        case SyncEntityType.inventoryChange.rawValue:
            let model = try decoder.decode(InventoryChangeModel.self, from: payload)
            guard let sessionId = model.sessionId else { throw SyncError.dataCorrupted }
            try await uploader.uploadInventoryChange(model, sessionId: sessionId)

        case SyncEntityType.qrCode.rawValue:
            let model = try decoder.decode(QRCodeModel.self, from: payload)
            try await uploader.uploadQRCode(model)

        default:
            break
        }
    }

    /// 更新 Firestore 中的實體（透過 uploader 的正確方法）
    private func updateEntity(_ op: CDPendingSyncOperation) async throws {
        guard let payload = op.payload else {
            throw SyncError.dataCorrupted
        }

        let decoder = JSONDecoder()

        switch op.entityType {
        case SyncEntityType.session.rawValue:
            let model = try decoder.decode(SessionModel.self, from: payload)
            try await uploader.updateSession(model)

        case SyncEntityType.category.rawValue:
            let model = try decoder.decode(CategoryModel.self, from: payload)
            guard let sessionId = model.sessionId else { throw SyncError.dataCorrupted }
            try await uploader.updateCategory(model, sessionId: sessionId)

        case SyncEntityType.product.rawValue:
            let model = try decoder.decode(ProductModel.self, from: payload)
            var imageURL: String? = model.imageURL
            if let image = model.image {
                imageURL = try await ImageSyncService.shared.uploadProductImage(image, productId: model.id)
                updateProductImageURL(productId: model.id, imageURL: imageURL)
            }
            try await uploader.updateProduct(model, imageURL: imageURL)

        case SyncEntityType.qrCode.rawValue:
            let model = try decoder.decode(QRCodeModel.self, from: payload)
            try await uploader.uploadQRCode(model)

        default:
            break
        }
    }

    /// 從 Firestore 刪除實體（透過 uploader 的正確方法）
    /// Session / Category / Product 使用 WithChildren 版本，確保 cascade delete
    private func deleteEntity(_ op: CDPendingSyncOperation) async throws {
        let entityId = op.entityId

        switch op.entityType {
        case SyncEntityType.session.rawValue:
            try await uploader.deleteSessionWithChildren(entityId)

        case SyncEntityType.category.rawValue:
            try await uploader.deleteCategoryWithProducts(entityId)

        case SyncEntityType.product.rawValue:
            try await uploader.deleteProductWithInventoryChanges(entityId)
            try? await ImageSyncService.shared.deleteProductImage(productId: entityId)

        case SyncEntityType.inventoryChange.rawValue:
            try await uploader.deleteInventoryChange(entityId)

        case SyncEntityType.qrCode.rawValue:
            try await uploader.deleteQRCode(entityId)

        default:
            break
        }
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

    // MARK: - Utility Methods

    /// 檢查本地是否有當前用戶的資料（用於登入情境判斷）
    func hasLocalData() -> Bool {
        guard let userId = currentUserId else { return false }
        return hasLocalData(for: userId)
    }

    /// 檢查本地是否有指定用戶的資料（用於登入前捕捉匿名 UID 的情境）
    func hasLocalData(for userId: String) -> Bool {
        let sessionRequest: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        sessionRequest.predicate = NSPredicate(format: "userId == %@", userId)
        if (try? context.count(for: sessionRequest)) ?? 0 > 0 { return true }

        // Guest 可能只有 QRCode（無 sessions），也需觸發升級流程
        let qrRequest: NSFetchRequest<CDQRCodeEntity> = CDQRCodeEntity.fetchRequest()
        qrRequest.predicate = NSPredicate(format: "userId == %@", userId)
        return (try? context.count(for: qrRequest)) ?? 0 > 0
    }

    /// 檢查 Firestore 是否有該用戶的資料（用於登入情境判斷）
    func hasCloudData(userId: String) async -> Bool {
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("sessions")
                .limit(to: 1)
                .getDocuments()
            return !snapshot.documents.isEmpty
        } catch {
            print("❌ hasCloudData 查詢失敗: \(error)")
            return false
        }
    }

    /// 批次更新所有實體的 userId（匿名 → 正式帳號升級時使用）
    func updateAllUserIds(from oldUID: String, to newUID: String) {
        let entityNames = [
            "CDSessionEntity",
            "CDCategoryEntity",
            "CDProductEntity",
            "CDTransactionEntity",
            "CDInventoryChangeEntity",
            "CDQRCodeEntity"
        ]

        for entityName in entityNames {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = NSPredicate(format: "userId == %@", oldUID)

            do {
                let entities = try context.fetch(request)
                for entity in entities {
                    entity.setValue(newUID, forKey: "userId")
                    entity.setValue("pending", forKey: "syncStatus")
                }
            } catch {
                print("❌ updateAllUserIds failed for \(entityName): \(error)")
            }
        }

        do {
            try context.save()
            print("✅ updateAllUserIds: \(oldUID) → \(newUID)")
        } catch {
            print("❌ updateAllUserIds save failed: \(error)")
            context.rollback()
        }
    }

    /// 全量上傳所有本地資料到 Firestore（情境 C：匿名資料升級後上傳）
    func fullUploadAllData() async {
        guard let userId = currentUserId else { return }
        guard isNetworkAvailable else {
            print("❌ fullUploadAllData: 無網路")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            // 1. 上傳 Sessions（含 Categories + Products）
            let sessionRequest: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
            sessionRequest.predicate = NSPredicate(format: "userId == %@", userId)
            let sessions = try context.fetch(sessionRequest)

            for session in sessions {
                do {
                    try await uploader.uploadSessionWithChildren(session.toModel())
                } catch {
                    print("❌ fullUpload Session 失敗: \(session.id) - \(error)")
                }
            }

            // 2. 上傳 Transactions
            let txRequest: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
            txRequest.predicate = NSPredicate(format: "userId == %@", userId)
            let transactions = try context.fetch(txRequest)

            for tx in transactions {
                do {
                    try await uploader.uploadTransaction(tx.toModel())
                } catch {
                    print("❌ fullUpload Transaction 失敗: \(tx.id) - \(error)")
                }
            }

            // 3. 上傳 InventoryChanges
            let changeRequest: NSFetchRequest<CDInventoryChangeEntity> = CDInventoryChangeEntity.fetchRequest()
            changeRequest.predicate = NSPredicate(format: "userId == %@", userId)
            let changes = try context.fetch(changeRequest)

            for change in changes {
                do {
                    let model = change.toModel()
                    if let sessionId = model.sessionId {
                        try await uploader.uploadInventoryChange(model, sessionId: sessionId)
                    }
                } catch {
                    print("❌ fullUpload InventoryChange 失敗: \(change.id) - \(error)")
                }
            }

            // 4. 上傳 QRCode（每人唯一，LWW：與遠端比較 updatedAt）
            let qrRequest: NSFetchRequest<CDQRCodeEntity> = CDQRCodeEntity.fetchRequest()
            qrRequest.predicate = NSPredicate(format: "userId == %@", userId)
            let qrCodes = try context.fetch(qrRequest)

            if let localQR = qrCodes.first {
                let localUpdatedAt = localQR.updatedAt ?? Date.distantPast

                // 查遠端是否已有 QRCode
                let remoteSnapshot = try? await db.collection("users").document(userId)
                    .collection("qrCodes")
                    .limit(to: 1)
                    .getDocuments()
                let remoteUpdatedAt = remoteSnapshot?.documents.first
                    .flatMap { ($0.data()["updatedAt"] as? Timestamp)?.dateValue() }

                if let remoteTime = remoteUpdatedAt, remoteTime > localUpdatedAt {
                    // 遠端較新 → 跳過，performFullSync 會下載遠端版本
                    print("⏭️ fullUpload QRCode 跳過（遠端較新）")
                } else {
                    // 本地較新或遠端不存在 → 上傳本地（含圖片）
                    var model = localQR.toModel()
                    if model.imageURL == nil, let image = model.image {
                        let url = try await ImageSyncService.shared.uploadQRCodeImage(image)
                        model.imageURL = url
                        localQR.imageURL = url
                    }
                    try await uploader.uploadQRCode(model)
                    print("✅ fullUpload QRCode 成功: \(model.id)")
                }
            }

            // 5. 批次更新 syncStatus = "synced"
            let allEntities: [NSManagedObject] = sessions + transactions + changes + qrCodes
            for entity in allEntities {
                entity.setValue("synced", forKey: "syncStatus")
            }
            // Sessions 內的 Categories 和 Products 也要更新
            for session in sessions {
                if let categories = session.categories as? Set<CDCategoryEntity> {
                    for category in categories {
                        category.syncStatus = "synced"
                        if let products = category.products as? Set<CDProductEntity> {
                            for product in products {
                                product.syncStatus = "synced"
                            }
                        }
                    }
                }
            }

            try context.save()
            print("✅ fullUploadAllData 完成")
        } catch {
            print("❌ fullUploadAllData 失敗: \(error)")
            context.rollback()
        }
    }

    /// 清除所有本地資料（登出時呼叫）
    /// CDSessionEntity 設有 cascade delete rule，刪除 session 會自動連動刪除
    /// CDCategoryEntity、CDProductEntity、CDInventoryChangeEntity
    func clearAllLocalData() {
        do {
            // 1. 刪除 CDPendingSyncOperation（無 cascade parent，需明確刪除）
            let pendingRequest: NSFetchRequest<CDPendingSyncOperation> = CDPendingSyncOperation.fetchRequest()
            let pendingOps = try context.fetch(pendingRequest)
            pendingOps.forEach { context.delete($0) }

            // 2. 刪除 CDSessionEntity → cascade 自動刪 Category / Product / InventoryChange
            let sessionRequest: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
            let sessions = try context.fetch(sessionRequest)
            sessions.forEach { context.delete($0) }

            // 3. 刪除 CDTransactionEntity（與 Session 無 cascade 關係）
            let txRequest: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
            let transactions = try context.fetch(txRequest)
            transactions.forEach { context.delete($0) }

            // 4. 刪除 CDQRCodeEntity（獨立 entity）
            let qrRequest: NSFetchRequest<CDQRCodeEntity> = CDQRCodeEntity.fetchRequest()
            let qrCodes = try context.fetch(qrRequest)
            qrCodes.forEach { context.delete($0) }

            try context.save()
        } catch {
            print("❌ clearAllLocalData 失敗: \(error)")
            context.rollback()
        }

        // 通知 UI 刷新
        NotificationCenter.default.post(name: .syncDidComplete, object: nil)

        print("✅ clearAllLocalData 完成")
    }

    // MARK: - Download Sync

    /// 全量下載（從 Firestore 下載所有資料到本地）
    func performFullSync() async {
        guard isUserLoggedIn else { return }
        guard isNetworkAvailable else {
            syncError = .networkUnavailable
            return
        }
        guard !isDownloading else { return }

        isDownloading = true
        isSyncing = true
        syncError = nil

        // 設定進度回報
        downloader.onProgressUpdate = { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress
            }
        }

        do {
            try await downloader.fullSync()
            lastSyncDate = Date()
            print("✅ SyncManager: 全量下載完成")

            // 通知 UI 刷新（Repository 層重新從 CoreData 讀取）
            NotificationCenter.default.post(name: .syncDidComplete, object: nil)
        } catch {
            print("❌ SyncManager: 全量下載失敗 - \(error)")
            syncError = .unknown(error)
        }

        isDownloading = false
        isSyncing = false
        downloadProgress = nil
    }

    /// 下載特定 Session 及其子項目
    func performSessionDownload(sessionId: UUID) async {
        guard isUserLoggedIn else { return }
        guard isNetworkAvailable else {
            syncError = .networkUnavailable
            return
        }

        isDownloading = true

        do {
            try await downloader.downloadSessionWithChildren(id: sessionId)
            print("✅ SyncManager: Session 下載完成 - \(sessionId)")
        } catch {
            print("❌ SyncManager: Session 下載失敗 - \(error)")
            syncError = .unknown(error)
        }

        isDownloading = false
    }

    /// 增量下載（Phase 5 Hybrid Listener 用）
    func performIncrementalSync(
        sessionIds: [UUID] = [],
        categoryIds: [UUID] = [],
        productIds: [UUID] = [],
        transactionIds: [UUID] = [],
        inventoryChangeIds: [UUID] = [],
        qrCodeIds: [UUID] = []
    ) async {
        guard isUserLoggedIn else { return }
        guard isNetworkAvailable else { return }

        do {
            try await downloader.downloadEntities(
                sessionIds: sessionIds,
                categoryIds: categoryIds,
                productIds: productIds,
                transactionIds: transactionIds,
                inventoryChangeIds: inventoryChangeIds,
                qrCodeIds: qrCodeIds
            )
            print("✅ SyncManager: 增量下載完成")

            // 通知 UI 刷新
            NotificationCenter.default.post(name: .syncDidComplete, object: nil)
        } catch {
            print("❌ SyncManager: 增量下載失敗 - \(error)")
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

// MARK: - Notification Names

extension Notification.Name {
    /// Full sync 完成後發送，通知 Repository 層重新讀取 CoreData
    static let syncDidComplete = Notification.Name("syncDidComplete")
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
