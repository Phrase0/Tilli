//
//  FirestoreUploader.swift
//  Tilli
//
//  Created by Peiyun on 2026/2/4.
//  Created for CoreData + Firebase Sync
//  處理各 Entity 上傳到 Firestore，支援 Batch Write 確保原子性
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Firestore 上傳服務
/// 負責將本地資料上傳到 Firestore，支援單一上傳和批次上傳
class FirestoreUploader {
    static let shared = FirestoreUploader()

    private let db = Firestore.firestore()

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

    // MARK: - Single Entity Upload

    /// 上傳 Session
    func uploadSession(_ session: SessionModel) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let data = session.toFirestoreData(userId: userId)
        try await db.collection(Collection.sessions)
            .document(session.id.uuidString)
            .setData(data)
    }

    /// 上傳 Category
    func uploadCategory(_ category: CategoryModel, sessionId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let data = category.toFirestoreData(userId: userId, sessionId: sessionId)
        try await db.collection(Collection.categories)
            .document(category.id.uuidString)
            .setData(data)
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

        let data = productToUpload.toFirestoreData(userId: userId)
        try await db.collection(Collection.products)
            .document(product.id.uuidString)
            .setData(data)
    }

    /// 上傳 Transaction
    func uploadTransaction(_ transaction: TransactionModel) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let data = transaction.toFirestoreData(userId: userId)
        try await db.collection(Collection.transactions)
            .document(transaction.id.uuidString)
            .setData(data)
    }

    /// 上傳 InventoryChange
    func uploadInventoryChange(_ change: InventoryChangeModel, sessionId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let data = change.toFirestoreData(userId: userId, sessionId: sessionId)
        try await db.collection(Collection.inventoryChanges)
            .document(change.id.uuidString)
            .setData(data)
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

        let data = qrCodeToUpload.toFirestoreData(userId: userId)
        try await db.collection(Collection.qrCodes)
            .document(qrCode.id.uuidString)
            .setData(data)
    }

    // MARK: - Update Entity

    /// 更新 Session
    func updateSession(_ session: SessionModel) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let data = session.toFirestoreData(userId: userId)
        try await db.collection(Collection.sessions)
            .document(session.id.uuidString)
            .updateData(data)
    }

    /// 更新 Category
    func updateCategory(_ category: CategoryModel, sessionId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let data = category.toFirestoreData(userId: userId, sessionId: sessionId)
        try await db.collection(Collection.categories)
            .document(category.id.uuidString)
            .updateData(data)
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

        let data = productToUpdate.toFirestoreData(userId: userId)
        try await db.collection(Collection.products)
            .document(product.id.uuidString)
            .updateData(data)
    }

    /// 更新 QRCode
    func updateQRCode(_ qrCode: QRCodeModel, imageURL: String? = nil) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        var qrCodeToUpdate = qrCode
        if let url = imageURL {
            qrCodeToUpdate.imageURL = url
        }

        let data = qrCodeToUpdate.toFirestoreData(userId: userId)
        try await db.collection(Collection.qrCodes)
            .document(qrCode.id.uuidString)
            .updateData(data)
    }

    // MARK: - Delete Entity

    /// 刪除 Session
    func deleteSession(_ sessionId: UUID) async throws {
        try await db.collection(Collection.sessions)
            .document(sessionId.uuidString)
            .delete()
    }

    /// 刪除 Category
    func deleteCategory(_ categoryId: UUID) async throws {
        try await db.collection(Collection.categories)
            .document(categoryId.uuidString)
            .delete()
    }

    /// 刪除 Product
    func deleteProduct(_ productId: UUID) async throws {
        try await db.collection(Collection.products)
            .document(productId.uuidString)
            .delete()
    }

    /// 刪除 InventoryChange
    func deleteInventoryChange(_ changeId: UUID) async throws {
        try await db.collection(Collection.inventoryChanges)
            .document(changeId.uuidString)
            .delete()
    }

    /// 刪除 QRCode
    func deleteQRCode(_ qrCodeId: UUID) async throws {
        try await db.collection(Collection.qrCodes)
            .document(qrCodeId.uuidString)
            .delete()
    }

    // MARK: - Batch Upload (Parent-First)

    /// 批次上傳完整 Session（包含 Categories 和 Products）
    /// 使用 Batch Write 確保原子性，Parent-First 順序
    func uploadSessionWithChildren(_ session: SessionModel) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let batch = db.batch()

        // 1. Parent: Session
        let sessionRef = db.collection(Collection.sessions).document(session.id.uuidString)
        let sessionData = session.toFirestoreData(userId: userId)
        batch.setData(sessionData, forDocument: sessionRef)

        // 2. Children: Categories
        for category in session.categories {
            let categoryRef = db.collection(Collection.categories).document(category.id.uuidString)
            let categoryData = category.toFirestoreData(userId: userId, sessionId: session.id)
            batch.setData(categoryData, forDocument: categoryRef)

            // 3. Grandchildren: Products
            for product in category.products {
                let productRef = db.collection(Collection.products).document(product.id.uuidString)
                let productData = product.toFirestoreData(userId: userId)
                batch.setData(productData, forDocument: productRef)
            }
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
        let chunks = categories.chunked(into: 450)

        for chunk in chunks {
            let batch = db.batch()

            for category in chunk {
                let ref = db.collection(Collection.categories).document(category.id.uuidString)
                let data = category.toFirestoreData(userId: userId, sessionId: sessionId)
                batch.setData(data, forDocument: ref)
            }

            try await batch.commit()
        }
    }

    /// 批次上傳多個 Products
    func uploadProducts(_ products: [ProductModel]) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let chunks = products.chunked(into: 450)

        for chunk in chunks {
            let batch = db.batch()

            for product in chunk {
                let ref = db.collection(Collection.products).document(product.id.uuidString)
                let data = product.toFirestoreData(userId: userId)
                batch.setData(data, forDocument: ref)
            }

            try await batch.commit()
        }
    }

    /// 批次上傳多個 Transactions
    func uploadTransactions(_ transactions: [TransactionModel]) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let chunks = transactions.chunked(into: 450)

        for chunk in chunks {
            let batch = db.batch()

            for transaction in chunk {
                let ref = db.collection(Collection.transactions).document(transaction.id.uuidString)
                let data = transaction.toFirestoreData(userId: userId)
                batch.setData(data, forDocument: ref)
            }

            try await batch.commit()
        }
    }

    /// 批次上傳多個 InventoryChanges
    func uploadInventoryChanges(_ changes: [InventoryChangeModel], sessionId: UUID) async throws {
        guard let userId = currentUserId else {
            throw SyncError.authenticationRequired
        }

        let chunks = changes.chunked(into: 450)

        for chunk in chunks {
            let batch = db.batch()

            for change in chunk {
                let ref = db.collection(Collection.inventoryChanges).document(change.id.uuidString)
                let data = change.toFirestoreData(userId: userId, sessionId: sessionId)
                batch.setData(data, forDocument: ref)
            }

            try await batch.commit()
        }
    }

    // MARK: - Cascade Delete

    /// 刪除 Session 及其所有相關資料（Cascade Delete）
    /// - Note: Transactions 不刪除，保留歷史記錄
    func deleteSessionWithChildren(_ sessionId: UUID) async throws {
        let sessionIdString = sessionId.uuidString

        // 1. 查詢並刪除 Categories
        let categoriesSnapshot = try await db.collection(Collection.categories)
            .whereField("sessionId", isEqualTo: sessionIdString)
            .getDocuments()

        // 2. 查詢並刪除 Products
        let productsSnapshot = try await db.collection(Collection.products)
            .whereField("sessionId", isEqualTo: sessionIdString)
            .getDocuments()

        // 3. 查詢並刪除 InventoryChanges
        let changesSnapshot = try await db.collection(Collection.inventoryChanges)
            .whereField("sessionId", isEqualTo: sessionIdString)
            .getDocuments()

        // 收集所有需要刪除的文件
        var allDocuments: [QueryDocumentSnapshot] = []
        allDocuments.append(contentsOf: categoriesSnapshot.documents)
        allDocuments.append(contentsOf: productsSnapshot.documents)
        allDocuments.append(contentsOf: changesSnapshot.documents)

        // 分批刪除（Firestore batch 最多 500 筆）
        let chunks = allDocuments.chunked(into: 450)

        for chunk in chunks {
            let batch = db.batch()
            for doc in chunk {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
        }

        // 4. 刪除 Session 本身
        try await db.collection(Collection.sessions)
            .document(sessionIdString)
            .delete()

        // ⚠️ Transactions 不刪除，保留歷史記錄
    }

    /// 刪除 Category 及其所有 Products
    func deleteCategoryWithProducts(_ categoryId: UUID) async throws {
        let categoryIdString = categoryId.uuidString

        // 1. 查詢並刪除 Products
        let productsSnapshot = try await db.collection(Collection.products)
            .whereField("categoryId", isEqualTo: categoryIdString)
            .getDocuments()

        // 分批刪除
        let chunks = productsSnapshot.documents.chunked(into: 450)

        for chunk in chunks {
            let batch = db.batch()
            for doc in chunk {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
        }

        // 2. 刪除 Category 本身
        try await db.collection(Collection.categories)
            .document(categoryIdString)
            .delete()
    }

    // MARK: - Get Product Image URLs for Deletion

    /// 取得 Session 下所有產品的圖片 URL（用於刪除 Storage 圖片）
    func getProductImageURLs(forSessionId sessionId: UUID) async throws -> [String] {
        let productsSnapshot = try await db.collection(Collection.products)
            .whereField("sessionId", isEqualTo: sessionId.uuidString)
            .getDocuments()

        return productsSnapshot.documents.compactMap { doc in
            doc.get("imageURL") as? String
        }.filter { !$0.isEmpty }
    }

    /// 取得 Category 下所有產品的圖片 URL
    func getProductImageURLs(forCategoryId categoryId: UUID) async throws -> [String] {
        let productsSnapshot = try await db.collection(Collection.products)
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
