//
//  UserProfile.swift
//  Tilli
//
//  Created by Peiyun on 2025/1/20.
//

import Foundation
import FirebaseFirestore

struct UserProfile: Identifiable, Codable, Equatable {
    var id: String { uid }

    let uid: String
    var email: String
    var name: String
    var photoURL: String?
    let provider: AuthProvider
    var accountStatus: AccountStatus
    var membership: Membership
    var expiryDate: Date?
    let createdAt: Date
    var currentDeviceId: String?

    // MARK: - 認證提供者
    enum AuthProvider: String, Codable {
        case anonymous
        case email
        case apple
        case google
    }

    // MARK: - 帳號狀態
    enum AccountStatus: String, Codable {
        case guest      // 本機使用者（未登入）
        case member     // 已註冊會員
    }

    // MARK: - 會員等級
    enum Membership: String, Codable {
        case free
        case pro
    }

    // MARK: - 本機 Guest 識別碼
    static let guestUserId = "LocalUser"

    // MARK: - 建立本機 Guest 使用者
    static func createLocal() -> UserProfile {
        return UserProfile(
            uid: guestUserId,
            email: "",
            name: "",
            photoURL: nil,
            provider: .anonymous,
            accountStatus: .guest,
            membership: .free,
            expiryDate: nil,
            createdAt: Date(),
            currentDeviceId: nil
        )
    }

    // MARK: - 取得 email @ 前面的文字作為預設名稱
    private func emailPrefix(from email: String) -> String {
        return email.components(separatedBy: "@").first ?? "使用者"
    }

    // MARK: - 檢查 Pro 會員是否過期
    var isProExpired: Bool {
        guard membership == .pro, let expiryDate = expiryDate else {
            return false
        }
        return Date() > expiryDate
    }

    // MARK: - 姓名縮寫（顯示用）
    var nameInitials: String {
        return String(name.prefix(2))
    }
}

// MARK: - Firestore 轉換
extension UserProfile {

    // 從 Firestore Document 轉換
    init?(document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }

        guard let uid = data["uid"] as? String,
              let providerRaw = data["provider"] as? String,
              let provider = AuthProvider(rawValue: providerRaw),
              let accountStatusRaw = data["accountStatus"] as? String,
              let accountStatus = AccountStatus(rawValue: accountStatusRaw),
              let membershipRaw = data["membership"] as? String,
              let membership = Membership(rawValue: membershipRaw),
              let createdAtTimestamp = data["createdAt"] as? Timestamp
        else { return nil }

        self.uid = uid
        self.email = data["email"] as? String ?? ""
        self.name = data["name"] as? String ?? ""
        self.photoURL = data["photoURL"] as? String
        self.provider = provider
        self.accountStatus = accountStatus
        self.membership = membership
        self.expiryDate = (data["expiryDate"] as? Timestamp)?.dateValue()
        self.createdAt = createdAtTimestamp.dateValue()
        self.currentDeviceId = data["currentDeviceId"] as? String
    }

    // 轉換為 Firestore Dictionary
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "uid": uid,
            "email": email,
            "name": name,
            "provider": provider.rawValue,
            "accountStatus": accountStatus.rawValue,
            "membership": membership.rawValue,
            "createdAt": Timestamp(date: createdAt)
        ]

        if let photoURL = photoURL {
            data["photoURL"] = photoURL
        }

        if let expiryDate = expiryDate {
            data["expiryDate"] = Timestamp(date: expiryDate)
        }

        if let currentDeviceId = currentDeviceId {
            data["currentDeviceId"] = currentDeviceId
        }

        return data
    }
}
