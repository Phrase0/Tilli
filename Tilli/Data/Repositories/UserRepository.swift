//
//  UserRepository.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/20.
//

import Foundation
import FirebaseFirestore

class UserRepository {

    private let db = Firestore.firestore()
    private let collectionName = "users"

    // MARK: - 建立使用者
    func createUser(_ user: UserProfile) async throws {
        try await db.collection(collectionName)
            .document(user.uid)
            .setData(user.toFirestoreData())
    }

    // MARK: - 取得使用者
    func getUser(uid: String) async throws -> UserProfile? {
        let document = try await db.collection(collectionName)
            .document(uid)
            .getDocument()

        return UserProfile(document: document)
    }

    // MARK: - 更新使用者
    func updateUser(_ user: UserProfile) async throws {
        try await db.collection(collectionName)
            .document(user.uid)
            .setData(user.toFirestoreData(), merge: true)
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
    func updateMembership(uid: String, membership: UserProfile.Membership, expiryDate: Date?) async throws {
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
            try await updateUserFields(uid: uid, fields: fields)
        }
    }

    // MARK: - 刪除使用者
    func deleteUser(uid: String) async throws {
        try await db.collection(collectionName)
            .document(uid)
            .delete()
    }
}
