//
//  FirestoreUploader.swift
//  Tilli
//
//  Created by Peiyun on 2026/2/4.
//  Created for CoreData + Firebase Sync
//  處理各 Entity 上傳到 Firestore，支援 Batch Write 確保原子性
//  整合 Hybrid Listener：每次上傳同時更新 syncState
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Firestore 上傳服務
/// 負責將本地資料上傳到 Firestore，支援單一上傳和批次上傳
/// 每次上傳都會同時更新 syncState，供 Hybrid Listener 使用
class FirestoreUploader {
    static let shared = FirestoreUploader()

    private let db = Firestore.firestore()

    /// pendingChanges 上限，超過就清空（觸發全量同步）
    private let pendingChangesLimit = 50

    private init() {}

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

    /// syncState 中 pendingChanges 的 key
    private enum SyncStateKey: String {
        case sessions
        case categories
        case products
        case transactions
        case inventoryChanges
        case qrCodes
    }

    // MARK: - SyncState Reference

    /// 取得 syncState 文件的 reference
    private func syncStateRef(userId: String) -> DocumentReference {
        return db.collection("users").document(userId)
            .collection("private").document("syncState")
    }

    // MARK: - Initialize SyncState

    /// 初始化 syncState（首次登入或 syncState 不存在時呼叫）
    func initializeSyncState() async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let ref = syncStateRef(userId: userId)
        let doc = try await ref.getDocument()

        if !doc.exists {
            try await ref.setData([
                "version": 0,
                "lastUpdate": FieldValue.serverTimestamp(),
                "pendingChanges": [
                    SyncStateKey.sessions.rawValue: [],
                    SyncStateKey.categories.rawValue: [],
                    SyncStateKey.products.rawValue: [],
                    SyncStateKey.transactions.rawValue: [],
                    SyncStateKey.inventoryChanges.rawValue: [],
                    SyncStateKey.qrCodes.rawValue: []
                ]
            ])
        }
    }

    /// 檢查 syncState 是否存在
    func syncStateExists() async throws -> Bool {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let ref = syncStateRef(userId: userId)
        let doc = try await ref.getDocument()
        return doc.exists
    }

    // MARK: - Trim PendingChanges

    /// 清理超過上限的 pendingChanges（非同步呼叫，不影響主流程）
    private func trimPendingChangesIfNeeded(userId: String, entityType: SyncStateKey) async {
        let ref = syncStateRef(userId: userId)

        do {
            let doc = try await ref.getDocument()
            guard let data = doc.data(),
                  let pendingChanges = data["pendingChanges"] as? [String: [String]],
                  let ids = pendingChanges[entityType.rawValue],
                  ids.count > pendingChangesLimit else { return }

            // 超過上限，清空該類別
            try await ref.updateData([
                "pendingChanges.\(entityType.rawValue)": FieldValue.delete()
            ])
        } catch {
            print("trimPendingChanges error: \(error)")
        }
    }

    // MARK: - Single Entity Upload

    /// 上傳 Session
    func uploadSession(_ session: SessionModel) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let batch = db.batch()

        // 1. 上傳資料
        let sessionRef = db.collection(Collection.sessions).document(session.id.uuidString)
        let data = session.toFirestoreData(userId: userId)
        batch.setData(data, forDocument: sessionRef)

        // 2. 更新 syncState
        let syncRef = syncStateRef(userId: userId)
        batch.updateData([
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.sessions.rawValue)": FieldValue.arrayUnion([session.id.uuidString])
        ], forDocument: syncRef)

        try await batch.commit()

        // 3. 檢查是否超過上限
        Task {
            await trimPendingChangesIfNeeded(userId: userId, entityType: .sessions)
        }
    }

    /// 上傳 Category
    func uploadCategory(_ category: CategoryModel, sessionId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let batch = db.batch()

        // 1. 上傳資料
        let categoryRef = db.collection(Collection.categories).document(category.id.uuidString)
        let data = category.toFirestoreData(userId: userId, sessionId: sessionId)
        batch.setData(data, forDocument: categoryRef)

        // 2. 更新 syncState
        let syncRef = syncStateRef(userId: userId)
        batch.updateData([
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.categories.rawValue)": FieldValue.arrayUnion([category.id.uuidString])
        ], forDocument: syncRef)

        try await batch.commit()

        Task {
            await trimPendingChangesIfNeeded(userId: userId, entityType: .categories)
        }
    }

    /// 上傳 Product
    /// - Parameters:
    ///   - product: 產品資料
    ///   - imageURL: 圖片 URL（如果有圖片，需先上傳到 Storage 取得 URL）
    func uploadProduct(_ product: ProductModel, imageURL: String? = nil) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        var productToUpload = product
        if let url = imageURL {
            productToUpload.imageURL = url
        }

        let batch = db.batch()

        // 1. 上傳資料
        let productRef = db.collection(Collection.products).document(product.id.uuidString)
        let data = productToUpload.toFirestoreData(userId: userId)
        batch.setData(data, forDocument: productRef)

        // 2. 更新 syncState
        let syncRef = syncStateRef(userId: userId)
        batch.updateData([
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.products.rawValue)": FieldValue.arrayUnion([product.id.uuidString])
        ], forDocument: syncRef)

        try await batch.commit()

        Task {
            await trimPendingChangesIfNeeded(userId: userId, entityType: .products)
        }
    }

    /// 上傳 Transaction
    func uploadTransaction(_ transaction: TransactionModel) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let batch = db.batch()

        // 1. 上傳資料
        let transactionRef = db.collection(Collection.transactions).document(transaction.id.uuidString)
        let data = transaction.toFirestoreData(userId: userId)
        batch.setData(data, forDocument: transactionRef)

        // 2. 更新 syncState
        let syncRef = syncStateRef(userId: userId)
        batch.updateData([
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.transactions.rawValue)": FieldValue.arrayUnion([transaction.id.uuidString])
        ], forDocument: syncRef)

        try await batch.commit()

        Task {
            await trimPendingChangesIfNeeded(userId: userId, entityType: .transactions)
        }
    }

    /// 上傳 InventoryChange
    func uploadInventoryChange(_ change: InventoryChangeModel, sessionId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let batch = db.batch()

        // 1. 上傳資料
        let changeRef = db.collection(Collection.inventoryChanges).document(change.id.uuidString)
        let data = change.toFirestoreData(userId: userId, sessionId: sessionId)
        batch.setData(data, forDocument: changeRef)

        // 2. 更新 syncState
        let syncRef = syncStateRef(userId: userId)
        batch.updateData([
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.inventoryChanges.rawValue)": FieldValue.arrayUnion([change.id.uuidString])
        ], forDocument: syncRef)

        try await batch.commit()

        Task {
            await trimPendingChangesIfNeeded(userId: userId, entityType: .inventoryChanges)
        }
    }

    /// 上傳 QRCode
    /// - Parameters:
    ///   - qrCode: QRCode 資料
    ///   - imageURL: 圖片 URL（需先上傳到 Storage 取得 URL）
    func uploadQRCode(_ qrCode: QRCodeModel, imageURL: String? = nil) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        var qrCodeToUpload = qrCode
        if let url = imageURL {
            qrCodeToUpload.imageURL = url
        }

        let batch = db.batch()

        // 1. 上傳資料
        let qrCodeRef = db.collection(Collection.qrCodes).document(qrCode.id.uuidString)
        let data = qrCodeToUpload.toFirestoreData(userId: userId)
        batch.setData(data, forDocument: qrCodeRef)

        // 2. 更新 syncState
        let syncRef = syncStateRef(userId: userId)
        batch.updateData([
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.qrCodes.rawValue)": FieldValue.arrayUnion([qrCode.id.uuidString])
        ], forDocument: syncRef)

        try await batch.commit()

        Task {
            await trimPendingChangesIfNeeded(userId: userId, entityType: .qrCodes)
        }
    }

    // MARK: - Update Entity

    /// 更新 Session
    func updateSession(_ session: SessionModel) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let batch = db.batch()

        // 1. 更新資料
        let sessionRef = db.collection(Collection.sessions).document(session.id.uuidString)
        let data = session.toFirestoreData(userId: userId)
        batch.updateData(data, forDocument: sessionRef)

        // 2. 更新 syncState
        let syncRef = syncStateRef(userId: userId)
        batch.updateData([
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.sessions.rawValue)": FieldValue.arrayUnion([session.id.uuidString])
        ], forDocument: syncRef)

        try await batch.commit()

        Task {
            await trimPendingChangesIfNeeded(userId: userId, entityType: .sessions)
        }
    }

    /// 更新 Category
    func updateCategory(_ category: CategoryModel, sessionId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let batch = db.batch()

        // 1. 更新資料
        let categoryRef = db.collection(Collection.categories).document(category.id.uuidString)
        let data = category.toFirestoreData(userId: userId, sessionId: sessionId)
        batch.updateData(data, forDocument: categoryRef)

        // 2. 更新 syncState
        let syncRef = syncStateRef(userId: userId)
        batch.updateData([
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.categories.rawValue)": FieldValue.arrayUnion([category.id.uuidString])
        ], forDocument: syncRef)

        try await batch.commit()

        Task {
            await trimPendingChangesIfNeeded(userId: userId, entityType: .categories)
        }
    }

    /// 更新 Product
    func updateProduct(_ product: ProductModel, imageURL: String? = nil) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        var productToUpdate = product
        if let url = imageURL {
            productToUpdate.imageURL = url
        }

        let batch = db.batch()

        // 1. 更新資料
        let productRef = db.collection(Collection.products).document(product.id.uuidString)
        let data = productToUpdate.toFirestoreData(userId: userId)
        batch.updateData(data, forDocument: productRef)

        // 2. 更新 syncState
        let syncRef = syncStateRef(userId: userId)
        batch.updateData([
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.products.rawValue)": FieldValue.arrayUnion([product.id.uuidString])
        ], forDocument: syncRef)

        try await batch.commit()

        Task {
            await trimPendingChangesIfNeeded(userId: userId, entityType: .products)
        }
    }


    // MARK: - Delete Entity

    /// 刪除 Session
    func deleteSession(_ sessionId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let batch = db.batch()

        // 1. 刪除資料
        let sessionRef = db.collection(Collection.sessions).document(sessionId.uuidString)
        batch.deleteDocument(sessionRef)

        // 2. 更新 syncState（version +1，加入 pendingChanges 供 Listener 增量偵測刪除）
        let syncRef = syncStateRef(userId: userId)
        batch.updateData([
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.sessions.rawValue)": FieldValue.arrayUnion([sessionId.uuidString])
        ], forDocument: syncRef)

        try await batch.commit()
    }

    /// 刪除 Category
    func deleteCategory(_ categoryId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let batch = db.batch()

        let categoryRef = db.collection(Collection.categories).document(categoryId.uuidString)
        batch.deleteDocument(categoryRef)

        let syncRef = syncStateRef(userId: userId)
        batch.updateData([
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.categories.rawValue)": FieldValue.arrayUnion([categoryId.uuidString])
        ], forDocument: syncRef)

        try await batch.commit()
    }

    /// 刪除 Product
    func deleteProduct(_ productId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let batch = db.batch()

        let productRef = db.collection(Collection.products).document(productId.uuidString)
        batch.deleteDocument(productRef)

        let syncRef = syncStateRef(userId: userId)
        batch.updateData([
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.products.rawValue)": FieldValue.arrayUnion([productId.uuidString])
        ], forDocument: syncRef)

        try await batch.commit()
    }

    /// 刪除 Product 及其所有 InventoryChanges（Cascade Delete）
    func deleteProductWithInventoryChanges(_ productId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let productIdString = productId.uuidString

        // 1. 查詢該產品的所有 InventoryChanges
        let changesSnapshot = try await db.collection(Collection.inventoryChanges)
            .whereField("userId", isEqualTo: userId)
            .whereField("productId", isEqualTo: productIdString)
            .getDocuments()

        let deletedChangeIds = changesSnapshot.documents.map { $0.documentID }

        // 2. 分批刪除 InventoryChanges（不更新 syncState）
        let chunks = changesSnapshot.documents.chunked(into: 450)

        for chunk in chunks {
            let batch = db.batch()
            for doc in chunk {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
        }

        // 3. 刪除 Product 本身 + 統一更新 syncState
        let finalBatch = db.batch()
        let productRef = db.collection(Collection.products).document(productIdString)
        finalBatch.deleteDocument(productRef)

        let syncRef = syncStateRef(userId: userId)
        var syncUpdate: [String: Any] = [
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.products.rawValue)": FieldValue.arrayUnion([productIdString])
        ]

        if deletedChangeIds.count > pendingChangesLimit {
            syncUpdate["pendingChanges.\(SyncStateKey.inventoryChanges.rawValue)"] = FieldValue.delete()
        } else if !deletedChangeIds.isEmpty {
            syncUpdate["pendingChanges.\(SyncStateKey.inventoryChanges.rawValue)"] = FieldValue.arrayUnion(deletedChangeIds)
        }

        finalBatch.updateData(syncUpdate, forDocument: syncRef)
        try await finalBatch.commit()
    }

    /// 刪除 InventoryChange
    func deleteInventoryChange(_ changeId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let batch = db.batch()

        let changeRef = db.collection(Collection.inventoryChanges).document(changeId.uuidString)
        batch.deleteDocument(changeRef)

        let syncRef = syncStateRef(userId: userId)
        batch.updateData([
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.inventoryChanges.rawValue)": FieldValue.arrayUnion([changeId.uuidString])
        ], forDocument: syncRef)

        try await batch.commit()
    }

    /// 刪除 QRCode
    func deleteQRCode(_ qrCodeId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let batch = db.batch()

        let qrCodeRef = db.collection(Collection.qrCodes).document(qrCodeId.uuidString)
        batch.deleteDocument(qrCodeRef)

        let syncRef = syncStateRef(userId: userId)
        batch.updateData([
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.qrCodes.rawValue)": FieldValue.arrayUnion([qrCodeId.uuidString])
        ], forDocument: syncRef)

        try await batch.commit()
    }

    // MARK: - Batch Upload (Parent-First)

    /// 批次上傳完整 Session（包含 Categories 和 Products）
    /// 使用 Batch Write 確保原子性，Parent-First 順序
    func uploadSessionWithChildren(_ session: SessionModel) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let batch = db.batch()

        // 收集所有 ID 用於更新 syncState
        let sessionIds: [String] = [session.id.uuidString]
        var categoryIds: [String] = []
        var productIds: [String] = []

        // 1. Parent: Session
        let sessionRef = db.collection(Collection.sessions).document(session.id.uuidString)
        let sessionData = session.toFirestoreData(userId: userId)
        batch.setData(sessionData, forDocument: sessionRef)

        // 2. Children: Categories
        for category in session.categories {
            let categoryRef = db.collection(Collection.categories).document(category.id.uuidString)
            let categoryData = category.toFirestoreData(userId: userId, sessionId: session.id)
            batch.setData(categoryData, forDocument: categoryRef)
            categoryIds.append(category.id.uuidString)

            // 3. Grandchildren: Products
            for product in category.products {
                let productRef = db.collection(Collection.products).document(product.id.uuidString)
                let productData = product.toFirestoreData(userId: userId)
                batch.setData(productData, forDocument: productRef)
                productIds.append(product.id.uuidString)
            }
        }

        // 4. 更新 syncState
        let syncRef = syncStateRef(userId: userId)

        // 計算總變更數，決定是否清空 pendingChanges
        let totalChanges = sessionIds.count + categoryIds.count + productIds.count

        if totalChanges > pendingChangesLimit {
            // 變更太多，只增加 version（觸發全量同步）
            batch.updateData([
                "version": FieldValue.increment(Int64(1)),
                "lastUpdate": FieldValue.serverTimestamp(),
                "pendingChanges.\(SyncStateKey.sessions.rawValue)": FieldValue.delete(),
                "pendingChanges.\(SyncStateKey.categories.rawValue)": FieldValue.delete(),
                "pendingChanges.\(SyncStateKey.products.rawValue)": FieldValue.delete()
            ], forDocument: syncRef)
        } else {
            // 正常更新 pendingChanges
            batch.updateData([
                "version": FieldValue.increment(Int64(1)),
                "lastUpdate": FieldValue.serverTimestamp(),
                "pendingChanges.\(SyncStateKey.sessions.rawValue)": FieldValue.arrayUnion(sessionIds),
                "pendingChanges.\(SyncStateKey.categories.rawValue)": FieldValue.arrayUnion(categoryIds),
                "pendingChanges.\(SyncStateKey.products.rawValue)": FieldValue.arrayUnion(productIds)
            ], forDocument: syncRef)
        }

        // 原子提交
        try await batch.commit()
    }

    /// 批次上傳多個 Categories
    func uploadCategories(_ categories: [CategoryModel], sessionId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        // Firestore batch 最多 500 筆，分批處理
        // 預留空間給 syncState 更新
        let chunks = categories.chunked(into: 400)

        for chunk in chunks {
            let batch = db.batch()
            var categoryIds: [String] = []

            for category in chunk {
                let ref = db.collection(Collection.categories).document(category.id.uuidString)
                let data = category.toFirestoreData(userId: userId, sessionId: sessionId)
                batch.setData(data, forDocument: ref)
                categoryIds.append(category.id.uuidString)
            }

            // 更新 syncState
            let syncRef = syncStateRef(userId: userId)
            if categoryIds.count > pendingChangesLimit {
                batch.updateData([
                    "version": FieldValue.increment(Int64(1)),
                    "lastUpdate": FieldValue.serverTimestamp(),
                    "pendingChanges.\(SyncStateKey.categories.rawValue)": FieldValue.delete()
                ], forDocument: syncRef)
            } else {
                batch.updateData([
                    "version": FieldValue.increment(Int64(1)),
                    "lastUpdate": FieldValue.serverTimestamp(),
                    "pendingChanges.\(SyncStateKey.categories.rawValue)": FieldValue.arrayUnion(categoryIds)
                ], forDocument: syncRef)
            }

            try await batch.commit()
        }
    }

    /// 批次上傳多個 Products
    func uploadProducts(_ products: [ProductModel]) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let chunks = products.chunked(into: 400)

        for chunk in chunks {
            let batch = db.batch()
            var productIds: [String] = []

            for product in chunk {
                let ref = db.collection(Collection.products).document(product.id.uuidString)
                let data = product.toFirestoreData(userId: userId)
                batch.setData(data, forDocument: ref)
                productIds.append(product.id.uuidString)
            }

            let syncRef = syncStateRef(userId: userId)
            if productIds.count > pendingChangesLimit {
                batch.updateData([
                    "version": FieldValue.increment(Int64(1)),
                    "lastUpdate": FieldValue.serverTimestamp(),
                    "pendingChanges.\(SyncStateKey.products.rawValue)": FieldValue.delete()
                ], forDocument: syncRef)
            } else {
                batch.updateData([
                    "version": FieldValue.increment(Int64(1)),
                    "lastUpdate": FieldValue.serverTimestamp(),
                    "pendingChanges.\(SyncStateKey.products.rawValue)": FieldValue.arrayUnion(productIds)
                ], forDocument: syncRef)
            }

            try await batch.commit()
        }
    }

    /// 批次上傳多個 Transactions
    func uploadTransactions(_ transactions: [TransactionModel]) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let chunks = transactions.chunked(into: 400)

        for chunk in chunks {
            let batch = db.batch()
            var transactionIds: [String] = []

            for transaction in chunk {
                let ref = db.collection(Collection.transactions).document(transaction.id.uuidString)
                let data = transaction.toFirestoreData(userId: userId)
                batch.setData(data, forDocument: ref)
                transactionIds.append(transaction.id.uuidString)
            }

            let syncRef = syncStateRef(userId: userId)
            if transactionIds.count > pendingChangesLimit {
                batch.updateData([
                    "version": FieldValue.increment(Int64(1)),
                    "lastUpdate": FieldValue.serverTimestamp(),
                    "pendingChanges.\(SyncStateKey.transactions.rawValue)": FieldValue.delete()
                ], forDocument: syncRef)
            } else {
                batch.updateData([
                    "version": FieldValue.increment(Int64(1)),
                    "lastUpdate": FieldValue.serverTimestamp(),
                    "pendingChanges.\(SyncStateKey.transactions.rawValue)": FieldValue.arrayUnion(transactionIds)
                ], forDocument: syncRef)
            }

            try await batch.commit()
        }
    }

    /// 批次上傳多個 InventoryChanges
    func uploadInventoryChanges(_ changes: [InventoryChangeModel], sessionId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let chunks = changes.chunked(into: 400)

        for chunk in chunks {
            let batch = db.batch()
            var changeIds: [String] = []

            for change in chunk {
                let ref = db.collection(Collection.inventoryChanges).document(change.id.uuidString)
                let data = change.toFirestoreData(userId: userId, sessionId: sessionId)
                batch.setData(data, forDocument: ref)
                changeIds.append(change.id.uuidString)
            }

            let syncRef = syncStateRef(userId: userId)
            if changeIds.count > pendingChangesLimit {
                batch.updateData([
                    "version": FieldValue.increment(Int64(1)),
                    "lastUpdate": FieldValue.serverTimestamp(),
                    "pendingChanges.\(SyncStateKey.inventoryChanges.rawValue)": FieldValue.delete()
                ], forDocument: syncRef)
            } else {
                batch.updateData([
                    "version": FieldValue.increment(Int64(1)),
                    "lastUpdate": FieldValue.serverTimestamp(),
                    "pendingChanges.\(SyncStateKey.inventoryChanges.rawValue)": FieldValue.arrayUnion(changeIds)
                ], forDocument: syncRef)
            }

            try await batch.commit()
        }
    }

    // MARK: - Cascade Delete

    /// 刪除 Session 及其所有相關資料（Cascade Delete）
    /// - Note: Transactions 不刪除，保留歷史記錄
    func deleteSessionWithChildren(_ sessionId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let sessionIdString = sessionId.uuidString

        // 1. 查詢所有子項目（加入 userId filter 以通過 Firestore Security Rules）
        let categoriesSnapshot = try await db.collection(Collection.categories)
            .whereField("userId", isEqualTo: userId)
            .whereField("sessionId", isEqualTo: sessionIdString)
            .getDocuments()

        let productsSnapshot = try await db.collection(Collection.products)
            .whereField("userId", isEqualTo: userId)
            .whereField("sessionId", isEqualTo: sessionIdString)
            .getDocuments()

        let changesSnapshot = try await db.collection(Collection.inventoryChanges)
            .whereField("userId", isEqualTo: userId)
            .whereField("sessionId", isEqualTo: sessionIdString)
            .getDocuments()

        // 收集所有被刪除的 ID（供 pendingChanges 使用）
        let deletedCategoryIds = categoriesSnapshot.documents.map { $0.documentID }
        let deletedProductIds = productsSnapshot.documents.map { $0.documentID }
        let deletedChangeIds = changesSnapshot.documents.map { $0.documentID }

        // 2. 收集所有需要刪除的文件
        var allDocuments: [QueryDocumentSnapshot] = []
        allDocuments.append(contentsOf: categoriesSnapshot.documents)
        allDocuments.append(contentsOf: productsSnapshot.documents)
        allDocuments.append(contentsOf: changesSnapshot.documents)

        // 3. 分批刪除子項目（不更新 syncState，最後統一更新）
        let chunks = allDocuments.chunked(into: 450)

        for chunk in chunks {
            let batch = db.batch()
            for doc in chunk {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
        }

        // 4. 刪除 Session 本身 + 統一更新 syncState（含所有被刪的 ID）
        let finalBatch = db.batch()
        let sessionRef = db.collection(Collection.sessions).document(sessionIdString)
        finalBatch.deleteDocument(sessionRef)

        let syncRef = syncStateRef(userId: userId)
        var syncUpdate: [String: Any] = [
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.sessions.rawValue)": FieldValue.arrayUnion([sessionIdString])
        ]

        // 各類型：超過上限就清空（觸發全量同步），否則加入 ID
        if deletedCategoryIds.count > pendingChangesLimit {
            syncUpdate["pendingChanges.\(SyncStateKey.categories.rawValue)"] = FieldValue.delete()
        } else if !deletedCategoryIds.isEmpty {
            syncUpdate["pendingChanges.\(SyncStateKey.categories.rawValue)"] = FieldValue.arrayUnion(deletedCategoryIds)
        }

        if deletedProductIds.count > pendingChangesLimit {
            syncUpdate["pendingChanges.\(SyncStateKey.products.rawValue)"] = FieldValue.delete()
        } else if !deletedProductIds.isEmpty {
            syncUpdate["pendingChanges.\(SyncStateKey.products.rawValue)"] = FieldValue.arrayUnion(deletedProductIds)
        }

        if deletedChangeIds.count > pendingChangesLimit {
            syncUpdate["pendingChanges.\(SyncStateKey.inventoryChanges.rawValue)"] = FieldValue.delete()
        } else if !deletedChangeIds.isEmpty {
            syncUpdate["pendingChanges.\(SyncStateKey.inventoryChanges.rawValue)"] = FieldValue.arrayUnion(deletedChangeIds)
        }

        finalBatch.updateData(syncUpdate, forDocument: syncRef)
        try await finalBatch.commit()

        // ⚠️ Transactions 不刪除，保留歷史記錄
    }

    /// 刪除 Category 及其所有 Products 和相關 InventoryChanges
    func deleteCategoryWithProducts(_ categoryId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let categoryIdString = categoryId.uuidString

        // 1. 查詢 Products（加入 userId filter 以通過 Firestore Security Rules）
        let productsSnapshot = try await db.collection(Collection.products)
            .whereField("userId", isEqualTo: userId)
            .whereField("categoryId", isEqualTo: categoryIdString)
            .getDocuments()

        let deletedProductIds = productsSnapshot.documents.map { $0.documentID }

        // 2. 查詢這些 Products 的所有 InventoryChanges
        var deletedChangeIds: [String] = []
        var allChangeDocs: [QueryDocumentSnapshot] = []

        for productDocId in deletedProductIds {
            let changesSnapshot = try await db.collection(Collection.inventoryChanges)
                .whereField("userId", isEqualTo: userId)
                .whereField("productId", isEqualTo: productDocId)
                .getDocuments()
            deletedChangeIds.append(contentsOf: changesSnapshot.documents.map { $0.documentID })
            allChangeDocs.append(contentsOf: changesSnapshot.documents)
        }

        // 3. 分批刪除 InventoryChanges + Products（不更新 syncState）
        var allDocuments: [QueryDocumentSnapshot] = []
        allDocuments.append(contentsOf: allChangeDocs)
        allDocuments.append(contentsOf: productsSnapshot.documents)

        let chunks = allDocuments.chunked(into: 450)

        for chunk in chunks {
            let batch = db.batch()
            for doc in chunk {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
        }

        // 4. 刪除 Category 本身 + 統一更新 syncState
        let finalBatch = db.batch()
        let categoryRef = db.collection(Collection.categories).document(categoryIdString)
        finalBatch.deleteDocument(categoryRef)

        let syncRef = syncStateRef(userId: userId)
        var syncUpdate: [String: Any] = [
            "version": FieldValue.increment(Int64(1)),
            "lastUpdate": FieldValue.serverTimestamp(),
            "pendingChanges.\(SyncStateKey.categories.rawValue)": FieldValue.arrayUnion([categoryIdString])
        ]

        if deletedProductIds.count > pendingChangesLimit {
            syncUpdate["pendingChanges.\(SyncStateKey.products.rawValue)"] = FieldValue.delete()
        } else if !deletedProductIds.isEmpty {
            syncUpdate["pendingChanges.\(SyncStateKey.products.rawValue)"] = FieldValue.arrayUnion(deletedProductIds)
        }

        if deletedChangeIds.count > pendingChangesLimit {
            syncUpdate["pendingChanges.\(SyncStateKey.inventoryChanges.rawValue)"] = FieldValue.delete()
        } else if !deletedChangeIds.isEmpty {
            syncUpdate["pendingChanges.\(SyncStateKey.inventoryChanges.rawValue)"] = FieldValue.arrayUnion(deletedChangeIds)
        }

        finalBatch.updateData(syncUpdate, forDocument: syncRef)
        try await finalBatch.commit()
    }

    // MARK: - Get Product Image URLs for Deletion

    /// 取得 Session 下所有產品的圖片 URL（用於刪除 Storage 圖片）
    func getProductImageURLs(forSessionId sessionId: UUID) async throws -> [String] {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let productsSnapshot = try await db.collection(Collection.products)
            .whereField("userId", isEqualTo: userId)
            .whereField("sessionId", isEqualTo: sessionId.uuidString)
            .getDocuments()

        return productsSnapshot.documents.compactMap { doc in
            doc.get("imageURL") as? String
        }.filter { !$0.isEmpty }
    }

    /// 取得 Category 下所有產品的圖片 URL
    func getProductImageURLs(forCategoryId categoryId: UUID) async throws -> [String] {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let productsSnapshot = try await db.collection(Collection.products)
            .whereField("userId", isEqualTo: userId)
            .whereField("categoryId", isEqualTo: categoryId.uuidString)
            .getDocuments()

        return productsSnapshot.documents.compactMap { doc in
            doc.get("imageURL") as? String
        }.filter { !$0.isEmpty }
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    /// 將陣列分割成指定大小的子陣列
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
