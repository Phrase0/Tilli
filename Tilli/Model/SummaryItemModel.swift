//
//  Untitled.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/13.
//
import SwiftUI

struct SummaryItemModel: Identifiable {
    let id = UUID()
    let product: ProductModel
    let quantity: Int
    let discount: Int
    var total: Double {
        let discountedPrice = product.price * (1 - Double(discount) / 100)
        return discountedPrice * Double(quantity)
    }
}
