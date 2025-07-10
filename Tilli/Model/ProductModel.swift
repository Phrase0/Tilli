//
//  ProductModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/23.
//

import SwiftUI

struct ProductModel: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var price: Double
    var quantity: Int
    var description: String

    // Use Data to store image for Codable compliance
    var imageData: Data?

    var sessionId: UUID
    var category: String

    // Computed UIImage property to access image easily
    var image: UIImage? {
        get {
            guard let data = imageData else { return nil }
            return UIImage(data: data)
        }
        set {
            imageData = newValue?.jpegData(compressionQuality: 0.8)
        }
    }

    // Init with UIImage option
    init(
        id: UUID = UUID(),
        name: String,
        price: Double,
        quantity: Int,
        description: String,
        image: UIImage? = nil,
        sessionId: UUID,
        category: String
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.quantity = quantity
        self.description = description
        self.imageData = image?.jpegData(compressionQuality: 0.8)
        self.sessionId = sessionId
        self.category = category
    }
}
