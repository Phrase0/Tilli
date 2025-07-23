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
    var category: String
    var description: String

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
