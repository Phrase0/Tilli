//
//  UserRepository.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/20.
//

import Foundation
import CoreData
import FirebaseFirestore

class UserRepository {

    private let db = Firestore.firestore()
    private let collectionName = "users"
    private let context: NSManagedObjectContext

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.context = container.viewContext
    }

    // MARK: - 建立使用者
    func createUser(_ user: UserProfileModel) async throws {
        try await db.collection(collectionName)
            .document(user.uid)
            .setData(user.toFirestoreData())
    }

    // MARK: - 取得使用者
    func getUser(uid: String) async throws -> UserProfileModel? {
        let document = try await db.collection(collectionName)
            .document(uid)
            .getDocument()

        return UserProfileModel(document: document)
    }

    // MARK: - 更新特定欄位
    func updateUserFields(uid: String, fields: [String: Any]) async throws {
        try await db.collection(collectionName)
            .document(uid)
            .updateData(fields)
    }

    // MARK: - 更新 currentDeviceId
    func updateDeviceId(uid: String, deviceId: String) async throws {
        try await updateUserFields(uid: uid, fields: ["currentDeviceId": deviceId])
    }

    // MARK: - 更新會員等級
    func updateMembership(uid: String, membership: UserProfileModel.Membership, expiryDate: Date?) async throws {
        var fields: [String: Any] = [
            "membership": membership.rawValue
        ]

        if let expiryDate = expiryDate {
            fields["expiryDate"] = Timestamp(date: expiryDate)
        } else {
            fields["expiryDate"] = FieldValue.delete()
        }

        try await updateUserFields(uid: uid, fields: fields)
    }

    // MARK: - 更新個人資料
    func updateProfile(uid: String, name: String?, photoURL: String?) async throws {
        var fields: [String: Any] = [:]

        if let name = name {
            fields["name"] = name
        }

        if let photoURL = photoURL {
            fields["photoURL"] = photoURL
        }

        if !fields.isEmpty {
            fields["updatedAt"] = Timestamp(date: Date())
            try await updateUserFields(uid: uid, fields: fields)
        }
    }

    // MARK: - 本機快取（本地優先，跟商品/場次同一套模式）

    /// 寫入/更新本機的使用者資料快取（一定成功，不管有沒有網路）
    func saveUserProfileLocally(_ profile: UserProfileModel, syncStatus: SyncStatus = .pending) {
        let request: NSFetchRequest<CDUserProfileEntity> = CDUserProfileEntity.fetchRequest()
        request.predicate = NSPredicate(format: "uid == %@", profile.uid)

        do {
            let entity = try context.fetch(request).first ?? CDUserProfileEntity(context: context)
            entity.update(from: profile)
            entity.syncStatus = syncStatus.rawValue
            try context.save()
        } catch {
            print("❌ saveUserProfileLocally 失敗: \(error)")
        }
    }

    /// 更新本機快取的 photoURL（頭貼上傳成功後呼叫，不動 imageData——本機縮圖繼續留著供離線顯示）
    func updateLocalUserProfilePhotoURL(uid: String, photoURL: String?) {
        let request: NSFetchRequest<CDUserProfileEntity> = CDUserProfileEntity.fetchRequest()
        request.predicate = NSPredicate(format: "uid == %@", uid)

        do {
            if let entity = try context.fetch(request).first {
                entity.photoURL = photoURL
                try context.save()
            }
        } catch {
            print("❌ updateLocalUserProfilePhotoURL 失敗: \(error)")
        }
    }

    /// 讀取本機的使用者資料快取
    func loadLocalUserProfile(uid: String) -> UserProfileModel? {
        let request: NSFetchRequest<CDUserProfileEntity> = CDUserProfileEntity.fetchRequest()
        request.predicate = NSPredicate(format: "uid == %@", uid)

        do {
            return try context.fetch(request).first?.toModel()
        } catch {
            print("❌ loadLocalUserProfile 失敗: \(error)")
            return nil
        }
    }

    /// 標記本機使用者資料快取的同步狀態
    func updateLocalUserProfileSyncStatus(uid: String, status: SyncStatus) {
        let request: NSFetchRequest<CDUserProfileEntity> = CDUserProfileEntity.fetchRequest()
        request.predicate = NSPredicate(format: "uid == %@", uid)

        do {
            if let entity = try context.fetch(request).first {
                entity.syncStatus = status.rawValue
                try context.save()
            }
        } catch {
            print("❌ updateLocalUserProfileSyncStatus 失敗: \(error)")
        }
    }
}
