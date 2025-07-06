//
//  ProductModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/23.
//

import SwiftUI

struct ProductModel: Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var price: Double
    var quantity: Int
    var description: String
    var image: UIImage?
    var sessionId: UUID
    var category: String
}

