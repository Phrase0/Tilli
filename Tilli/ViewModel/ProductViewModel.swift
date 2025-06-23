//
//  ProductViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/6/23.
//

import SwiftUI

class ProductViewModel: ObservableObject {
    @Published var productsBySession: [UUID: [ProductModel]] = [:] // sessionId -> [Products]

    func addProduct(_ product: ProductModel) {
        let sessionId = product.sessionId
        if productsBySession[sessionId] != nil {
            productsBySession[sessionId]?.append(product)
        } else {
            productsBySession[sessionId] = [product]
        }
    }

    func getProducts(for sessionId: UUID) -> [ProductModel] {
        return productsBySession[sessionId] ?? []
    }
}
