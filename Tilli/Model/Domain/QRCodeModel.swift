//
//  QRCodeModel.swift
//  Tilli
//
//  Created by Peiyun on 2026/1/29.
//  Created for CoreData + Firebase Sync
//

import SwiftUI

struct QRCodeModel: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var imageData: Data?              // 本地圖片資料
    var imageURL: String?             // Firebase Storage URL
    var createdAt: Date = Date()

    // 計算屬性：取得 UIImage
    var image: UIImage? {
        get {
            guard let data = imageData else { return nil }
            return UIImage(data: data)
        }
        set {
            guard let newImage = newValue else {
                imageData = nil
                return
            }
            // 使用 ImageSyncService 處理：512x512 PNG 無損
            imageData = ImageSyncService.shared.processImageForLocal(newImage, type: .qrCode)
        }
    }
}

// MARK: - CoreData 轉換
extension QRCodeModel {
    init(entity: CDQRCodeEntity) {
        self.id = entity.id
        self.imageData = entity.imageData
        self.createdAt = entity.createdAt
        self.imageURL = entity.imageURL
    }
}
