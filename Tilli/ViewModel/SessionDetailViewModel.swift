//
//  SessionDetailViewModel.swift
//  Tilli
//
//  Created by Peiyun on 2025/7/8.
//

import Foundation

class SessionDetailViewModel: ObservableObject {
    let session: SessionModel

    @Published var products: [ProductModel] = []
    @Published var quantities: [UUID: Int] = [:]
    @Published var selectedDiscounts: [UUID: Int] = [:]
    @Published var selectedTab: Int = 0

    private let productDataManager: ProductDataManager

    init(session: SessionModel, productDataManager: ProductDataManager = ProductDataManager()) {
        self.session = session
        self.productDataManager = productDataManager
        loadProducts()
    }
    
    func loadProducts() {
        products = productDataManager.fetchProducts(forSessionId: session.id)
    }

    func increaseQuantity(for product: ProductModel) {
        let current = quantities[product.id, default: 0]
        if current < product.stock {
            quantities[product.id] = current + 1
        }
    }

    func decreaseQuantity(for product: ProductModel) {
        let current = quantities[product.id, default: 0]
        if current > 0 {
            quantities[product.id] = current - 1
        }
    }

    func toggleDiscount(for product: ProductModel, percent: Int) {
        if selectedDiscounts[product.id] == percent {
            selectedDiscounts[product.id] = nil
        } else {
            selectedDiscounts[product.id] = percent
        }
    }

    func isDiscountSelected(for product: ProductModel, percent: Int) -> Bool {
        selectedDiscounts[product.id] == percent
    }

    func quantity(for product: ProductModel) -> Int {
        quantities[product.id, default: 0]
    }
    
    func clearAllQuantities() {
        quantities.removeAll()
        selectedDiscounts.removeAll()
    }

    func totalAmount() -> Int {
        products.reduce(0) { result, product in
            let qty = quantities[product.id, default: 0]
            let discount = selectedDiscounts[product.id] ?? 0
            let discountedPrice = product.price * (1 - Double(discount) / 100)
            let roundedTotal = (discountedPrice * Double(qty)).rounded()
            return result + Int(roundedTotal)
        }
    }

    
    func selectedProductsWithQuantityAndDiscount() -> [SummaryItemModel] {
        var result: [SummaryItemModel] = []
        for product in products {
            let qty = quantities[product.id, default: 0]
            if qty > 0 {
                let discount = selectedDiscounts[product.id, default: 0]
                result.append(SummaryItemModel(productId: product.id, name: product.name, price: product.price, quantity: qty, discount: discount, timestamp: Date()))
            }
        }
        return result
    }
}
