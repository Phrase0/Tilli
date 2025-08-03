//
//  ProductModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/23.
//

import SwiftUI

struct ProductModel: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var sessionId: UUID               // 所屬 Session 的 ID
    var name: String
    var price: Double
    var stock: Int                   // 初始庫存
    var categoryId: UUID
    var category: String
    var note: String?
    var imageData: Data?             // 可選圖片（轉 UIImage 用 image）
    
    var image: UIImage? {
        get {
            guard let data = imageData else { return nil }
            return UIImage(data: data)
        }
        set {
            imageData = newValue?.jpegData(compressionQuality: 0.8)
        }
    }
}

extension ProductModel {
    init(entity: CDProductEntity) {
        self.id = entity.id
        self.sessionId = entity.sessionId
        self.name = entity.name
        self.price = entity.price
        self.stock = Int(entity.stock)
        self.note = entity.note
        self.imageData = entity.imageData
        
        self.categoryId = entity.category.id
        self.category = entity.category.name
    }
}

