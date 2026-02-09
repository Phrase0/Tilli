//
//  FirestoreDownloader.swift
//  Tilli
//
//  Created by Peiyun on 2026/2/6.
//  Created for CoreData + Firebase Sync
//  處理從 Firestore 下載資料到本地 CoreData，支援 LWW 衝突策略
//  對稱 FirestoreUploader：上傳 → 下載
//

import Foundation
import CoreData
import FirebaseFirestore
import FirebaseAuth

/// Firestore 下載服務
/// 負責從 Firestore 下載資料並寫入本地 CoreData
/// 衝突策略：LWW（Session/Category/Product/QRCode）、Skip-if-exists（Transaction/InventoryChange）
class FirestoreDownloader {
    static let shared = FirestoreDownloader()

    private let db = Firestore.firestore()
    private let context: NSManagedObjectContext

    private init() {
        self.context = PersistenceController.shared.container.viewContext
    }

    // MARK: - Current User ID

    private var currentUserId: String? {
        return Auth.auth().currentUser?.uid
    }

    // MARK: - Collection Names

    private enum Collection {
        static let sessions = "sessions"
        static let categories = "categories"
        static let products = "products"
        static let transactions = "transactions"
        static let inventoryChanges = "inventoryChanges"
        static let qrCodes = "qrCodes"
    }

    // MARK: - Sync Progress

    struct SyncProgress {
        var currentStep: String
        var currentEntity: String
        var overallProgress: Double // 0.0 ~ 1.0
    }

    var onProgressUpdate: ((SyncProgress) -> Void)?

    private func reportProgress(step: String, entity: String, progress: Double) {
        let syncProgress = SyncProgress(currentStep: step, currentEntity: entity, overallProgress: progress)
        onProgressUpdate?(syncProgress)
    }

    // MARK: - Single Entity Download

    /// 下載 Session
    func downloadSession(id: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let doc = try await db.collection(Collection.sessions).document(id.uuidString).getDocument()
        guard let data = doc.data(),
              data["userId"] as? String == userId,
              let model = SessionModel(from: data),
              let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        else { return }

        await MainActor.run {
            saveSession(model, remoteUpdatedAt: remoteUpdatedAt, userId: userId)
        }
    }

    /// 下載 Category
    func downloadCategory(id: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let doc = try await db.collection(Collection.categories).document(id.uuidString).getDocument()
        guard let data = doc.data(),
              data["userId"] as? String == userId,
              let model = CategoryModel(from: data),
              let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        else { return }

        await MainActor.run {
            saveCategory(model, remoteUpdatedAt: remoteUpdatedAt, userId: userId)
        }
    }

    /// 下載 Product
    func downloadProduct(id: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let doc = try await db.collection(Collection.products).document(id.uuidString).getDocument()
        guard let data = doc.data(),
              data["userId"] as? String == userId,
              let model = ProductModel(from: data),
              let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        else { return }

        await MainActor.run {
            saveProduct(model, remoteUpdatedAt: remoteUpdatedAt, userId: userId)
        }
    }

    /// 下載 Transaction
    func downloadTransaction(id: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let doc = try await db.collection(Collection.transactions).document(id.uuidString).getDocument()
        guard let data = doc.data(),
              data["userId"] as? String == userId,
              let model = TransactionModel(from: data)
        else { return }

        await MainActor.run {
            createTransaction(model, userId: userId)
        }
    }

    /// 下載 InventoryChange
    func downloadInventoryChange(id: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let doc = try await db.collection(Collection.inventoryChanges).document(id.uuidString).getDocument()
        guard let data = doc.data(),
              data["userId"] as? String == userId,
              let model = InventoryChangeModel(from: data)
        else { return }

        await MainActor.run {
            createInventoryChange(model, userId: userId)
        }
    }

    /// 下載 QRCode
    func downloadQRCode(id: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let doc = try await db.collection(Collection.qrCodes).document(id.uuidString).getDocument()
        guard let data = doc.data(),
              data["userId"] as? String == userId,
              let model = QRCodeModel(from: data),
              let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        else { return }

        await MainActor.run {
            saveQRCode(model, remoteUpdatedAt: remoteUpdatedAt, userId: userId)
        }
    }

    // MARK: - Batch Download

    /// 下載所有 Sessions
    func downloadAllSessions() async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        reportProgress(step: "正在下載場次...", entity: "sessions", progress: 0.0)

        let snapshot = try await db.collection(Collection.sessions)
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        await MainActor.run {
            for doc in snapshot.documents {
                let data = doc.data()
                guard let model = SessionModel(from: data),
                      let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
                else { continue }

                saveSession(model, remoteUpdatedAt: remoteUpdatedAt, userId: userId)
            }
        }

        print("✅ 下載 Sessions 完成: \(snapshot.documents.count) 筆")
    }

    /// 下載所有 Categories
    func downloadAllCategories() async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        reportProgress(step: "正在下載分類...", entity: "categories", progress: 1.0 / 7.0)

        let snapshot = try await db.collection(Collection.categories)
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        await MainActor.run {
            for doc in snapshot.documents {
                let data = doc.data()
                guard let model = CategoryModel(from: data),
                      let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
                else { continue }

                saveCategory(model, remoteUpdatedAt: remoteUpdatedAt, userId: userId)
            }
        }

        print("✅ 下載 Categories 完成: \(snapshot.documents.count) 筆")
    }

    /// 下載所有 Products
    func downloadAllProducts() async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        reportProgress(step: "正在下載產品...", entity: "products", progress: 2.0 / 7.0)

        let snapshot = try await db.collection(Collection.products)
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        await MainActor.run {
            for doc in snapshot.documents {
                let data = doc.data()
                guard let model = ProductModel(from: data),
                      let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
                else { continue }

                saveProduct(model, remoteUpdatedAt: remoteUpdatedAt, userId: userId)
            }
        }

        print("✅ 下載 Products 完成: \(snapshot.documents.count) 筆")
    }

    /// 下載所有 Transactions
    func downloadAllTransactions() async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        reportProgress(step: "正在下載交易記錄...", entity: "transactions", progress: 3.0 / 7.0)

        // 批次查詢已存在的 ID，避免 N+1
        let existingIds = await MainActor.run { fetchExistingTransactionIds() }

        let snapshot = try await db.collection(Collection.transactions)
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        await MainActor.run {
            for doc in snapshot.documents {
                let data = doc.data()
                guard let model = TransactionModel(from: data) else { continue }

                // Skip-if-exists：已存在就跳過
                if existingIds.contains(model.id) { continue }

                createTransaction(model, userId: userId)
            }
        }

        print("✅ 下載 Transactions 完成: \(snapshot.documents.count) 筆")
    }

    /// 下載所有 InventoryChanges
    func downloadAllInventoryChanges() async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        reportProgress(step: "正在下載庫存變動...", entity: "inventoryChanges", progress: 4.0 / 7.0)

        // 批次查詢已存在的 ID，避免 N+1
        let existingIds = await MainActor.run { fetchExistingInventoryChangeIds() }

        let snapshot = try await db.collection(Collection.inventoryChanges)
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        await MainActor.run {
            for doc in snapshot.documents {
                let data = doc.data()
                guard let model = InventoryChangeModel(from: data) else { continue }

                // Skip-if-exists：已存在就跳過
                if existingIds.contains(model.id) { continue }

                createInventoryChange(model, userId: userId)
            }
        }

        print("✅ 下載 InventoryChanges 完成: \(snapshot.documents.count) 筆")
    }

    /// 下載所有 QRCodes
    func downloadAllQRCodes() async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        reportProgress(step: "正在下載 QR Code...", entity: "qrCodes", progress: 5.0 / 7.0)

        let snapshot = try await db.collection(Collection.qrCodes)
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        await MainActor.run {
            for doc in snapshot.documents {
                let data = doc.data()
                guard let model = QRCodeModel(from: data),
                      let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
                else { continue }

                saveQRCode(model, remoteUpdatedAt: remoteUpdatedAt, userId: userId)
            }
        }

        print("✅ 下載 QRCodes 完成: \(snapshot.documents.count) 筆")
    }

    // MARK: - Download With Children

    /// 下載 Session 及其子項目（Categories + Products + InventoryChanges）
    func downloadSessionWithChildren(id: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let sessionIdString = id.uuidString

        // 1. 下載 Session
        try await downloadSession(id: id)

        // 2. 下載 Categories（by sessionId）
        let categoriesSnapshot = try await db.collection(Collection.categories)
            .whereField("userId", isEqualTo: userId)
            .whereField("sessionId", isEqualTo: sessionIdString)
            .getDocuments()

        var categoryIds: [UUID] = []
        await MainActor.run {
            for doc in categoriesSnapshot.documents {
                let data = doc.data()
                guard let model = CategoryModel(from: data),
                      let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
                else { continue }

                saveCategory(model, remoteUpdatedAt: remoteUpdatedAt, userId: userId)
                categoryIds.append(model.id)
            }
        }

        // 3. 下載 Products（by sessionId）
        let productsSnapshot = try await db.collection(Collection.products)
            .whereField("userId", isEqualTo: userId)
            .whereField("sessionId", isEqualTo: sessionIdString)
            .getDocuments()

        await MainActor.run {
            for doc in productsSnapshot.documents {
                let data = doc.data()
                guard let model = ProductModel(from: data),
                      let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
                else { continue }

                saveProduct(model, remoteUpdatedAt: remoteUpdatedAt, userId: userId)
            }
        }

        // 4. 下載 InventoryChanges（by sessionId）
        let existingChangeIds = await MainActor.run { fetchExistingInventoryChangeIds() }

        let changesSnapshot = try await db.collection(Collection.inventoryChanges)
            .whereField("userId", isEqualTo: userId)
            .whereField("sessionId", isEqualTo: sessionIdString)
            .getDocuments()

        await MainActor.run {
            for doc in changesSnapshot.documents {
                let data = doc.data()
                guard let model = InventoryChangeModel(from: data) else { continue }
                if existingChangeIds.contains(model.id) { continue }
                createInventoryChange(model, userId: userId)
            }
        }

        print("✅ 下載 Session（含子項目）完成: \(id)")
    }

    // MARK: - Full Sync

    /// 全量同步：按 parent-first 順序下載所有資料，然後清理已刪除的
    func fullSync() async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        // 1. 按 parent-first 順序下載
        try await downloadAllSessions()
        try await downloadAllCategories()
        try await downloadAllProducts()
        try await downloadAllTransactions()
        try await downloadAllInventoryChanges()
        try await downloadAllQRCodes()

        // 2. 清理本地有但雲端沒有的資料
        reportProgress(step: "正在清理已刪除的資料...", entity: "cleanup", progress: 6.0 / 7.0)
        try await cleanUpDeletedEntities(userId: userId)

        reportProgress(step: "同步完成", entity: "done", progress: 1.0)
        print("✅ Full Sync 完成")
    }

    // MARK: - Incremental Download

    /// 增量下載（給 Phase 5 Hybrid Listener 用）
    func downloadEntities(
        sessionIds: [UUID] = [],
        categoryIds: [UUID] = [],
        productIds: [UUID] = [],
        transactionIds: [UUID] = [],
        inventoryChangeIds: [UUID] = [],
        qrCodeIds: [UUID] = []
    ) async throws {
        // 按 parent-first 順序下載
        for id in sessionIds {
            try await downloadSession(id: id)
        }
        for id in categoryIds {
            try await downloadCategory(id: id)
        }
        for id in productIds {
            try await downloadProduct(id: id)
        }
        for id in transactionIds {
            try await downloadTransaction(id: id)
        }
        for id in inventoryChangeIds {
            try await downloadInventoryChange(id: id)
        }
        for id in qrCodeIds {
            try await downloadQRCode(id: id)
        }
    }

    // MARK: - Sync From Server (for Hybrid Listener)

    /// 從 Firestore 同步單一實體（下載或偵測刪除）
    /// 供 HybridSyncListener 使用
    /// - Returns: true 表示實體存在並已同步，false 表示實體已從 Firestore 刪除
    func syncFromServer(type: SyncEntityType, id: UUID) async throws -> Bool {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let collectionName: String
        switch type {
        case .session: collectionName = Collection.sessions
        case .category: collectionName = Collection.categories
        case .product: collectionName = Collection.products
        case .transaction: collectionName = Collection.transactions
        case .inventoryChange: collectionName = Collection.inventoryChanges
        case .qrCode: collectionName = Collection.qrCodes
        }

        let doc = try await db.collection(collectionName).document(id.uuidString).getDocument()

        guard doc.exists else {
            // 文件已從 Firestore 刪除 → 刪除本地對應實體
            await MainActor.run {
                deleteLocalEntity(type: type, id: id)
            }
            return false
        }

        guard let data = doc.data(), data["userId"] as? String == userId else {
            return true // 文件存在但不屬於當前用戶，跳過
        }

        // 文件存在，根據類型執行對應的 save/create 邏輯
        switch type {
        case .session:
            guard let model = SessionModel(from: data),
                  let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
            else { return true }
            await MainActor.run {
                saveSession(model, remoteUpdatedAt: remoteUpdatedAt, userId: userId)
            }

        case .category:
            guard let model = CategoryModel(from: data),
                  let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
            else { return true }
            await MainActor.run {
                saveCategory(model, remoteUpdatedAt: remoteUpdatedAt, userId: userId)
            }

        case .product:
            guard let model = ProductModel(from: data),
                  let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
            else { return true }
            await MainActor.run {
                saveProduct(model, remoteUpdatedAt: remoteUpdatedAt, userId: userId)
            }

        case .transaction:
            guard let model = TransactionModel(from: data) else { return true }
            await MainActor.run {
                createTransaction(model, userId: userId)
            }

        case .inventoryChange:
            guard let model = InventoryChangeModel(from: data) else { return true }
            await MainActor.run {
                createInventoryChange(model, userId: userId)
            }

        case .qrCode:
            guard let model = QRCodeModel(from: data),
                  let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
            else { return true }
            await MainActor.run {
                saveQRCode(model, remoteUpdatedAt: remoteUpdatedAt, userId: userId)
            }
        }

        return true
    }

    /// 刪除本地 CoreData 中的實體（Listener 偵測到 Firestore 文件已刪除時呼叫）
    @MainActor
    private func deleteLocalEntity(type: SyncEntityType, id: UUID) {
        let entityName: String
        switch type {
        case .session: entityName = "CDSessionEntity"
        case .category: entityName = "CDCategoryEntity"
        case .product: entityName = "CDProductEntity"
        case .transaction: entityName = "CDTransactionEntity"
        case .inventoryChange: entityName = "CDInventoryChangeEntity"
        case .qrCode: entityName = "CDQRCodeEntity"
        }

        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                context.delete(entity)
                try context.save()
                print("🗑️ Listener: 本地 \(type.rawValue) 已刪除: \(id)")
            }
        } catch {
            print("❌ deleteLocalEntity 失敗: \(error)")
        }
    }

    // MARK: - Cleanup Deleted Entities

    /// 清理本地有但雲端沒有的資料
    /// 只清理 syncStatus == "synced" 的資料（保留 "pending" 尚未上傳的）
    private func cleanUpDeletedEntities(userId: String) async throws {
        // 從 Firestore 取得所有遠端 ID
        let remoteSessions = try await fetchRemoteIds(collection: Collection.sessions, userId: userId)
        let remoteCategories = try await fetchRemoteIds(collection: Collection.categories, userId: userId)
        let remoteProducts = try await fetchRemoteIds(collection: Collection.products, userId: userId)
        let remoteTransactions = try await fetchRemoteIds(collection: Collection.transactions, userId: userId)
        let remoteInventoryChanges = try await fetchRemoteIds(collection: Collection.inventoryChanges, userId: userId)
        let remoteQRCodes = try await fetchRemoteIds(collection: Collection.qrCodes, userId: userId)

        await MainActor.run {
            // 清理各類型（由 child-first 到 parent）
            cleanUpLocalEntities(
                entityName: "CDInventoryChangeEntity",
                remoteIds: remoteInventoryChanges,
                userId: userId
            )
            cleanUpLocalEntities(
                entityName: "CDTransactionEntity",
                remoteIds: remoteTransactions,
                userId: userId
            )
            cleanUpLocalEntities(
                entityName: "CDProductEntity",
                remoteIds: remoteProducts,
                userId: userId
            )
            cleanUpLocalEntities(
                entityName: "CDCategoryEntity",
                remoteIds: remoteCategories,
                userId: userId
            )
            cleanUpLocalEntities(
                entityName: "CDSessionEntity",
                remoteIds: remoteSessions,
                userId: userId
            )
            cleanUpLocalEntities(
                entityName: "CDQRCodeEntity",
                remoteIds: remoteQRCodes,
                userId: userId
            )

            do {
                try context.save()
            } catch {
                print("❌ 清理已刪除資料 save 失敗: \(error)")
            }
        }
    }

    // MARK: - Private Helpers

    // MARK: LWW Save Helpers

    /// 儲存 Session（LWW 策略）
    @MainActor
    private func saveSession(_ model: SessionModel, remoteUpdatedAt: Date, userId: String) {
        let request: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)

        do {
            let results = try context.fetch(request)
            let entity: CDSessionEntity

            if let existing = results.first {
                // LWW：本地較新就跳過
                if let localUpdatedAt = existing.updatedAt, localUpdatedAt >= remoteUpdatedAt {
                    return
                }
                entity = existing
            } else {
                entity = CDSessionEntity(context: context)
            }

            entity.update(from: model, context: context)
            entity.userId = userId
            entity.updatedAt = remoteUpdatedAt
            entity.syncStatus = SyncStatus.synced.rawValue

            try context.save()
        } catch {
            print("❌ saveSession 失敗: \(error)")
        }
    }

    /// 儲存 Category（LWW 策略）— 需重建 category.session relationship
    @MainActor
    private func saveCategory(_ model: CategoryModel, remoteUpdatedAt: Date, userId: String) {
        // 必須找到對應的 Session，找不到就跳過
        guard let sessionId = model.sessionId else { return }

        let sessionRequest: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
        sessionRequest.predicate = NSPredicate(format: "id == %@", sessionId as CVarArg)

        do {
            guard let sessionEntity = try context.fetch(sessionRequest).first else {
                print("⚠️ saveCategory 跳過: 找不到 Session \(sessionId)")
                return
            }

            let request: NSFetchRequest<CDCategoryEntity> = CDCategoryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)

            let results = try context.fetch(request)
            let entity: CDCategoryEntity

            if let existing = results.first {
                // LWW：本地較新就跳過
                if let localUpdatedAt = existing.updatedAt, localUpdatedAt >= remoteUpdatedAt {
                    return
                }
                entity = existing
            } else {
                entity = CDCategoryEntity(context: context)
            }

            entity.update(from: model, context: context)
            entity.session = sessionEntity
            entity.userId = userId
            entity.updatedAt = remoteUpdatedAt
            entity.syncStatus = SyncStatus.synced.rawValue

            try context.save()
        } catch {
            print("❌ saveCategory 失敗: \(error)")
        }
    }

    /// 儲存 Product（LWW 策略）— 需重建 product.category relationship、保留 imageData
    @MainActor
    private func saveProduct(_ model: ProductModel, remoteUpdatedAt: Date, userId: String) {
        let categoryRequest: NSFetchRequest<CDCategoryEntity> = CDCategoryEntity.fetchRequest()
        categoryRequest.predicate = NSPredicate(format: "id == %@", model.categoryId as CVarArg)

        do {
            guard let categoryEntity = try context.fetch(categoryRequest).first else {
                print("⚠️ saveProduct 跳過: 找不到 Category \(model.categoryId)")
                return
            }

            let request: NSFetchRequest<CDProductEntity> = CDProductEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)

            let results = try context.fetch(request)
            let entity: CDProductEntity

            // 暫存現有 imageData（下載的 model.imageData 為 nil，需保留本地圖片）
            var existingImageData: Data?

            if let existing = results.first {
                // LWW：本地較新就跳過
                if let localUpdatedAt = existing.updatedAt, localUpdatedAt >= remoteUpdatedAt {
                    return
                }
                existingImageData = existing.imageData
                entity = existing
            } else {
                entity = CDProductEntity(context: context)
            }

            entity.update(from: model, context: context)

            // 還原 imageData（model.imageData 為 nil，update 不會覆蓋，但以防萬一再保護一次）
            if entity.imageData == nil, let preserved = existingImageData {
                entity.imageData = preserved
            }

            entity.category = categoryEntity
            entity.userId = userId
            entity.updatedAt = remoteUpdatedAt
            entity.syncStatus = SyncStatus.synced.rawValue

            try context.save()
        } catch {
            print("❌ saveProduct 失敗: \(error)")
        }
    }

    /// 儲存 QRCode（LWW 策略）— 保留 imageData
    @MainActor
    private func saveQRCode(_ model: QRCodeModel, remoteUpdatedAt: Date, userId: String) {
        let request: NSFetchRequest<CDQRCodeEntity> = CDQRCodeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)

        do {
            let results = try context.fetch(request)
            let entity: CDQRCodeEntity

            // 暫存現有 imageData
            var existingImageData: Data?

            if let existing = results.first {
                // LWW：本地較新就跳過
                if let localUpdatedAt = existing.updatedAt, localUpdatedAt >= remoteUpdatedAt {
                    return
                }
                existingImageData = existing.imageData
                entity = existing
            } else {
                entity = CDQRCodeEntity(context: context)
            }

            entity.update(from: model, context: context)

            // QRCode 的 update(from:) 會寫 model.imageData ?? Data()
            // 因此必須明確還原 existing imageData
            if let preserved = existingImageData, !preserved.isEmpty {
                entity.imageData = preserved
            }

            entity.userId = userId
            entity.updatedAt = remoteUpdatedAt
            entity.syncStatus = SyncStatus.synced.rawValue

            try context.save()
        } catch {
            print("❌ saveQRCode 失敗: \(error)")
        }
    }

    // MARK: Skip-if-exists Create Helpers

    /// 建立 Transaction（存在就跳過）— 重建 transaction.session relationship
    @MainActor
    private func createTransaction(_ model: TransactionModel, userId: String) {
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)

        do {
            let existing = try context.fetch(request).first
            if existing != nil { return } // 已存在，跳過

            let entity = CDTransactionEntity(context: context)
            entity.update(from: model, context: context)
            entity.userId = userId
            entity.syncStatus = SyncStatus.synced.rawValue

            // 重建 session relationship（optional）
            let sessionRequest: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
            sessionRequest.predicate = NSPredicate(format: "id == %@", model.sessionId as CVarArg)
            entity.session = try context.fetch(sessionRequest).first

            try context.save()
        } catch {
            print("❌ createTransaction 失敗: \(error)")
        }
    }

    /// 建立 InventoryChange（存在就跳過）— 重建 inventoryChange.session relationship
    @MainActor
    private func createInventoryChange(_ model: InventoryChangeModel, userId: String) {
        let request: NSFetchRequest<CDInventoryChangeEntity> = CDInventoryChangeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)

        do {
            let existing = try context.fetch(request).first
            if existing != nil { return } // 已存在，跳過

            let entity = CDInventoryChangeEntity(context: context)
            entity.update(from: model, context: context)
            entity.userId = userId
            entity.syncStatus = SyncStatus.synced.rawValue

            // 重建 session relationship（optional）
            if let sessionId = model.sessionId {
                let sessionRequest: NSFetchRequest<CDSessionEntity> = CDSessionEntity.fetchRequest()
                sessionRequest.predicate = NSPredicate(format: "id == %@", sessionId as CVarArg)
                entity.session = try context.fetch(sessionRequest).first
            }

            try context.save()
        } catch {
            print("❌ createInventoryChange 失敗: \(error)")
        }
    }

    // MARK: Batch Query Helpers

    /// 批次查詢所有本地 Transaction ID
    @MainActor
    private func fetchExistingTransactionIds() -> Set<UUID> {
        let request: NSFetchRequest<CDTransactionEntity> = CDTransactionEntity.fetchRequest()
        request.propertiesToFetch = ["id"]

        do {
            let results = try context.fetch(request)
            return Set(results.map { $0.id })
        } catch {
            print("❌ fetchExistingTransactionIds 失敗: \(error)")
            return []
        }
    }

    /// 批次查詢所有本地 InventoryChange ID
    @MainActor
    private func fetchExistingInventoryChangeIds() -> Set<UUID> {
        let request: NSFetchRequest<CDInventoryChangeEntity> = CDInventoryChangeEntity.fetchRequest()
        request.propertiesToFetch = ["id"]

        do {
            let results = try context.fetch(request)
            return Set(results.map { $0.id })
        } catch {
            print("❌ fetchExistingInventoryChangeIds 失敗: \(error)")
            return []
        }
    }

    // MARK: Remote ID Fetching

    /// 從 Firestore 取得某 collection 中屬於該 user 的所有 ID
    private func fetchRemoteIds(collection: String, userId: String) async throws -> Set<UUID> {
        let snapshot = try await db.collection(collection)
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        var ids = Set<UUID>()
        for doc in snapshot.documents {
            if let idString = doc.data()["id"] as? String,
               let id = UUID(uuidString: idString) {
                ids.insert(id)
            }
        }
        return ids
    }

    // MARK: Local Cleanup

    /// 清理本地 entity：刪除 syncStatus=="synced" 且不在遠端的資料
    @MainActor
    private func cleanUpLocalEntities(entityName: String, remoteIds: Set<UUID>, userId: String) {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(
            format: "userId == %@ AND syncStatus == %@",
            userId, SyncStatus.synced.rawValue
        )

        do {
            let results = try context.fetch(request)
            for entity in results {
                guard let entityId = entity.value(forKey: "id") as? UUID else { continue }
                if !remoteIds.contains(entityId) {
                    context.delete(entity)
                }
            }
        } catch {
            print("❌ cleanUpLocalEntities(\(entityName)) 失敗: \(error)")
        }
    }
}
