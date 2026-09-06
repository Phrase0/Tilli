//
//  CDUserProfileEntity+CoreDataProperties.swift
//  Tilli
//
//  Created by Peiyun on 2026/9/6.
//  本機使用者資料快取，讓 UserProfileModel 跟商品/場次一樣走「本地優先 + 背景同步」，
//  離線編輯個人資料時不會遺失，App 重啟時也能跟遠端資料做 LWW 比較，不會被舊資料蓋過去。
//

import Foundation
import CoreData

extension CDUserProfileEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDUserProfileEntity> {
        return NSFetchRequest<CDUserProfileEntity>(entityName: "CDUserProfileEntity")
    }

    @NSManaged public var uid: String
    @NSManaged public var email: String
    @NSManaged public var name: String
    @NSManaged public var photoURL: String?
    @NSManaged public var imageData: Data?
    @NSManaged public var provider: String
    @NSManaged public var accountStatus: String
    @NSManaged public var membership: String
    @NSManaged public var expiryDate: Date?
    @NSManaged public var createdAt: Date
    @NSManaged public var currentDeviceId: String?
    @NSManaged public var updatedAt: Date
    @NSManaged public var syncStatus: String

}

extension CDUserProfileEntity: Identifiable {

}

extension CDUserProfileEntity {

    func update(from model: UserProfileModel) {
        self.uid = model.uid
        self.email = model.email
        self.name = model.name
        self.photoURL = model.photoURL
        if let imageData = model.imageData {
            self.imageData = imageData
        }
        self.provider = model.provider.rawValue
        self.accountStatus = model.accountStatus.rawValue
        self.membership = model.membership.rawValue
        self.expiryDate = model.expiryDate
        self.createdAt = model.createdAt
        self.currentDeviceId = model.currentDeviceId
        self.updatedAt = model.updatedAt
    }

    func toModel() -> UserProfileModel? {
        guard let provider = UserProfileModel.AuthProvider(rawValue: provider),
              let accountStatus = UserProfileModel.AccountStatus(rawValue: accountStatus),
              let membership = UserProfileModel.Membership(rawValue: membership)
        else { return nil }

        return UserProfileModel(
            uid: uid,
            email: email,
            name: name,
            photoURL: photoURL,
            imageData: imageData,
            provider: provider,
            accountStatus: accountStatus,
            membership: membership,
            expiryDate: expiryDate,
            createdAt: createdAt,
            currentDeviceId: currentDeviceId,
            updatedAt: updatedAt
        )
    }
}
